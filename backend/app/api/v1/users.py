from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.db.session import get_db
from app.models import User
from app.schemas.auth import UserOut, UserUpdate
from app.services.metrics import age_from_birth_date, calorie_target, macro_targets, water_target_ml

router = APIRouter(prefix="/users", tags=["users"])


def recompute_targets(db: Session, user: User) -> None:
    age = age_from_birth_date(user.birth_date)
    current = user.start_weight_kg
    from sqlalchemy import select

    from app.models import WeightEntry  # local import avoids cycle at module load

    latest = db.scalar(
        select(WeightEntry).where(WeightEntry.user_id == user.id).order_by(WeightEntry.recorded_on.desc())
    )
    if latest:
        current = latest.weight_kg

    user.daily_calorie_target = calorie_target(
        current, user.height_cm, age, user.gender, user.activity_level, user.weekly_goal_kg
    )
    protein, _carbs, _fat = macro_targets(user.daily_calorie_target, current)
    user.daily_protein_target_g = protein
    if not user.daily_water_ml_target:
        user.daily_water_ml_target = water_target_ml(current)
    db.add(user)
    db.commit()
    db.refresh(user)


@router.get("/me", response_model=UserOut)
def read_me(user: User = Depends(get_current_user)):
    return UserOut.model_validate(user)


@router.patch("/me", response_model=UserOut)
def update_me(
    payload: UserUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        setattr(user, field, value)
    db.add(user)
    db.commit()
    db.refresh(user)
    recompute_targets(db, user)
    return UserOut.model_validate(user)


@router.delete("/me", status_code=204)
def delete_me(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    db.delete(user)
    db.commit()
