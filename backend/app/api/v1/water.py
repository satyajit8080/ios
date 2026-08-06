from datetime import date, datetime, timedelta, timezone
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.db.session import get_db
from app.models import User, WaterEntry
from app.schemas.tracking import WaterCreate, WaterOut, WaterStats
from app.services.gamification import award_xp, grant_badge
from app.services.streaks import streaks

router = APIRouter(prefix="/water", tags=["water"])


@router.post("", response_model=WaterOut, status_code=201)
def log_water(payload: WaterCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    day = payload.recorded_on or date.today()
    entry = WaterEntry(
        user_id=user.id,
        amount_ml=payload.amount_ml,
        recorded_on=day,
        logged_at=datetime.now(timezone.utc),
    )
    db.add(entry)
    award_xp(db, user, "water_logged")
    db.commit()
    db.refresh(entry)
    return WaterOut.model_validate(entry)


@router.get("/today", response_model=List[WaterOut])
def water_today(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(WaterEntry)
        .where(WaterEntry.user_id == user.id, WaterEntry.recorded_on == date.today())
        .order_by(WaterEntry.logged_at.asc())
    ).all()
    return [WaterOut.model_validate(r) for r in rows]


@router.get("/stats", response_model=WaterStats)
def water_stats(
    days: int = Query(30, ge=7, le=180),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    today = date.today()
    since = today - timedelta(days=days)
    rows = db.execute(
        select(WaterEntry.recorded_on, func.sum(WaterEntry.amount_ml))
        .where(WaterEntry.user_id == user.id, WaterEntry.recorded_on >= since)
        .group_by(WaterEntry.recorded_on)
        .order_by(WaterEntry.recorded_on.asc())
    ).all()
    totals = {row[0]: int(row[1] or 0) for row in rows}
    goal = user.daily_water_ml_target or 2500
    today_ml = totals.get(today, 0)
    week = [totals.get(today - timedelta(days=i), 0) for i in range(7)]
    hit_days = [d for d, ml in totals.items() if ml >= goal]
    current, _ = streaks(hit_days, today)

    if current >= 7 and grant_badge(db, user, "hydrated_7"):
        db.commit()

    return WaterStats(
        today_ml=today_ml,
        goal_ml=goal,
        progress_pct=round(min(today_ml / goal * 100, 100), 1) if goal else 0.0,
        week_average_ml=int(sum(week) / 7),
        current_streak=current,
        series=[{"date": d.isoformat(), "ml": ml} for d, ml in sorted(totals.items())],
    )


@router.delete("/{entry_id}", status_code=204)
def delete_water(entry_id: UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    entry = db.scalar(select(WaterEntry).where(WaterEntry.id == entry_id, WaterEntry.user_id == user.id))
    if not entry:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That entry no longer exists.")
    db.delete(entry)
    db.commit()
