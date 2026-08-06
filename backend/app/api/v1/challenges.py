from datetime import date, timedelta
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.db.session import get_db
from app.models import (
    Challenge,
    ChallengeParticipant,
    Food,
    MealLog,
    StepEntry,
    User,
    WeightEntry,
)
from app.schemas.engagement import ChallengeOut, ChallengeStatus
from app.services.gamification import award_xp, evaluate_badges

router = APIRouter(prefix="/challenges", tags=["challenges"])

SEED = [
    dict(
        code="drop_4kg_60d",
        title="Drop 4 kg in 60 days",
        subtitle="A steady, sustainable pace",
        description="Log your weight regularly and aim for about 0.5 kg per week. Progress is measured from your "
        "weight on the day you join.",
        kind="weight",
        duration_days=60,
        target_value=4.0,
        xp_reward=500,
    ),
    dict(
        code="steps_10k_30d",
        title="10,000 steps for 30 days",
        subtitle="Consistency beats intensity",
        description="Hit 10,000 steps each day. Every qualifying day counts once toward your total.",
        kind="steps",
        duration_days=30,
        target_value=30,
        xp_reward=400,
    ),
    dict(
        code="no_sugar_21d",
        title="21 days without added sugar",
        subtitle="Reset your sweet tooth",
        description="Mark the no-added-sugar habit complete each day. Miss a day and you keep the days you banked.",
        kind="no_sugar",
        duration_days=21,
        target_value=21,
        xp_reward=350,
    ),
]


def seed_challenges(db: Session) -> None:
    existing = {c.code for c in db.scalars(select(Challenge)).all()}
    for item in SEED:
        if item["code"] not in existing:
            db.add(Challenge(**item))
    db.commit()


SUGAR_LIMIT_G = 25.0  # WHO free-sugar guidance for an adult, used as the no-sugar bar
STEPS_CHALLENGE_TARGET = 10000


def _qualifying_days(db: Session, user: User, challenge: Challenge, part: ChallengeParticipant) -> List[date]:
    """Days that count toward a day-counting challenge, oldest first.

    Only days with enough logged data to verify are counted. A day with nothing
    logged is unknown, not a pass.
    """
    start, end = part.start_date, min(part.end_date, date.today())

    if challenge.kind == "steps":
        rows = db.execute(
            select(StepEntry.recorded_on).where(
                StepEntry.user_id == user.id,
                StepEntry.recorded_on.between(start, end),
                StepEntry.steps >= STEPS_CHALLENGE_TARGET,
            )
        ).all()
        return sorted({row.recorded_on for row in rows})

    # no-sugar: a day passes when meals were logged and tracked sugar stayed under the limit.
    logged_days = {
        row.recorded_on
        for row in db.execute(
            select(MealLog.recorded_on).where(
                MealLog.user_id == user.id, MealLog.recorded_on.between(start, end)
            )
        ).all()
    }
    if not logged_days:
        return []

    sugar_rows = db.execute(
        select(MealLog.recorded_on, func.sum(Food.sugar_g * MealLog.quantity_g / func.nullif(Food.serving_grams, 0)))
        .join(Food, Food.id == MealLog.food_id)
        .where(MealLog.user_id == user.id, MealLog.recorded_on.between(start, end))
        .group_by(MealLog.recorded_on)
    ).all()
    over_limit = {row[0] for row in sugar_rows if (row[1] or 0) > SUGAR_LIMIT_G}

    return sorted(logged_days - over_limit)


def _streaks(days: List[date]) -> tuple[int, int, date | None]:
    """(current, longest, last_day) from an ordered list of qualifying days."""
    if not days:
        return 0, 0, None

    longest = run = 1
    for previous, current in zip(days, days[1:]):
        run = run + 1 if (current - previous).days == 1 else 1
        longest = max(longest, run)

    today = date.today()
    current_streak = run if days[-1] in (today, today - timedelta(days=1)) else 0
    return current_streak, longest, days[-1]


