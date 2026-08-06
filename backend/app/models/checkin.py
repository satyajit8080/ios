import uuid
from datetime import date as date_type
from typing import Optional

from sqlalchemy import Date, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class DailyCheckIn(Base, UUIDMixin, TimestampMixin):
    """One coach check-in per user per day.

    `answers` holds the user's replies keyed by question id; `metrics` snapshots the
    numbers the analysis was based on, so a check-in stays interpretable later even
    after the underlying logs change.
    """

    __tablename__ = "daily_checkins"
    __table_args__ = (UniqueConstraint("user_id", "recorded_on", name="uq_checkin_user_day"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    recorded_on: Mapped[date_type] = mapped_column(Date, index=True, default=date_type.today)

    answers: Mapped[dict] = mapped_column(JSONB, default=dict)
    metrics: Mapped[dict] = mapped_column(JSONB, default=dict)

    mood: Mapped[Optional[int]] = mapped_column(Integer)
    energy: Mapped[Optional[int]] = mapped_column(Integer)
    adherence: Mapped[Optional[int]] = mapped_column(Integer)

    summary: Mapped[Optional[str]] = mapped_column(Text)
    recommendations: Mapped[list] = mapped_column(JSONB, default=list)
    focus: Mapped[Optional[str]] = mapped_column(String(160))
    provider: Mapped[Optional[str]] = mapped_column(String(24))
