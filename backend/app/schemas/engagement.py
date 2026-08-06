from datetime import date, datetime
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class HabitCreate(BaseModel):
    name: str = Field(max_length=120)
    icon: str = "checkmark.seal"
    color: str = "#2E9E7B"
    target_per_day: int = Field(default=1, ge=1, le=20)


class HabitOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    name: str
    icon: str
    color: str
    target_per_day: int
    archived: bool


class HabitWithStats(BaseModel):
    habit: HabitOut
    done_today: int
    current_streak: int
    longest_streak: int
    last_30_days: List[date]


class HabitLogCreate(BaseModel):
    recorded_on: Optional[date] = None
    count: int = Field(default=1, ge=0, le=20)


class BadgeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    code: str
    name: str
    description: str
    icon: str
    xp_reward: int


class EarnedBadgeOut(BaseModel):
    badge: BadgeOut
    earned_at: datetime


class GamificationOut(BaseModel):
    xp: int
    level: int
    xp_into_level: int
    xp_for_next_level: int
    badges: List[EarnedBadgeOut]
    locked_badges: List[BadgeOut]


class ChallengeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    code: str
    title: str
    subtitle: str
    description: str
    kind: str
    duration_days: int
    target_value: float
    xp_reward: int
    premium_only: bool


class ChallengeStatus(BaseModel):
    challenge: ChallengeOut
    joined: bool
    progress: float
    progress_pct: float
    days_left: int
    completed: bool
    participants: int