def _progress(db: Session, user: User, challenge: Challenge, part: ChallengeParticipant) -> float:
    """Progress in the challenge's own units, and refresh its streak counters."""
    if challenge.kind == "weight":
        end = min(part.end_date, date.today())
        latest = db.scalar(
            select(WeightEntry)
            .where(WeightEntry.user_id == user.id, WeightEntry.recorded_on <= end)
            .order_by(WeightEntry.recorded_on.desc())
        )
        if not latest or part.baseline is None:
            return 0.0
        return max(round(part.baseline - latest.weight_kg, 2), 0.0)

    days = _qualifying_days(db, user, challenge, part)
    current, longest, last_day = _streaks(days)
    part.current_streak = current
    part.longest_streak = max(longest, part.longest_streak or 0)
    part.last_qualified_on = last_day
    return float(len(days))


@router.get("", response_model=List[ChallengeStatus])
def list_challenges(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    seed_challenges(db)
    out: List[ChallengeStatus] = []
    for challenge in db.scalars(select(Challenge).where(Challenge.is_active.is_(True))).all():
        part = db.scalar(
            select(ChallengeParticipant).where(
                ChallengeParticipant.challenge_id == challenge.id, ChallengeParticipant.user_id == user.id
            )
        )
        count = db.scalar(
            select(func.count(ChallengeParticipant.id)).where(
                ChallengeParticipant.challenge_id == challenge.id
            )
        ) or 0
        progress = _progress(db, user, challenge, part) if part else 0.0
        if part:
            part.progress = progress
            if progress >= challenge.target_value and not part.completed:
                part.completed = True
                award_xp(db, user, "challenge_completed")
                user.xp = (user.xp or 0) + challenge.xp_reward
                db.add(user)
            db.add(part)
            db.commit()
            evaluate_badges(db, user)
        out.append(
            ChallengeStatus(
                challenge=ChallengeOut.model_validate(challenge),
                joined=part is not None,
                progress=progress,
                progress_pct=round(min(progress / challenge.target_value * 100, 100), 1)
                if challenge.target_value
                else 0.0,
                days_left=max((part.end_date - date.today()).days, 0) if part else challenge.duration_days,
                completed=bool(part and part.completed),
                participants=count,
            )
        )
    return out


@router.post("/{challenge_id}/join", response_model=ChallengeStatus, status_code=201)
def join_challenge(challenge_id: UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    challenge = db.get(Challenge, challenge_id)
    if not challenge or not challenge.is_active:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That challenge isn't available.")
    if challenge.premium_only and not user.is_premium:
        raise HTTPException(status.HTTP_402_PAYMENT_REQUIRED, "Premium unlocks this challenge.")

    existing = db.scalar(
        select(ChallengeParticipant).where(
            ChallengeParticipant.challenge_id == challenge.id, ChallengeParticipant.user_id == user.id
        )
    )
    if existing:
        raise HTTPException(status.HTTP_409_CONFLICT, "You've already joined this challenge.")

    baseline = None
    if challenge.kind == "weight":
        latest = db.scalar(
            select(WeightEntry).where(WeightEntry.user_id == user.id).order_by(WeightEntry.recorded_on.desc())
        )
        baseline = latest.weight_kg if latest else user.start_weight_kg

    part = ChallengeParticipant(
        challenge_id=challenge.id,
        user_id=user.id,
        start_date=date.today(),
        end_date=date.today() + timedelta(days=challenge.duration_days),
        baseline=baseline,
    )
    db.add(part)
    db.commit()
    count = db.scalar(
        select(func.count(ChallengeParticipant.id)).where(ChallengeParticipant.challenge_id == challenge.id)
    ) or 1
    return ChallengeStatus(
        challenge=ChallengeOut.model_validate(challenge),
        joined=True,
        progress=0.0,
        progress_pct=0.0,
        days_left=challenge.duration_days,
        completed=False,
        participants=count,
    )


@router.delete("/{challenge_id}/leave", status_code=204)
def leave_challenge(challenge_id: UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    db.query(ChallengeParticipant).filter(
        ChallengeParticipant.challenge_id == challenge_id, ChallengeParticipant.user_id == user.id
    ).delete()
    db.commit()
