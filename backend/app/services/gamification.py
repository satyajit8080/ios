"""XP awards and badge unlocking."""
from datetime import date, datetime, timezone
from typing import List

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import (
    Badge,
    ChallengeParticipant,
    DailyCheckIn,
    HabitLog,
    StepEntry,
    User,
    UserBadge,
    WeightEntry,
)

XP_RULES = {
    "weight_logged": 10,
    "meal_logged": 5,
    "water_logged": 2,
    "habit_completed": 8,
    "steps_goal_hit": 15,
    "challenge_completed": 250,
    "checkin_completed": 12,
}

DEFAULT_BADGES = [
    ("first_weigh_in", "First Step", "Logged your first weight", "figure.stand", 50),
    ("streak_7", "One Week Strong", "7-day logging streak", "flame", 100),
    ("streak_30", "Month of Momentum", "30-day logging streak", "flame.fill", 300),
    ("steps_10k", "Ten Thousand", "Hit 10,000 steps in a day", "shoeprints.fill", 80),
    ("steps_100k_week", "Century Week", "100,000 steps in one week", "figure.walk.motion", 250),
    ("hydrated_7", "Well Watered", "Hit your water goal 7 days running", "drop.fill", 120),
    ("habit_master", "Habit Master", "A 21-day habit streak", "checkmark.seal.fill", 200),
    ("goal_halfway", "Halfway There", "Reached 50% of your weight goal", "chart.line.downtrend.xyaxis", 300),
    ("goal_reached", "Goal Reached", "Hit your target weight", "trophy.fill", 1000),
    ("checkin_7", "Daily Habit", "Seven check-ins in a row", "calendar.badge.checkmark", 150),
    ("challenge_finisher", "Finisher", "Completed a challenge", "medal.fill", 250),
]


def seed_badges(db: Session) -> None:
    existing = {b.code for b in db.scalars(select(Badge)).all()}
    for code, name, desc, icon, xp in DEFAULT_BADGES:
        if code not in existing:
            db.add(Badge(code=code, name=name, description=desc, icon=icon, xp_reward=xp))
    db.commit()


def award_xp(db: Session, user: User, rule: str, multiplier: int = 1) -> int:
    amount = XP_RULES.get(rule, 0) * multiplier
    if amount:
        user.xp = (user.xp or 0) + amount
        db.add(user)
    return amount


def grant_badge(db: Session, user: User, code: str) -> bool:
    badge = db.scalar(select(Badge).where(Badge.code == code))
    if not badge:
        return False
    exists = db.scalar(
        select(UserBadge).where(UserBadge.user_id == user.id, UserBadge.badge_id == badge.id)
    )
    if exists:
        return False
    db.add(UserBadge(user_id=user.id, badge_id=badge.id, earned_at=datetime.now(timezone.utc)))
    user.xp = (user.xp or 0) + badge.xp_reward
    db.add(user)
    return True


def evaluate_badges(db: Session, user: User) -> List[str]:
    """Recompute badge eligibility. Returns newly granted codes."""
    granted: List[str] = []

    weigh_ins = db.scalar(select(func.count(WeightEntry.id)).where(WeightEntry.user_id == user.id)) or 0
    if weigh_ins >= 1 and grant_badge(db, user, "first_weigh_in"):
        granted.append("first_weigh_in")

    checkins = (
        db.scalar(select(func.count(DailyCheckIn.id)).where(DailyCheckIn.user_id == user.id)) or 0
    )
    if checkins >= 7 and grant_badge(db, user, "checkin_7"):
        granted.append("checkin_7")

    best_steps = db.scalar(select(func.max(StepEntry.steps)).where(StepEntry.user_id == user.id)) or 0
    if best_steps >= 10000 and grant_badge(db, user, "steps_10k"):
        granted.append("steps_10k")

    week_steps = (
        db.scalar(
            select(func.sum(StepEntry.steps)).where(
                StepEntry.user_id == user.id,
                StepEntry.recorded_on >= date.today().fromordinal(date.today().toordinal() - 6),
            )
        )
        or 0
    )
    if week_steps >= 100000 and grant_badge(db, user, "steps_100k_week"):
        granted.append("steps_100k_week")

    habit_days = (
        db.scalar(
            select(func.count(func.distinct(HabitLog.recorded_on))).where(HabitLog.user_id == user.id)
        )
        or 0
    )
    if habit_days >= 21 and grant_badge(db, user, "habit_master"):
        granted.append("habit_master")

    latest = db.scalar(
        select(WeightEntry).where(WeightEntry.user_id == user.id).order_by(WeightEntry.recorded_on.desc())
    )
    if latest and user.start_weight_kg and user.goal_weight_kg and user.start_weight_kg != user.goal_weight_kg:
        pct = (user.start_weight_kg - latest.weight_kg) / (user.start_weight_kg - user.goal_weight_kg)
        if pct >= 0.5 and grant_badge(db, user, "goal_halfway"):
            granted.append("goal_halfway")
        if pct >= 1.0 and grant_badge(db, user, "goal_reached"):
            granted.append("goal_reached")

    finished = db.scalar(
        select(func.count(ChallengeParticipant.id)).where(
            ChallengeParticipant.user_id == user.id, ChallengeParticipant.completed.is_(True)
        )
    ) or 0
    if finished >= 1 and grant_badge(db, user, "challenge_finisher"):
        granted.append("challenge_finisher")

    db.commit()
    return granted
