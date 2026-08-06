from datetime import date, datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    full_name: Optional[str] = Field(default=None, max_length=120)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class AppleSignInRequest(BaseModel):
    identity_token: str
    full_name: Optional[str] = None


class RefreshRequest(BaseModel):
    refresh_token: str


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str = Field(min_length=8, max_length=128)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: EmailStr
    full_name: Optional[str]
    gender: str
    birth_date: Optional[date]
    height_cm: Optional[float]
    activity_level: str
    start_weight_kg: Optional[float]
    goal_weight_kg: Optional[float]
    weekly_goal_kg: float
    daily_calorie_target: int
    daily_protein_target_g: int
    daily_water_ml_target: int
    daily_step_target: int
    timezone: str
    xp: int
    is_premium: bool
    is_admin: bool
    onboarded: bool
    premium_expires_at: Optional[datetime]
    created_at: datetime


class AuthResponse(BaseModel):
    user: UserOut
    tokens: TokenPair


class UserUpdate(BaseModel):
    full_name: Optional[str] = Field(default=None, max_length=120)
    gender: Optional[str] = None
    birth_date: Optional[date] = None
    height_cm: Optional[float] = Field(default=None, gt=60, lt=260)
    activity_level: Optional[str] = None
    start_weight_kg: Optional[float] = Field(default=None, gt=20, lt=400)
    goal_weight_kg: Optional[float] = Field(default=None, gt=20, lt=400)
    weekly_goal_kg: Optional[float] = Field(default=None, ge=0.1, le=1.0)
    daily_water_ml_target: Optional[int] = Field(default=None, ge=500, le=6000)
    daily_step_target: Optional[int] = Field(default=None, ge=1000, le=40000)
    timezone: Optional[str] = None
    onboarded: Optional[bool] = None
