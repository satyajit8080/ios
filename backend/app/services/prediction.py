"""Weight trajectory projection.

Deliberately conservative. A weight-loss projection is easy to make motivating and
misleading at the same time, so this module refuses to extrapolate from thin data,
caps the rate it will project at the same clinical ceiling the calorie targets use,
and never projects below a healthy BMI floor.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Dict, List, Optional, Sequence, Tuple

from app.core.config import get_settings

settings = get_settings()

MIN_ENTRIES_FOR_TREND = 4
MIN_SPAN_DAYS = 10
MAX_PROJECTION_DAYS = 730
HEALTHY_BMI_FLOOR = 18.5
EWMA_ALPHA = 0.25


@dataclass
class Projection:
    """A single projected point on the trajectory."""

    day: date
    weight_kg: float


@dataclass
class PredictionResult:
    has_enough_data: bool
    reason: Optional[str] = None

    current_kg: Optional[float] = None
    smoothed_kg: Optional[float] = None
    start_kg: Optional[float] = None
    goal_kg: Optional[float] = None
    remaining_kg: float = 0.0
    lost_kg: float = 0.0

    trend_kg_per_week: float = 0.0
    confidence: str = "low"          # low | moderate | high
    r_squared: float = 0.0

    goal_date: Optional[date] = None
    weeks_to_goal: Optional[int] = None
    goal_reachable: bool = False

    weekly_projection: List[Projection] = field(default_factory=list)
    monthly_projection: List[Projection] = field(default_factory=list)

    plateau_detected: bool = False
    notes: List[str] = field(default_factory=list)

    def as_dict(self) -> Dict:
        return {
            "has_enough_data": self.has_enough_data,
            "reason": self.reason,
            "current_kg": _round(self.current_kg),
            "smoothed_kg": _round(self.smoothed_kg),
            "start_kg": _round(self.start_kg),
            "goal_kg": _round(self.goal_kg),
            "remaining_kg": round(self.remaining_kg, 1),
            "lost_kg": round(self.lost_kg, 1),
            "trend_kg_per_week": round(self.trend_kg_per_week, 2),
            "confidence": self.confidence,
            "r_squared": round(self.r_squared, 3),
            "goal_date": self.goal_date.isoformat() if self.goal_date else None,
            "weeks_to_goal": self.weeks_to_goal,
            "goal_reachable": self.goal_reachable,
            "weekly_projection": [
                {"date": p.day.isoformat(), "weight_kg": _round(p.weight_kg)} for p in self.weekly_projection
            ],
            "monthly_projection": [
                {"date": p.day.isoformat(), "weight_kg": _round(p.weight_kg)} for p in self.monthly_projection
            ],
            "plateau_detected": self.plateau_detected,
            "notes": self.notes,
        }


def _round(value: Optional[float]) -> Optional[float]:
    return None if value is None else round(value, 1)


def _ewma(values: Sequence[float], alpha: float = EWMA_ALPHA) -> float:
    """Exponentially weighted mean, most recent sample weighted heaviest.

    Daily scale readings swing a kilo or more on water alone, so the raw latest
    value is a poor anchor for a projection.
    """
    if not values:
        return 0.0
    smoothed = values[0]
    for value in values[1:]:
        smoothed = alpha * value + (1 - alpha) * smoothed
    return smoothed


def _linear_fit(points: Sequence[Tuple[float, float]]) -> Tuple[float, float, float]:
    """Ordinary least squares. Returns (slope_per_day, intercept, r_squared)."""
    n = len(points)
    if n < 2:
        return 0.0, points[0][1] if points else 0.0, 0.0

    mean_x = sum(x for x, _ in points) / n
    mean_y = sum(y for _, y in points) / n

    sxx = sum((x - mean_x) ** 2 for x, _ in points)
    sxy = sum((x - mean_x) * (y - mean_y) for x, y in points)
    if sxx == 0:
        return 0.0, mean_y, 0.0

    slope = sxy / sxx
    intercept = mean_y - slope * mean_x

    ss_tot = sum((y - mean_y) ** 2 for _, y in points)
    ss_res = sum((y - (slope * x + intercept)) ** 2 for x, y in points)
    if ss_tot == 0:
        # Every reading identical: the line explains the data exactly. This is the
        # clearest plateau there is, so it must not score as low confidence.
        r_squared = 1.0
    else:
        r_squared = max(0.0, 1 - ss_res / ss_tot)

    return slope, intercept, r_squared


def _confidence(entry_count: int, span_days: int, r_squared: float) -> str:
    if entry_count >= 12 and span_days >= 28 and r_squared >= 0.5:
        return "high"
    if entry_count >= 7 and span_days >= 14 and r_squared >= 0.25:
        return "moderate"
    return "low"


def _healthy_floor_kg(height_cm: Optional[float]) -> Optional[float]:
    if not height_cm:
        return None
    metres = height_cm / 100
    return HEALTHY_BMI_FLOOR * metres * metres


def predict(
    entries: Sequence[Tuple[date, float]],
    goal_kg: Optional[float],
    start_kg: Optional[float] = None,
    height_cm: Optional[float] = None,
    weekly_goal_kg: float = 0.5,
    today: Optional[date] = None,
) -> PredictionResult:
    """Project a weight trajectory from logged entries.

    `entries` must be (date, weight_kg) pairs. Order does not matter.
    """
    today = today or date.today()
    ordered = sorted(entries, key=lambda item: item[0])

    if not ordered:
        return PredictionResult(
            has_enough_data=False,
            reason="No weigh-ins logged yet.",
            goal_kg=goal_kg,
        )

    current = ordered[-1][1]
    first_day, first_weight = ordered[0]
    span_days = (ordered[-1][0] - first_day).days
    anchor = start_kg if start_kg is not None else first_weight

    result = PredictionResult(
        has_enough_data=False,
        current_kg=current,
        start_kg=anchor,
        goal_kg=goal_kg,
        lost_kg=max(anchor - current, 0.0) if anchor else 0.0,
        remaining_kg=max(current - goal_kg, 0.0) if goal_kg else 0.0,
    )

    if len(ordered) < MIN_ENTRIES_FOR_TREND or span_days < MIN_SPAN_DAYS:
        needed = max(MIN_ENTRIES_FOR_TREND - len(ordered), 0)
        result.reason = (
            f"Log {needed} more weigh-in{'s' if needed != 1 else ''} over at least "
            f"{MIN_SPAN_DAYS} days and a projection becomes meaningful."
            if needed
            else f"Keep logging for another {MIN_SPAN_DAYS - span_days} days to establish a trend."
        )
        result.smoothed_kg = _ewma([w for _, w in ordered])
        return result

    # Fit against the recent window; older data describes a different person's habits.
    window_start = today - timedelta(days=90)
    windowed = [item for item in ordered if item[0] >= window_start] or ordered
    points = [((day - windowed[0][0]).days, weight) for day, weight in windowed]

    slope_per_day, _, r_squared = _linear_fit(points)
    smoothed = _ewma([w for _, w in windowed])

    result.has_enough_data = True
    result.smoothed_kg = smoothed
    result.r_squared = r_squared
    result.trend_kg_per_week = slope_per_day * 7
    result.confidence = _confidence(len(windowed), (windowed[-1][0] - windowed[0][0]).days, r_squared)

    # A loss faster than the clinical ceiling is almost always water or a fluke run.
    # Project at the capped rate rather than flattering the user with the raw slope.
    capped_weekly = result.trend_kg_per_week
    if capped_weekly < -settings.MAX_WEEKLY_LOSS_KG:
        capped_weekly = -settings.MAX_WEEKLY_LOSS_KG
        result.notes.append(
            "Your recent rate is faster than 1 kg a week, so the projection uses a steadier rate. "
            "Sharp early drops are usually water, not fat."
        )
    projection_slope = capped_weekly / 7

    if abs(result.trend_kg_per_week) < 0.1 and result.confidence != "low":
        result.plateau_detected = True
        result.notes.append(
            "Weight has been broadly flat for a few weeks. Plateaus are normal, and usually "
            "resolve with a look at portion drift rather than a bigger deficit."
        )

    floor = _healthy_floor_kg(height_cm)
    if floor and goal_kg and goal_kg < floor:
        result.notes.append(
            f"Your goal sits below a BMI of {HEALTHY_BMI_FLOOR}. Worth talking through with a doctor "
            "before aiming lower."
        )

    result.weekly_projection = _build_projection(
        smoothed, projection_slope, today, step_days=7, count=12, floor=floor, goal_kg=goal_kg
    )
    result.monthly_projection = _build_projection(
        smoothed, projection_slope, today, step_days=30, count=6, floor=floor, goal_kg=goal_kg
    )

    if goal_kg is not None:
        _apply_goal_date(result, smoothed, projection_slope, goal_kg, today, weekly_goal_kg)

    return result


def _build_projection(
    anchor_kg: float,
    slope_per_day: float,
    today: date,
    step_days: int,
    count: int,
    floor: Optional[float],
    goal_kg: Optional[float],
) -> List[Projection]:
    points: List[Projection] = []
    hard_floor = max(x for x in [floor, goal_kg, 35.0] if x is not None)
    for index in range(1, count + 1):
        offset = index * step_days
        value = anchor_kg + slope_per_day * offset
        value = max(value, hard_floor)
        points.append(Projection(day=today + timedelta(days=offset), weight_kg=value))
        if value <= hard_floor:
            break
    return points


def _apply_goal_date(
    result: PredictionResult,
    anchor_kg: float,
    slope_per_day: float,
    goal_kg: float,
    today: date,
    weekly_goal_kg: float,
) -> None:
    if anchor_kg <= goal_kg:
        result.goal_reachable = True
        result.goal_date = today
        result.weeks_to_goal = 0
        result.notes.append("You're at or past your goal weight. Maintenance is its own skill — worth asking the coach about.")
        return

    if slope_per_day >= -0.0001:
        # Not currently losing. Fall back to what the chosen pace would deliver,
        # but label it as a plan rather than a measured trajectory.
        planned_weekly = min(max(weekly_goal_kg, 0.1), settings.MAX_WEEKLY_LOSS_KG)
        weeks = (anchor_kg - goal_kg) / planned_weekly
        if weeks * 7 <= MAX_PROJECTION_DAYS:
            result.goal_date = today + timedelta(days=int(round(weeks * 7)))
            result.weeks_to_goal = int(round(weeks))
        result.goal_reachable = False
        result.notes.append(
            "Your current trend isn't heading downward, so this date reflects your chosen pace "
            "rather than what's actually happening. Worth a check-in with the coach."
        )
        return

    days = (anchor_kg - goal_kg) / abs(slope_per_day)
    if days > MAX_PROJECTION_DAYS:
        result.goal_reachable = False
        result.notes.append(
            "At the current rate your goal is more than two years out. A slightly larger deficit "
            "or more daily movement would change that meaningfully."
        )
        return

    result.goal_reachable = True
    result.goal_date = today + timedelta(days=int(round(days)))
    result.weeks_to_goal = int(round(days / 7))
