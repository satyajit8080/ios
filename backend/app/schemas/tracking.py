from datetime import date, datetime
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class WeightCreate(BaseModel):
    weight_kg: float = Field(gt=20, lt=400)
    body_fat_pct: Optional[float] = Field(default=None, ge=2, le=70)
    note: Optional[str] = Field(default=None, max_length=280)
    recorded_on: Optional[date] = None


class WeightOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    weight_kg: float
    body_fat_pct: Optional[float]
    note: Optional[str]
    recorded_on: date


class WeightStats(BaseModel):
    current_kg: Optional[float]
    start_kg: Optional[float]
    goal_kg: Optional[float]
    change_kg: float
    change_7d_kg: float
    change_30d_kg: float
    bmi: Optional[float]
    bmi_category: Optional[str]
    goal_progress_pct: float
    trend_kg_per_week: float
    series: List[WeightOut]


class StepSyncItem(BaseModel):
    recorded_on: date
    steps: int = Field(ge=0, le=200000)
    distance_m: float = Field(default=0, ge=0)
    active_kcal: float = Field(default=0, ge=0)


class StepSyncRequest(BaseModel):
    items: List[StepSyncItem] = Field(max_length=180)
    source: str = "healthkit"


class StepOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    recorded_on: date
    steps: int
    distance_m: float
    active_kcal: float


class StepStats(BaseModel):
    today: int
    goal: int
    week_total: int
    week_average: int
    best_day: int
    current_streak: int
    longest_streak: int
    series: List[StepOut]


class WaterCreate(BaseModel):
    amount_ml: int = Field(gt=0, le=3000)
    recorded_on: Optional[date] = None


class WaterOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    amount_ml: int
    recorded_on: date
    logged_at: datetime


class WaterStats(BaseModel):
    today_ml: int
    goal_ml: int
    progress_pct: float
    week_average_ml: int
    current_streak: int
    series: List[dict]
