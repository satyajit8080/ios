from datetime import date as date_type
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, throttle
from app.db.session import get_db
from app.models import DailyCheckIn, User
from app.schemas.misc import (
    CheckInHistoryOut,
    CheckInOut,
    CheckInPrompt,
    CheckInQuestion,
    CheckInSubmit,
)
from app.services import checkin
from app.services.gamification import award_xp, evaluate_badges

router = APIRouter(prefix="/checkin", tags=["checkin"])


def _as_out(row: DailyCheckIn) -> CheckInOut:
    return CheckInOut(
        id=row.id,
        recorded_on=row.recorded_on,
        answers=row.answers or {},
        metrics=row.metrics or {},
        mood=row.mood,
        energy=row.energy,
        adherence=row.adherence,
        summary=row.summary,
        recommendations=list(row.recommendations or []),
        focus=row.focus,
        provider=row.provider,
        created_at=row.created_at,
    )


@router.get("/today", response_model=CheckInPrompt)
def todays_prompt(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Questions for today, the numbers behind them, and whether it's already done."""
    today = date_type.today()
    existing = db.scalar(
        select(DailyCheckIn).where(DailyCheckIn.user_id == user.id, DailyCheckIn.recorded_on == today)
    )
    return CheckInPrompt(
        recorded_on=today,
        completed=existing is not None,
        questions=[CheckInQuestion(**q) for q in checkin.questions_for(today)],
        metrics=checkin.gather_metrics(db, user, today),
        streak=checkin.streak(db, user, today),
    )


@router.post("", response_model=CheckInOut, dependencies=[Depends(throttle("checkin", 20, 3600))])
async def submit(
    payload: CheckInSubmit,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Submit answers and get the coach's analysis back.

    Re-submitting on the same day overwrites that day's check-in rather than creating
    a second one, so the streak stays honest.
    """
    day = payload.recorded_on or date_type.today()
    if day > date_type.today():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "You can't check in for a future date.")

    metrics = checkin.gather_metrics(db, user, day)
    analysis = await checkin.analyse(db, user, payload.answers, metrics)

    row = db.scalar(
        select(DailyCheckIn).where(DailyCheckIn.user_id == user.id, DailyCheckIn.recorded_on == day)
    )
    is_new = row is None
    if row is None:
        row = DailyCheckIn(user_id=user.id, recorded_on=day)

    row.answers = payload.answers
    row.metrics = metrics
    row.mood = _scale(payload.answers.get("mood"))
    row.energy = _scale(payload.answers.get("energy"))
    row.adherence = _scale(payload.answers.get("adherence"))
    row.summary = analysis["summary"]
    row.recommendations = analysis["recommendations"]
    row.focus = analysis.get("focus")
    row.provider = analysis.get("provider")
    db.add(row)

    if is_new:
        award_xp(db, user, "checkin_completed")
        evaluate_badges(db, user)

    db.commit()
    db.refresh(row)
    return _as_out(row)


@router.get("", response_model=CheckInHistoryOut)
def history(
    limit: int = Query(30, ge=1, le=120),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows: List[DailyCheckIn] = db.scalars(
        select(DailyCheckIn)
        .where(DailyCheckIn.user_id == user.id)
        .order_by(DailyCheckIn.recorded_on.desc())
        .limit(limit)
    ).all()
    return CheckInHistoryOut(streak=checkin.streak(db, user), entries=[_as_out(r) for r in rows])


@router.delete("/{checkin_id}", status_code=204)
def delete_checkin(checkin_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.scalar(
        select(DailyCheckIn).where(DailyCheckIn.id == checkin_id, DailyCheckIn.user_id == user.id)
    )
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That check-in no longer exists.")
    db.delete(row)
    db.commit()


def _scale(value) -> int | None:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return None
    return max(1, min(parsed, 5))
