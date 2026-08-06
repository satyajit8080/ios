from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.redis_client import rate_limit
from app.core.security import decode_token
from app.db.session import get_db
from app.models import ReminderSetting, User

bearer = HTTPBearer(auto_error=True)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    try:
        payload = decode_token(credentials.credentials, "access")
        user_id = UUID(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sign in again to continue.")

    user = db.get(User, user_id)
    if not user or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sign in again to continue.")

    user.last_active_at = datetime.now(timezone.utc)
    db.add(user)
    db.commit()
    return user


def get_current_admin(user: User = Depends(get_current_user)) -> User:
    if not user.is_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Admin access required.")
    return user


def require_premium(user: User = Depends(get_current_user)) -> User:
    if not user.is_premium:
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            "Premium unlocks this feature.",
        )
    return user


def ensure_reminder_settings(db: Session, user: User) -> ReminderSetting:
    settings_row = db.query(ReminderSetting).filter(ReminderSetting.user_id == user.id).one_or_none()
    if settings_row is None:
        settings_row = ReminderSetting(user_id=user.id)
        db.add(settings_row)
        db.commit()
        db.refresh(settings_row)
    return settings_row


def throttle(bucket: str, limit: int, window: int):
    def dependency(request: Request, user: Optional[User] = Depends(get_current_user)):
        ident = str(user.id) if user else (request.client.host if request.client else "anon")
        if not rate_limit(f"rl:{bucket}:{ident}", limit, window):
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Too many requests. Try again shortly.")
        return user

    return dependency


def ip_throttle(bucket: str, limit: int, window: int):
    def dependency(request: Request):
        ident = request.client.host if request.client else "anon"
        if not rate_limit(f"rl:{bucket}:{ident}", limit, window):
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Too many requests. Try again shortly.")

    return dependency
