import uuid
from datetime import datetime, time
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Time
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class Notification(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "notifications"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    body: Mapped[str] = mapped_column(String(400), default="")
    kind: Mapped[str] = mapped_column(String(32), default="general")
    payload: Mapped[dict] = mapped_column(JSONB, default=dict)
    scheduled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), index=True)
    sent_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    read_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class ReminderSetting(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "reminder_settings"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True, index=True
    )
    water_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    water_interval_minutes: Mapped[int] = mapped_column(Integer, default=120)
    day_start: Mapped[time] = mapped_column(Time, default=time(8, 0))
    day_end: Mapped[time] = mapped_column(Time, default=time(21, 0))
    weigh_in_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    weigh_in_time: Mapped[time] = mapped_column(Time, default=time(8, 0))
    meal_log_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    step_nudge_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    coach_checkin_enabled: Mapped[bool] = mapped_column(Boolean, default=True)


class AnalyticsEvent(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "analytics_events"

    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), index=True
    )
    name: Mapped[str] = mapped_column(String(64), index=True, nullable=False)
    props: Mapped[dict] = mapped_column(JSONB, default=dict)
