import uuid
from datetime import date, datetime
from typing import Optional

from sqlalchemy import Boolean, Date, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class Food(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "foods"

    name: Mapped[str] = mapped_column(String(200), index=True, nullable=False)
    brand: Mapped[Optional[str]] = mapped_column(String(120))
    serving_label: Mapped[str] = mapped_column(String(80), default="100 g")
    serving_grams: Mapped[float] = mapped_column(Float, default=100.0)
    calories: Mapped[float] = mapped_column(Float, default=0.0)
    protein_g: Mapped[float] = mapped_column(Float, default=0.0)
    carbs_g: Mapped[float] = mapped_column(Float, default=0.0)
    fat_g: Mapped[float] = mapped_column(Float, default=0.0)
    fiber_g: Mapped[float] = mapped_column(Float, default=0.0)
    sugar_g: Mapped[float] = mapped_column(Float, default=0.0)
    is_public: Mapped[bool] = mapped_column(Boolean, default=True)
    created_by: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL")
    )


class FavoriteFood(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "favorite_foods"
    __table_args__ = (UniqueConstraint("user_id", "food_id", name="uq_favorite_food"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    food_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("foods.id", ondelete="CASCADE"))


class MealLog(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "meal_logs"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    food_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("foods.id", ondelete="SET NULL")
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    meal_type: Mapped[str] = mapped_column(String(16), default="lunch")
    quantity_g: Mapped[float] = mapped_column(Float, default=100.0)
    calories: Mapped[float] = mapped_column(Float, default=0.0)
    protein_g: Mapped[float] = mapped_column(Float, default=0.0)
    carbs_g: Mapped[float] = mapped_column(Float, default=0.0)
    fat_g: Mapped[float] = mapped_column(Float, default=0.0)
    source: Mapped[str] = mapped_column(String(16), default="manual")
    image_url: Mapped[Optional[str]] = mapped_column(String(512))
    recorded_on: Mapped[date] = mapped_column(Date, index=True, nullable=False)
    logged_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class MealPlan(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "meal_plans"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    start_date: Mapped[date] = mapped_column(Date, index=True, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)
    kind: Mapped[str] = mapped_column(String(8), default="week")
    calorie_target: Mapped[int] = mapped_column(Integer, default=2000)
    preferences: Mapped[Optional[str]] = mapped_column(Text)
    days: Mapped[dict] = mapped_column(JSONB, default=dict)
    grocery_list: Mapped[dict] = mapped_column(JSONB, default=dict)
