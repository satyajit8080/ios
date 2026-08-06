from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.deps import get_current_user, ip_throttle
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    new_opaque_token,
    sha256,
    verify_password,
)
from app.db.session import get_db
from app.models import PasswordResetToken, RefreshToken, ReminderSetting, User
from app.schemas.auth import (
    AppleSignInRequest,
    AuthResponse,
    ForgotPasswordRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
    TokenPair,
    UserOut,
)
from app.services import apple_auth
from app.services.mailer import send_password_reset

router = APIRouter(prefix="/auth", tags=["auth"])


def _issue(db: Session, user: User) -> TokenPair:
    refresh = create_refresh_token(str(user.id))
    db.add(
        RefreshToken(
            user_id=user.id,
            token_hash=sha256(refresh),
            expires_at=datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_DAYS),
        )
    )
    db.commit()
    return TokenPair(
        access_token=create_access_token(str(user.id), user.is_admin),
        refresh_token=refresh,
        expires_in=settings.ACCESS_TOKEN_MINUTES * 60,
    )


def _bootstrap(db: Session, user: User) -> None:
    if not db.scalar(select(ReminderSetting).where(ReminderSetting.user_id == user.id)):
        db.add(ReminderSetting(user_id=user.id))
        db.commit()


@router.post("/register", response_model=AuthResponse, status_code=201,
             dependencies=[Depends(ip_throttle("register", 10, 3600))])
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    email = payload.email.lower()
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(status.HTTP_409_CONFLICT, "That email is already registered.")
    user = User(email=email, hashed_password=hash_password(payload.password), full_name=payload.full_name)
    db.add(user)
    db.commit()
    db.refresh(user)
    _bootstrap(db, user)
    return AuthResponse(user=UserOut.model_validate(user), tokens=_issue(db, user))


@router.post("/login", response_model=AuthResponse,
             dependencies=[Depends(ip_throttle("login", 20, 900))])
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == payload.email.lower()))
    if not user or not user.hashed_password or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "That email and password don't match.")
    if not user.is_active:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This account is disabled.")
    _bootstrap(db, user)
    return AuthResponse(user=UserOut.model_validate(user), tokens=_issue(db, user))


@router.post("/apple", response_model=AuthResponse,
             dependencies=[Depends(ip_throttle("apple", 30, 900))])
def apple_sign_in(payload: AppleSignInRequest, db: Session = Depends(get_db)):
    try:
        claims = apple_auth.verify_identity_token(payload.identity_token)
    except Exception:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Apple sign-in could not be verified.")

    sub = claims["sub"]
    email = (claims.get("email") or f"{sub}@privaterelay.appleid.com").lower()

    user = db.scalar(select(User).where(User.apple_sub == sub))
    if not user:
        user = db.scalar(select(User).where(User.email == email))
    if not user:
        user = User(email=email, apple_sub=sub, full_name=payload.full_name)
        db.add(user)
    else:
        user.apple_sub = sub
        if payload.full_name and not user.full_name:
            user.full_name = payload.full_name
    db.commit()
    db.refresh(user)
    _bootstrap(db, user)
    return AuthResponse(user=UserOut.model_validate(user), tokens=_issue(db, user))


@router.post("/refresh", response_model=TokenPair)
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)):
    try:
        claims = decode_token(payload.refresh_token, "refresh")
    except Exception:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sign in again to continue.")

    row = db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == sha256(payload.refresh_token),
            RefreshToken.revoked.is_(False),
        )
    )
    if not row or row.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sign in again to continue.")

    user = db.get(User, row.user_id)
    if not user or not user.is_active or str(user.id) != claims["sub"]:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sign in again to continue.")

    row.revoked = True
    db.add(row)
    db.commit()
    return _issue(db, user)


@router.post("/logout", status_code=204)
def logout(payload: RefreshRequest, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    row = db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == sha256(payload.refresh_token), RefreshToken.user_id == user.id
        )
    )
    if row:
        row.revoked = True
        db.add(row)
        db.commit()


@router.post("/forgot-password", status_code=202,
             dependencies=[Depends(ip_throttle("forgot", 5, 3600))])
def forgot_password(payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == payload.email.lower()))
    if user and user.hashed_password:
        token = new_opaque_token()
        db.add(
            PasswordResetToken(
                user_id=user.id,
                token_hash=sha256(token),
                expires_at=datetime.now(timezone.utc) + timedelta(minutes=settings.RESET_TOKEN_MINUTES),
            )
        )
        db.commit()
        send_password_reset(user.email, token)
    return {"detail": "If that email has an account, a reset link is on its way."}


@router.post("/reset-password", status_code=204,
             dependencies=[Depends(ip_throttle("reset", 10, 3600))])
def reset_password(payload: ResetPasswordRequest, db: Session = Depends(get_db)):
    row = db.scalar(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == sha256(payload.token),
            PasswordResetToken.used.is_(False),
        )
    )
    if not row or row.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "This reset link has expired. Request a new one.")

    user = db.get(User, row.user_id)
    if not user:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "This reset link is no longer valid.")

    user.hashed_password = hash_password(payload.new_password)
    row.used = True
    db.query(RefreshToken).filter(RefreshToken.user_id == user.id).update({"revoked": True})
    db.add_all([user, row])
    db.commit()


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return UserOut.model_validate(user)
