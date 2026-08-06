from datetime import date, timedelta
from typing import List

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.db.session import get_db
from app.models import AnalyticsEvent, Habit, HabitLog, MealLog, StepEntry, User, WaterEntry, WeightEntry
from app.schemas.misc import AnalyticsOut, TrendPoint

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.post("/events", status_code=204)
def track_event(
    name: str = Query(max_length=64),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    db.add(AnalyticsEvent(user_id=user.id, name=name, props={}))
    db.commit()


@router.get("", response_model=AnalyticsOut)
def analytics(
    days: int = Query(30, ge=7, le=365),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    today = date.today()
    since = today - timedelta(days=days - 1)

    weights = db.scalars(
        select(WeightEntry)
        .where(WeightEntry.user_id == user.id, WeightEntry.recorded_on >= since)
        .order_by(WeightEntry.recorded_on.asc())
    ).all()
    steps = db.scalars(
        select(StepEntry)
        .where(StepEntry.user_id == user.id, StepEntry.recorded_on >= since)
        .order_by(StepEntry.recorded_on.asc())
    ).all()
    calories = db.execute(
        select(MealLog.recorded_on, func.sum(MealLog.calories))
        .where(MealLog.user_id == user.id, MealLog.recorded_on >= since)
        .group_by(MealLog.recorded_on)
        .order_by(MealLog.recorded_on.asc())
    ).all()
    water = db.execute(
        select(WaterEntry.recorded_on, func.sum(WaterEntry.amount_ml))
        .where(WaterEntry.user_id == user.id, WaterEntry.recorded_on >= since)
        .group_by(WaterEntry.recorded_on)
        .order_by(WaterEntry.recorded_on.asc())
    ).all()

    habit_count = db.scalar(
        select(func.count(Habit.id)).where(Habit.user_id == user.id, Habit.archived.is_(False))
    ) or 0
    habit_rows = db.execute(
        select(HabitLog.recorded_on, func.count(HabitLog.id))
        .where(HabitLog.user_id == user.id, HabitLog.recorded_on >= since, HabitLog.count > 0)
        .group_by(HabitLog.recorded_on)
        .order_by(HabitLog.recorded_on.asc())
    ).all()

    insights: List[str] = []
    if len(weights) >= 2:
        delta = weights[-1].weight_kg - weights[0].weight_kg
        span_weeks = max((weights[-1].recorded_on - weights[0].recorded_on).days / 7, 0.5)
        rate = delta / span_weeks
        if delta < -0.2:
            insights.append(f"You're down {abs(round(delta, 1))} kg over this window — about {abs(round(rate, 2))} kg per week.")
        elif delta > 0.2:
            insights.append(f"Weight is up {round(delta, 1)} kg across this window. Worth a look at portions and sleep.")
        else:
            insights.append("Weight is holding steady. A plateau after a loss phase is normal.")
    else:
        insights.append("Log your weight a few more times and trends will show up here.")

    if steps:
        avg = int(sum(s.steps for s in steps) / len(steps))
        insights.append(
            f"You average {avg:,} steps a day — {'above' if avg >= user.daily_step_target else 'below'} your "
            f"{user.daily_step_target:,} goal."
        )
    if calories:
        avg_cals = int(sum(float(r[1] or 0) for r in calories) / len(calories))
        insights.append(f"Logged intake averages {avg_cals:,} kcal on days you track, against a {user.daily_calorie_target:,} kcal target.")
    if habit_count and habit_rows:
        rate = sum(r[1] for r in habit_rows) / (len(habit_rows) * habit_count) * 100
        insights.append(f"You complete {int(rate)}% of your habits on the days you check in.")

    return AnalyticsOut(
        range_days=days,
        weight=[TrendPoint(label=w.recorded_on.isoformat(), value=w.weight_kg) for w in weights],
        steps=[TrendPoint(label=s.recorded_on.isoformat(), value=float(s.steps)) for s in steps],
        calories=[TrendPoint(label=r[0].isoformat(), value=float(r[1] or 0)) for r in calories],
        water=[TrendPoint(label=r[0].isoformat(), value=float(r[1] or 0)) for r in water],
        habit_completion=[
            TrendPoint(label=r[0].isoformat(), value=round(r[1] / habit_count * 100, 1) if habit_count else 0.0)
            for r in habit_rows
        ],
        insights=insights,
    )
