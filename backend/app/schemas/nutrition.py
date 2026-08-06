from datetime import date, datetime
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class FoodOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    name: str
    brand: Optional[str]
    serving_label: str
    serving_grams: float
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float
    sugar_g: float


class FoodCreate(BaseModel):
    name: str = Field(max_length=200)
    brand: Optional[str] = Field(default=None, max_length=120)
    serving_label: str = "100 g"
    serving_grams: float = Field(default=100, gt=0, le=5000)
    calories: float = Field(ge=0, le=2000)
    protein_g: float = Field(default=0, ge=0, le=300)
    carbs_g: float = Field(default=0, ge=0, le=300)
    fat_g: float = Field(default=0, ge=0, le=300)
    fiber_g: float = Field(default=0, ge=0, le=100)
    sugar_g: float = Field(default=0, ge=0, le=300)


class MealLogCreate(BaseModel):
    name: str = Field(max_length=200)
    meal_type: str = Field(default="lunch", pattern="^(breakfast|lunch|dinner|snack)$")
    quantity_g: float = Field(default=100, gt=0, le=5000)
    calories: float = Field(ge=0, le=10000)
    protein_g: float = Field(default=0, ge=0)
    carbs_g: float = Field(default=0, ge=0)
    fat_g: float = Field(default=0, ge=0)
    food_id: Optional[UUID] = None
    source: str = "manual"
    image_url: Optional[str] = None
    recorded_on: Optional[date] = None


class MealLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    name: str
    meal_type: str
    quantity_g: float
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    source: str
    image_url: Optional[str]
    recorded_on: date
    logged_at: datetime


class DaySummary(BaseModel):
    recorded_on: date
    calorie_target: int
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    remaining_calories: float
    meals: List[MealLogOut]


class VisionItem(BaseModel):
    name: str
    quantity_g: float
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    confidence: float


class VisionResult(BaseModel):
    items: List[VisionItem]
    total_calories: float
    total_protein_g: float
    total_carbs_g: float
    total_fat_g: float
    notes: str


class MealPlanRequest(BaseModel):
    kind: str = Field(default="week", pattern="^(day|week)$")
    start_date: Optional[date] = None
    preferences: Optional[str] = Field(default=None, max_length=500)
    exclusions: List[str] = Field(default_factory=list, max_length=25)


class MealPlanOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    start_date: date
    end_date: date
    kind: str
    calorie_target: int
    days: dict
    grocery_list: dict
    created_at: datetime
