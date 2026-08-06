from datetime import date, datetime
from typing import Any, Dict, List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)


class ChatMessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    role: str
    content: str
    created_at: datetime


class ChatResponse(BaseModel):
    reply: ChatMessageOut
    provider: str


class MemoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    key: str
    value: str


class DashboardOut(BaseModel):
    date: date
    weight_kg: Optional[float]
    weight_change_7d_kg: float
    bmi: Optional[float]
    bmi_category: Optional[str]
    goal_weight_kg: Optional[float]
    goal_progress_pct: float
    calories_consumed: float
    calorie_target: int
    calories_remaining: float
    protein_g: float
    carbs_g: float
    fat_g: float
    water_ml: int
    water_target_ml: int
    steps: int
    step_target: int
    step_streak: int
    habits_done: int
    habits_total: int
    xp: int
    level: int
    weight_series: List[dict]
    calorie_series: List[dict]
    step_series: List[dict]


class DeviceRegister(BaseModel):
    token: str = Field(min_length=8, max_length=512)
    platform: str = "ios"
    app_version: Optional[str] = None


class NotificationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    title: str
    body: str
    kind: str
    payload: dict
    sent_at: Optional[datetime]
    read_at: Optional[datetime]
    created_at: datetime


class ReminderSettingsIn(BaseModel):
    water_enabled: Optional[bool] = None
    water_interval_minutes: Optional[int] = Field(default=None, ge=30, le=480)
    day_start: Optional[str] = None
    day_end: Optional[str] = None
    weigh_in_enabled: Optional[bool] = None
    weigh_in_time: Optional[str] = None
    meal_log_enabled: Optional[bool] = None
    step_nudge_enabled: Optional[bool] = None
    coach_checkin_enabled: Optional[bool] = None


class ReminderSettingsOut(BaseModel):
    water_enabled: bool
    water_interval_minutes: int
    day_start: str
    day_end: str
    weigh_in_enabled: bool
    weigh_in_time: str
    meal_log_enabled: bool
    step_nudge_enabled: bool
    coach_checkin_enabled: bool


class VerifyPurchaseRequest(BaseModel):
    signed_transaction: Optional[str] = None
    product_id: str
    original_transaction_id: str
    transaction_id: str
    purchase_date_ms: int
    expires_date_ms: Optional[int] = None
    environment: str = "Production"


class SubscriptionStatus(BaseModel):
    is_premium: bool
    product_id: Optional[str]
    expires_at: Optional[datetime]
    auto_renew: bool
    status: str


class TrendPoint(BaseModel):
    label: str
    value: float


class AnalyticsOut(BaseModel):
    range_days: int
    weight: List[TrendPoint]
    steps: List[TrendPoint]
    calories: List[TrendPoint]
    water: List[TrendPoint]
    habit_completion: List[TrendPoint]
    insights: List[str]


# --- Weight prediction -------------------------------------------------------


class ProjectionPoint(BaseModel):
    date: date
    weight_kg: float


class PredictionOut(BaseModel):
    has_enough_data: bool
    reason: Optional[str] = None
    current_kg: Optional[float] = None
    smoothed_kg: Optional[float] = None
    start_kg: Optional[float] = None
    goal_kg: Optional[float] = None
    remaining_kg: float = 0.0
    lost_kg: float = 0.0
    trend_kg_per_week: float = 0.0
    confidence: str = "low"
    r_squared: float = 0.0
    goal_date: Optional[date] = None
    weeks_to_goal: Optional[int] = None
    goal_reachable: bool = False
    weekly_projection: List[ProjectionPoint] = Field(default_factory=list)
    monthly_projection: List[ProjectionPoint] = Field(default_factory=list)
    plateau_detected: bool = False
    notes: List[str] = Field(default_factory=list)


# --- Daily check-in ----------------------------------------------------------


class CheckInQuestion(BaseModel):
    id: str
    text: str
    type: str
    min: Optional[float] = None
    max: Optional[float] = None
    labels: Optional[List[str]] = None
    options: Optional[List[str]] = None
    max_length: Optional[int] = None


class CheckInPrompt(BaseModel):
    """Today's questions plus whether the user already completed the check-in."""

    recorded_on: date
    completed: bool
    questions: List[CheckInQuestion]
    metrics: dict
    streak: int


class CheckInSubmit(BaseModel):
    answers: Dict[str, Any] = Field(default_factory=dict)
    recorded_on: Optional[date] = None


class CheckInOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    recorded_on: date
    answers: dict
    metrics: dict
    mood: Optional[int]
    energy: Optional[int]
    adherence: Optional[int]
    summary: Optional[str]
    recommendations: List[str] = Field(default_factory=list)
    focus: Optional[str]
    provider: Optional[str]
    created_at: datetime


class CheckInHistoryOut(BaseModel):
    streak: int
    entries: List[CheckInOut]
