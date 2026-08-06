from datetime import date, timedelta
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.db.session import get_db
from app.models import Badge, Habit, HabitLog, User, UserBadge
from app.schemas.engagement import (
    BadgeOut,
    EarnedBadgeOut,
    GamificationOut,
    HabitCreate,
    HabitLogCreate,
    HabitOut,
    HabitWithStats,
)
from app.services.gamification import award_xp, evaluate_badges
from app.services.metrics import level_for_xp
from app.services.streaks import streaks

router = APIRouter(tags=["habits"])


@router.post("/habits", response_model=HabitOut, status_code=201)
def create_habit(payload: HabitCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    habit = Habit(user_id=user.id, **payload.model_dump())
    db.add(habit)
    db.commit()
    db.refresh(habit)
    return HabitOut.model_validate(habit)


@router.get("/habits", response_model=List[HabitWithStats])
def list_habits(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    today = date.today()
    habits = db.scalars(
        select(Habit).where(Habit.user_id == user.id, Habit.archived.is_(False)).order_by(Habit.created_at.asc())
    ).all()
    out: List[HabitWithStats] = []
    for habit in habits:
        logs = db.scalars(
            select(HabitLog)
            .where(HabitLog.habit_id == habit.id, HabitLog.recorded_on >= today - timedelta(days=90))
            .order_by(HabitLog.recorded_on.asc())
        ).all()
        completed_days = [log.recorded_on for log in logs if log.count >= habit.target_per_day]
        current, longest = streaks(completed_days, today)
        out.append(
            HabitWithStats(
                habit=HabitOut.model_validate(habit),
                done_today=next((log.count for log in logs if log.recorded_on == today), 0),
                current_streak=current,
                longest_streak=longest,
                last_30_days=[d for d in completed_days if d >= today - timedelta(days=29)],
            )
        )
    return out


@router.post("/habits/{habit_id}/log", response_model=HabitWithStats)
def log_habit(
    habit_id: UUID,
    payload: HabitLogCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    habit = db.scalar(select(Habit).where(Habit.id == habit_id, Habit.user_id == user.id))
    if not habit:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That habit no longer exists.")

    day = payload.recorded_on or date.today()
    log = db.scalar(select(HabitLog).where(HabitLog.habit_id == habit.id, HabitLog.recorded_on == day))
    was_complete = bool(log and log.count >= habit.target_per_day)
    if log is None:
        log = HabitLog(habit_id=habit.id, user_id=user.id, recorded_on=day, count=0)
    log.count = payload.count
    db.add(log)
    if log.count >= habit.target_per_day and not was_complete:
        award_xp(db, user, "habit_completed")
    db.commit()
    evaluate_badges(db, user)

    logs = db.scalars(
        select(HabitLog).where(HabitLog.habit_id == habit.id).order_by(HabitLog.recorded_on.asc())
    ).all()
    completed_days = [log.recorded_on for log in logs if log.count >= habit.target_per_day]
    current, longest = streaks(completed_days)
    return HabitWithStats(
        habit=HabitOut.model_validate(habit),
        done_today=next((log.count for log in logs if log.recorded_on == date.today()), 0),
        current_streak=current,
        longest_streak=longest,
        last_30_days=[d for d in completed_days if d >= date.today() - timedelta(days=29)],
    )


@router.delete("/habits/{habit_id}", status_code=204)
def archive_habit(habit_id: UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    habit = db.scalar(select(Habit).where(Habit.id == habit_id, Habit.user_id == user.id))
    if not habit:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That habit no longer exists.")
    habit.archived = True
    db.add(habit)
    db.commit()


@router.get("/gamification", response_model=GamificationOut)
def gamification(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    earned = db.execute(
        select(UserBadge, Badge).join(Badge, Badge.id == UserBadge.badge_id).where(UserBadge.user_id == user.id)
    ).all()
    earned_ids = {row[1].id for row in earned}
    locked = [b for b in db.scalars(select(Badge)).all() if b.id not in earned_ids]
    level, into, need = level_for_xp(user.xp or 0)
    return GamificationOut(
        xp=user.xp or 0,
        level=level,
        xp_into_level=into,
        xp_for_next_level=need,
        badges=[
            EarnedBadgeOut(badge=BadgeOut.model_validate(row[1]), earned_at=row[0].earned_at) for row in earned
        ],
        locked_badges=[BadgeOut.model_validate(b) for b in locked],
    )
