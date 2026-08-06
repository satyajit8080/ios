from datetime import date, timedelta
from typing import List

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.db.session import get_db
from app.models import StepEntry, User
from app.schemas.tracking import StepOut, StepStats, StepSyncRequest
from app.services.gamification import award_xp, evaluate_badges
from app.services.streaks import streaks

router = APIRouter(prefix="/steps", tags=["steps"])


@router.post("/sync", response_model=StepStats)
def sync_steps(payload: StepSyncRequest, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    goal_hits = 0
    for item in payload.items:
        if item.recorded_on > date.today():
            continue
        entry = db.scalar(
            select(StepEntry).where(StepEntry.user_id == user.id, StepEntry.recorded_on == item.recorded_on)
        )
        previously_hit = bool(entry and entry.steps >= user.daily_step_target)
        if entry is None:
            entry = StepEntry(user_id=user.id, recorded_on=item.recorded_on)
        entry.steps = item.steps
        entry.distance_m = item.distance_m
        entry.active_kcal = item.active_kcal
        entry.source = payload.source
        db.add(entry)
        if item.steps >= user.daily_step_target and not previously_hit:
            goal_hits += 1

    if goal_hits:
        award_xp(db, user, "steps_goal_hit", goal_hits)
    db.commit()
    evaluate_badges(db, user)
    return _stats(db, user)


@router.get("/stats", response_model=StepStats)
def step_stats(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return _stats(db, user)


@router.get("", response_model=List[StepOut])
def list_steps(
    days: int = Query(30, ge=1, le=365),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    since = date.today() - timedelta(days=days)
    rows = db.scalars(
        select(StepEntry)
        .where(StepEntry.user_id == user.id, StepEntry.recorded_on >= since)
        .order_by(StepEntry.recorded_on.asc())
    ).all()
    return [StepOut.model_validate(r) for r in rows]


def _stats(db: Session, user: User) -> StepStats:
    today = date.today()
    rows = db.scalars(
        select(StepEntry)
        .where(StepEntry.user_id == user.id, StepEntry.recorded_on >= today - timedelta(days=59))
        .order_by(StepEntry.recorded_on.asc())
    ).all()
    by_day = {r.recorded_on: r for r in rows}
    week = [by_day[today - timedelta(days=i)].steps for i in range(7) if today - timedelta(days=i) in by_day]
    hit_days = [r.recorded_on for r in rows if r.steps >= user.daily_step_target]
    current, longest = streaks(hit_days, today)

    return StepStats(
        today=by_day[today].steps if today in by_day else 0,
        goal=user.daily_step_target,
        week_total=sum(week),
        week_average=int(sum(week) / len(week)) if week else 0,
        best_day=max((r.steps for r in rows), default=0),
        current_streak=current,
        longest_streak=longest,
        series=[StepOut.model_validate(r) for r in rows[-30:]],
    )
