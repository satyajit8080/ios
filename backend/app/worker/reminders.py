"""Reminder engine: runs on a schedule, decides who needs a nudge, sends push + inbox row."""
import logging
from datetime import datetime, time, timedelta, timezone
from typing import List
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.session import SessionLocal
from app.models import (
    DailyCheckIn,
    Device,
    HabitLog,
    MealLog,
    Notification,
    ReminderSetting,
    StepEntry,
    User,
    WaterEntry,
    WeightEntry,
)
from app.services import checkin as checkin_service
from app.services.push import send_push

logger = logging.getLogger(__name__)


def _local_now(user: User) -> datetime:
    try:
        return datetime.now(ZoneInfo(user.timezone or "UTC"))
    except (ZoneInfoNotFoundError, ValueError):
        return datetime.now(timezone.utc)


def _tokens(db: Session, user: User) -> List[str]:
    return [d.token for d in db.scalars(select(Device).where(Device.user_id == user.id)).all()]


def _deliver(db: Session, user: User, kind: str, title: str, body: str, cooldown_hours: int = 6) -> bool:
    since = datetime.now(timezone.utc) - timedelta(hours=cooldown_hours)
    recent = db.scalar(
        select(func.count(Notification.id)).where(
            Notification.user_id == user.id, Notification.kind == kind, Notification.created_at >= since
        )
    )
    if recent:
        return False

    notification = Notification(
        user_id=user.id, title=title, body=body, kind=kind, payload={"kind": kind},
        scheduled_at=datetime.now(timezone.utc),
    )
    db.add(notification)
    tokens = _tokens(db, user)
    if tokens:
        send_push(tokens, title, body, {"kind": kind})
        notification.sent_at = datetime.now(timezone.utc)
    db.commit()
    return True


def run_cycle() -> int:
    """One pass over active users. Returns notifications delivered."""
    delivered = 0
    db: Session = SessionLocal()
    try:
        users = db.scalars(select(User).where(User.is_active.is_(True))).all()
        for user in users:
            settings_row = db.scalar(select(ReminderSetting).where(ReminderSetting.user_id == user.id))
            if settings_row is None:
                continue
            now = _local_now(user)
            local_today = now.date()
            if not (settings_row.day_start <= now.time() <= settings_row.day_end):
                continue

            if settings_row.weigh_in_enabled and _within(now.time(), settings_row.weigh_in_time, 30):
                logged = db.scalar(
                    select(WeightEntry).where(
                        WeightEntry.user_id == user.id, WeightEntry.recorded_on == local_today
                    )
                )
                if not logged and _deliver(
                    db, user, "weigh_in", "Morning weigh-in",
                    "Step on the scale and log today's number — it takes ten seconds.", 20,
                ):
                    delivered += 1

            if settings_row.water_enabled:
                total = db.scalar(
                    select(func.sum(WaterEntry.amount_ml)).where(
                        WaterEntry.user_id == user.id, WaterEntry.recorded_on == local_today
                    )
                ) or 0
                elapsed = (now.hour * 60 + now.minute) - (settings_row.day_start.hour * 60)
                window = max((settings_row.day_end.hour - settings_row.day_start.hour) * 60, 1)
                expected = user.daily_water_ml_target * max(min(elapsed / window, 1), 0)
                if total < expected * 0.7 and _deliver(
                    db, user, "water", "Time for water",
                    f"You're at {int(total)} ml of {user.daily_water_ml_target} ml today.",
                    max(settings_row.water_interval_minutes // 60, 1),
                ):
                    delivered += 1

            if settings_row.meal_log_enabled and now.hour >= 14:
                meals = db.scalar(
                    select(func.count(MealLog.id)).where(
                        MealLog.user_id == user.id, MealLog.recorded_on == local_today
                    )
                ) or 0
                if meals == 0 and _deliver(
                    db, user, "meal_log", "Nothing logged yet today",
                    "Snap a photo of your next meal and the coach will do the maths.", 12,
                ):
                    delivered += 1

            if settings_row.step_nudge_enabled and now.hour >= 18:
                entry = db.scalar(
                    select(StepEntry).where(
                        StepEntry.user_id == user.id, StepEntry.recorded_on == local_today
                    )
                )
                steps = entry.steps if entry else 0
                short = user.daily_step_target - steps
                if 0 < short <= 3000 and _deliver(
                    db, user, "steps", "Close to your step goal",
                    f"{short:,} steps to go — about a {max(short // 120, 5)} minute walk.", 12,
                ):
                    delivered += 1

            # Daily AI check-in: mid-morning, only if today's check-in is still outstanding.
            if settings_row.coach_checkin_enabled and 9 <= now.hour <= 11:
                done_today = db.scalar(
                    select(func.count(DailyCheckIn.id)).where(
                        DailyCheckIn.user_id == user.id, DailyCheckIn.recorded_on == local_today
                    )
                ) or 0
                if done_today == 0:
                    run = checkin_service.streak(db, user, local_today)
                    body = (
                        f"Keep your {run}-day streak going — two minutes and the coach reads your numbers back to you."
                        if run >= 2
                        else "Two minutes of questions and the coach reads your week back to you."
                    )
                    if _deliver(db, user, "checkin", "Your daily check-in", body, 20):
                        delivered += 1

            if settings_row.coach_checkin_enabled and now.weekday() == 6 and 17 <= now.hour <= 19:
                if _deliver(
                    db, user, "weekly_review", "Your week in review",
                    "Open the coach for a look at how the week went and what to change.", 120,
                ):
                    delivered += 1

            if settings_row.coach_checkin_enabled and now.hour >= 20:
                habit_done = db.scalar(
                    select(func.count(HabitLog.id)).where(
                        HabitLog.user_id == user.id, HabitLog.recorded_on == local_today, HabitLog.count > 0
                    )
                ) or 0
                if habit_done == 0 and _deliver(
                    db, user, "habits", "Habits still open",
                    "Tick off what you managed today — partial credit counts.", 20,
                ):
                    delivered += 1
    finally:
        db.close()
    logger.info("reminder cycle delivered %s notifications", delivered)
    return delivered


def _within(now: time, target: time, minutes: int) -> bool:
    now_m = now.hour * 60 + now.minute
    target_m = target.hour * 60 + target.minute
    return 0 <= now_m - target_m <= minutes


def purge_expired(retention_days: int = 90) -> int:
    db: Session = SessionLocal()
    try:
        cutoff = datetime.now(timezone.utc) - timedelta(days=retention_days)
        removed = db.query(Notification).filter(Notification.created_at < cutoff).delete()
        db.commit()
        return removed
    finally:
        db.close()
