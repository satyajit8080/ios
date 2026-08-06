"""Body metric + target calculations with hard safety floors."""
from datetime import date
from typing import Optional, Tuple

from app.core.config import settings

ACTIVITY_FACTORS = {
    "sedentary": 1.2,
    "light": 1.375,
    "moderate": 1.55,
    "active": 1.725,
    "athlete": 1.9,
}


def age_from_birth_date(birth_date: Optional[date], today: Optional[date] = None) -> int:
    if not birth_date:
        return 30
    today = today or date.today()
    return max(
        14,
        today.year - birth_date.year - ((today.month, today.day) < (birth_date.month, birth_date.day)),
    )


def bmi(weight_kg: Optional[float], height_cm: Optional[float]) -> Optional[float]:
    if not weight_kg or not height_cm or height_cm <= 0:
        return None
    return round(weight_kg / ((height_cm / 100) ** 2), 1)


def bmi_category(value: Optional[float]) -> Optional[str]:
    if value is None:
        return None
    if value < 18.5:
        return "Underweight"
    if value < 25:
        return "Healthy"
    if value < 30:
        return "Overweight"
    return "Obese"


def bmr(weight_kg: float, height_cm: float, age: int, gender: str) -> float:
    """Mifflin-St Jeor."""
    base = 10 * weight_kg + 6.25 * height_cm - 5 * age
    if gender == "male":
        return base + 5
    if gender == "female":
        return base - 161
    return base - 78


def tdee(weight_kg: float, height_cm: float, age: int, gender: str, activity: str) -> float:
    return bmr(weight_kg, height_cm, age, gender) * ACTIVITY_FACTORS.get(activity, 1.55)


def calorie_target(
    weight_kg: Optional[float],
    height_cm: Optional[float],
    age: int,
    gender: str,
    activity: str,
    weekly_goal_kg: float,
) -> int:
    """Daily calorie target, clamped so it can never fall below clinical floors."""
    if not weight_kg or not height_cm:
        return 2000
    weekly_goal_kg = min(max(weekly_goal_kg, 0.0), settings.MAX_WEEKLY_LOSS_KG)
    maintenance = tdee(weight_kg, height_cm, age, gender, activity)
    deficit = (weekly_goal_kg * 7700) / 7
    target = maintenance - deficit
    floor = settings.MIN_CALORIES_MALE if gender == "male" else settings.MIN_CALORIES_FEMALE
    target = max(target, floor, maintenance * 0.75)
    return int(round(target / 10) * 10)


def macro_targets(calories: int, weight_kg: Optional[float]) -> Tuple[int, int, int]:
    protein_g = int(round((weight_kg or 70) * 1.6))
    protein_kcal = protein_g * 4
    fat_kcal = calories * 0.28
    carbs_kcal = max(calories - protein_kcal - fat_kcal, calories * 0.2)
    return protein_g, int(round(carbs_kcal / 4)), int(round(fat_kcal / 9))


def water_target_ml(weight_kg: Optional[float]) -> int:
    return int(min(max((weight_kg or 70) * 33, 1500), 4000))


def goal_progress_pct(start: Optional[float], current: Optional[float], goal: Optional[float]) -> float:
    if start is None or current is None or goal is None or start == goal:
        return 0.0
    pct = (start - current) / (start - goal) * 100
    return round(min(max(pct, 0.0), 100.0), 1)


def level_for_xp(xp: int) -> tuple[int, int, int]:
    """Returns (level, xp_into_level, xp_needed_for_next)."""
    level, remaining, need = 1, max(xp, 0), 100
    while remaining >= need:
        remaining -= need
        level += 1
        need = int(need * 1.35)
    return level, remaining, need
