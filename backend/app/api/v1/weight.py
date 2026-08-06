from datetime import date, timedelta
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.db.session import get_db
from app.models import User, WeightEntry
from app.schemas.misc import PredictionOut
from app.schemas.tracking import WeightCreate, WeightOut, WeightStats
from app.services import prediction
from app.services.gamification import award_xp, evaluate_badges
from app.services.metrics import bmi, bmi_category, goal_progress_pct

router = APIRouter(prefix="/weight", tags=["weight"])


@router.post("", response_model=WeightOut, status_code=201)
def log_weight(payload: WeightCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    day = payload.recorded_on or date.today()
    if day > date.today():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "You can't log a weight for a future date.")

    entry = db.scalar(
        select(WeightEntry).where(WeightEntry.user_id == user.id, WeightEntry.recorded_on == day)
    )
    is_new = entry is None
    if entry is None:
        entry = WeightEntry(user_id=user.id, recorded_on=day)
    entry.weight_kg = payload.weight_kg
    entry.body_fat_pct = payload.body_fat_pct
    entry.note = payload.note
    db.add(entry)

    if user.start_weight_kg is None:
        user.start_weight_kg = payload.weight_kg
        db.add(user)
    if is_new:
        award_xp(db, user, "weight_logged")
    db.commit()
    db.refresh(entry)

    from app.api.v1.users import recompute_targets

    recompute_targets(db, user)
    evaluate_badges(db, user)
    return WeightOut.model_validate(entry)


@router.get("", response_model=List[WeightOut])
def list_weight(
    days: int = Query(90, ge=1, le=730),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    since = date.today() - timedelta(days=days)
    rows = db.scalars(
        select(WeightEntry)
        .where(WeightEntry.user_id == user.id, WeightEntry.recorded_on >= since)
        .order_by(WeightEntry.recorded_on.asc())
    ).all()
    return [WeightOut.model_validate(r) for r in rows]


@router.get("/stats", response_model=WeightStats)
def weight_stats(
    days: int = Query(90, ge=7, le=730),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    since = date.today() - timedelta(days=days)
    rows = db.scalars(
        select(WeightEntry)
        .where(WeightEntry.user_id == user.id, WeightEntry.recorded_on >= since)
        .order_by(WeightEntry.recorded_on.asc())
    ).all()

    current = rows[-1].weight_kg if rows else None
    start = user.start_weight_kg or (rows[0].weight_kg if rows else None)

    def change_over(window: int) -> float:
        if not rows or current is None:
            return 0.0
        cutoff = date.today() - timedelta(days=window)
        prior = [r for r in rows if r.recorded_on <= cutoff]
        base = prior[-1].weight_kg if prior else rows[0].weight_kg
        return round(current - base, 2)

    trend = 0.0
    if len(rows) >= 2:
        span_days = max((rows[-1].recorded_on - rows[0].recorded_on).days, 1)
        trend = round((rows[-1].weight_kg - rows[0].weight_kg) / span_days * 7, 2)

    value = bmi(current, user.height_cm)
    return WeightStats(
        current_kg=current,
        start_kg=start,
        goal_kg=user.goal_weight_kg,
        change_kg=round((current - start), 2) if current is not None and start is not None else 0.0,
        change_7d_kg=change_over(7),
        change_30d_kg=change_over(30),
        bmi=value,
        bmi_category=bmi_category(value),
        goal_progress_pct=goal_progress_pct(start, current, user.goal_weight_kg),
        trend_kg_per_week=trend,
        series=[WeightOut.model_validate(r) for r in rows],
    )


@router.delete("/{entry_id}", status_code=204)
def delete_weight(entry_id: UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    entry = db.scalar(select(WeightEntry).where(WeightEntry.id == entry_id, WeightEntry.user_id == user.id))
    if not entry:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That entry no longer exists.")
    db.delete(entry)
    db.commit()


@router.get("/prediction", response_model=PredictionOut)
def weight_prediction(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Projected trajectory toward the user's goal weight.

    Returns `has_enough_data=False` with a reason rather than guessing from a
    handful of entries — an early projection built on noise is worse than none.
    """
    rows = db.scalars(
        select(WeightEntry)
        .where(WeightEntry.user_id == user.id)
        .order_by(WeightEntry.recorded_on.asc())
    ).all()

    result = prediction.predict(
        entries=[(row.recorded_on, row.weight_kg) for row in rows],
        goal_kg=user.goal_weight_kg,
        start_kg=user.start_weight_kg,
        height_cm=user.height_cm,
        weekly_goal_kg=user.weekly_goal_kg,
    )
    return PredictionOut(**result.as_dict())
