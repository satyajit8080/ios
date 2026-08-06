import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, Float, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class User(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(320), unique=True, index=True, nullable=False)
    hashed_password: Mapped[Optional[str]] = mapped_column(String(255))
    apple_sub: Mapped[Optional[str]] = mapped_column(String(255), unique=True, index=True)

    full_name: Mapped[Optional[str]] = mapped_column(String(120))
    gender: Mapped[str] = mapped_column(String(16), default="unspecified")
    birth_date: Mapped[Optional[date]] = mapped_column(Date)
    height_cm: Mapped[Optional[float]] = mapped_column(Float)
    activity_level: Mapped[str] = mapped_column(String(24), default="moderate")

    start_weight_kg: Mapped[Optional[float]] = mapped_column(Float)
    goal_weight_kg: Mapped[Optional[float]] = mapped_column(Float)
    weekly_goal_kg: Mapped[float] = mapped_column(Float, default=0.5)

    daily_calorie_target: Mapped[int] = mapped_column(Integer, default=2000)
    daily_protein_target_g: Mapped[int] = mapped_column(Integer, default=120)
    daily_water_ml_target: Mapped[int] = mapped_column(Integer, default=2500)
    daily_step_target: Mapped[int] = mapped_column(Integer, default=8000)

    timezone: Mapped[str] = mapped_column(String(64), default="UTC")
    locale: Mapped[str] = mapped_column(String(8), default="en")
    xp: Mapped[int] = mapped_column(Integer, default=0)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    is_premium: Mapped[bool] = mapped_column(Boolean, default=False)
    premium_expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    onboarded: Mapped[bool] = mapped_column(Boolean, default=False)
    last_active_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    devices: Mapped[list["Device"]] = relationship(back_populates="user", cascade="all, delete-orphan")


class Device(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "devices"
    __table_args__ = (UniqueConstraint("token", name="uq_device_token"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token: Mapped[str] = mapped_column(String(512), nullable=False)
    platform: Mapped[str] = mapped_column(String(16), default="ios")
    app_version: Mapped[Optional[str]] = mapped_column(String(32))
    user: Mapped[User] = relationship(back_populates="devices")


class RefreshToken(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "refresh_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), index=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)


class PasswordResetToken(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "password_reset_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), index=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    used: Mapped[bool] = mapped_column(Boolean, default=False)
