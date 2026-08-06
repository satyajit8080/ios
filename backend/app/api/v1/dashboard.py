from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.core.redis_client import cache_get, cache_set
from app.db.session import get_db
from app.models import Habit, HabitLog, MealLog, StepEntry, User, WaterEntry, WeightEntry
from app.schemas.misc import DashboardOut
from app.services.metrics import bmi, bmi_category, goal_progress_pct, level_for_xp
from app.services.streaks import streaks

router = APIRouter(tags=["dashboard"])


@router.get("/dashboard", response_model=DashboardOut)
def dashboard(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    today = date.today()
    cache_key = f"dash:{user.id}:{today.isoformat()}"
    cached = cache_get(cache_key)
    if cached:
        return DashboardOut(**cached)

    since = today - timedelta(days=29)

    weights = db.scalars(
        select(WeightEntry)
        .where(WeightEntry.user_id == user.id, WeightEntry.recorded_on >= since)
        .order_by(WeightEntry.recorded_on.asc())
    ).all()
    latest = db.scalar(
        select(WeightEntry).where(WeightEntry.user_id == user.id).order_by(WeightEntry.recorded_on.desc())
    )
    current = latest.weight_kg if latest else None
    week_ref = next((w.weight_kg for w in weights if w.recorded_on <= today - timedelta(days=7)), None)
    if week_ref is None and weights:
        week_ref = weights[0].weight_kg

    meals = db.scalars(
        select(MealLog).where(MealLog.user_id == user.id, MealLog.recorded_on == today)
    ).all()
    calorie_rows = db.execute(
        select(MealLog.recorded_on, func.sum(MealLog.calories))
        .where(MealLog.user_id == user.id, MealLog.recorded_on >= since)
        .group_by(MealLog.recorded_on)
        .order_by(MealLog.recorded_on.asc())
    ).all()

    water_today = db.scalar(
        select(func.sum(WaterEntry.amount_ml)).where(
            WaterEntry.user_id == user.id, WaterEntry.recorded_on == today
        )
    ) or 0

    steps_rows = db.scalars(
        select(StepEntry)
        .where(StepEntry.user_id == user.id, StepEntry.recorded_on >= since)
        .order_by(StepEntry.recorded_on.asc())
    ).all()
    steps_today = next((s.steps for s in steps_rows if s.recorded_on == today), 0)
    streak, _ = streaks([s.recorded_on for s in steps_rows if s.steps >= user.daily_step_target], today)

    habits = db.scalars(select(Habit).where(Habit.user_id == user.id, Habit.archived.is_(False))).all()
    habit_logs = db.scalars(
        select(HabitLog).where(HabitLog.user_id == user.id, HabitLog.recorded_on == today)
    ).all()
    done_map = {log.habit_id: log.count for log in habit_logs}
    habits_done = sum(1 for h in habits if done_map.get(h.id, 0) >= h.target_per_day)

    calories = sum(m.calories for m in meals)
    value = bmi(current, user.height_cm)
    level, _into, _need = level_for_xp(user.xp or 0)

    result = DashboardOut(
        date=today,
        weight_kg=current,
        weight_change_7d_kg=round(current - week_ref, 2) if current is not None and week_ref else 0.0,
        bmi=value,
        bmi_category=bmi_category(value),
        goal_weight_kg=user.goal_weight_kg,
        goal_progress_pct=goal_progress_pct(user.start_weight_kg, current, user.goal_weight_kg),
        calories_consumed=round(calories, 1),
        calorie_target=user.daily_calorie_target,
        calories_remaining=round(user.daily_calorie_target - calories, 1),
        protein_g=round(sum(m.protein_g for m in meals), 1),
        carbs_g=round(sum(m.carbs_g for m in meals), 1),
        fat_g=round(sum(m.fat_g for m in meals), 1),
        water_ml=int(water_today),
        water_target_ml=user.daily_water_ml_target,
        steps=steps_today,
        step_target=user.daily_step_target,
        step_streak=streak,
        habits_done=habits_done,
        habits_total=len(habits),
        xp=user.xp or 0,
        level=level,
        weight_series=[{"date": w.recorded_on.isoformat(), "value": w.weight_kg} for w in weights],
        calorie_series=[{"date": r[0].isoformat(), "value": float(r[1] or 0)} for r in calorie_rows],
        step_series=[{"date": s.recorded_on.isoformat(), "value": s.steps} for s in steps_rows],
    )
    cache_set(cache_key, result.model_dump(mode="json"), ttl=60)
    return result
