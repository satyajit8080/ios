import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import Date, DateTime, Float, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class WeightEntry(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "weight_entries"
    __table_args__ = (UniqueConstraint("user_id", "recorded_on", name="uq_weight_user_day"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    weight_kg: Mapped[float] = mapped_column(Float, nullable=False)
    body_fat_pct: Mapped[Optional[float]] = mapped_column(Float)
    note: Mapped[Optional[str]] = mapped_column(String(280))
    recorded_on: Mapped[date] = mapped_column(Date, index=True, nullable=False)


class StepEntry(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "step_entries"
    __table_args__ = (UniqueConstraint("user_id", "recorded_on", name="uq_steps_user_day"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    steps: Mapped[int] = mapped_column(Integer, default=0)
    distance_m: Mapped[float] = mapped_column(Float, default=0.0)
    active_kcal: Mapped[float] = mapped_column(Float, default=0.0)
    source: Mapped[str] = mapped_column(String(24), default="healthkit")
    recorded_on: Mapped[date] = mapped_column(Date, index=True, nullable=False)


class WaterEntry(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "water_entries"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    amount_ml: Mapped[int] = mapped_column(Integer, nullable=False)
    recorded_on: Mapped[date] = mapped_column(Date, index=True, nullable=False)
    logged_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
