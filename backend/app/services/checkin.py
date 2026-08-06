"""Daily coach check-in.

Assembles the day's numbers, asks a short set of questions, and turns the pair into
a short analysis plus two or three concrete recommendations. The analysis is written
by the AI but constrained: the prompt forbids calorie targets below the clinical
floor, and any risk language in the user's answers routes to support instead.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any, Dict, List, Optional, Sequence, Tuple

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models import DailyCheckIn, MealLog, StepEntry, User, WaterEntry, WeightEntry
from app.services import ai, coach, prediction

settings = get_settings()

CHECKIN_SYSTEM = """You are a supportive, evidence-based weight-loss coach writing a short daily check-in analysis.

You are given the user's recent numbers and their answers to today's check-in questions.

Rules you must not break:
- Never recommend a daily calorie intake below 1200 kcal for women or 1500 kcal for men.
- Never recommend losing more than 1 kg per week.
- Never suggest skipping meals, fasting beyond 16 hours, purging, laxatives, or "earning" food with exercise.
- Do not moralise about food. No "good"/"bad"/"cheat"/"guilty" framing.
- Day-to-day weight noise is water, not fat. Never interpret a single day's change as fat gain or loss.
- If the numbers are thin or missing, say so plainly rather than inventing a pattern.

Respond with JSON only, no markdown fences, in exactly this shape:
{
  "summary": "2-3 sentences on what the numbers and answers actually show. Specific, not generic.",
  "recommendations": ["one concrete action", "another concrete action"],
  "focus": "a short phrase naming the single thing worth attention today"
}

Give 2-3 recommendations. Each must be something the user could do today, tied to their own data.
Keep the tone warm and matter-of-fact. Never more than 90 words in the summary."""

# Rotating pool so the check-in does not feel like the same form every morning.
QUESTION_POOL: List[Dict[str, Any]] = [
    {
        "id": "mood",
        "text": "How are you feeling today?",
        "type": "scale",
        "min": 1,
        "max": 5,
        "labels": ["Rough", "Low", "Okay", "Good", "Great"],
        "always": True,
    },
    {
        "id": "energy",
        "text": "How's your energy?",
        "type": "scale",
        "min": 1,
        "max": 5,
        "labels": ["Drained", "Low", "Fine", "Good", "Buzzing"],
        "always": True,
    },
    {
        "id": "adherence",
        "text": "How closely did yesterday go to plan?",
        "type": "scale",
        "min": 1,
        "max": 5,
        "labels": ["Not at all", "A little", "Mostly", "Closely", "Nailed it"],
        "always": True,
    },
    {"id": "sleep_hours", "text": "Roughly how many hours did you sleep?", "type": "number", "min": 0, "max": 14},
    {"id": "hunger", "text": "Were you hungry between meals yesterday?", "type": "choice",
     "options": ["Not really", "A bit", "Often", "Constantly"]},
    {"id": "biggest_hurdle", "text": "What got in the way yesterday, if anything?", "type": "text", "max_length": 280},
    {"id": "movement", "text": "Did you move deliberately yesterday, beyond normal walking?", "type": "choice",
     "options": ["No", "A short session", "A full workout"]},
    {"id": "stress", "text": "How stressful was yesterday?", "type": "choice",
     "options": ["Calm", "Manageable", "Stressful", "Overwhelming"]},
    {"id": "eating_out", "text": "Did you eat out or order in?", "type": "choice", "options": ["No", "Once", "More than once"]},
    {"id": "win", "text": "What went well, however small?", "type": "text", "max_length": 280},
]

ROTATING_IDS = [q["id"] for q in QUESTION_POOL if not q.get("always")]


def questions_for(day: date) -> List[Dict[str, Any]]:
    """Three fixed scales plus two rotating questions chosen by day-of-year."""
    fixed = [q for q in QUESTION_POOL if q.get("always")]
    pool = [q for q in QUESTION_POOL if not q.get("always")]
    if not pool:
        return fixed
    offset = day.toordinal() % len(pool)
    rotating = [pool[offset], pool[(offset + 1) % len(pool)]]
    return fixed + rotating


def gather_metrics(db: Session, user: User, today: Optional[date] = None) -> Dict[str, Any]:
    """Snapshot the numbers the analysis reasons over."""
    today = today or date.today()
    week_ago = today - timedelta(days=7)
    month_ago = today - timedelta(days=30)

    weights: Sequence[Tuple[date, float]] = [
        (row.recorded_on, row.weight_kg)
        for row in db.scalars(
            select(WeightEntry)
            .where(WeightEntry.user_id == user.id, WeightEntry.recorded_on >= month_ago)
            .order_by(WeightEntry.recorded_on.asc())
        ).all()
    ]

    current_kg = weights[-1][1] if weights else None
    week_start_kg = next((w for d, w in weights if d >= week_ago), None)
    weight_change_7d = round(current_kg - week_start_kg, 2) if current_kg and week_start_kg else 0.0

    steps_rows = db.execute(
        select(StepEntry.recorded_on, StepEntry.steps)
        .where(StepEntry.user_id == user.id, StepEntry.recorded_on >= week_ago)
        .order_by(StepEntry.recorded_on.asc())
    ).all()
    step_values = [row.steps for row in steps_rows]
    steps_today = next((row.steps for row in steps_rows if row.recorded_on == today), 0)

    calorie_rows = db.execute(
        select(MealLog.recorded_on, func.sum(MealLog.calories).label("kcal"))
        .where(MealLog.user_id == user.id, MealLog.recorded_on >= week_ago)
        .group_by(MealLog.recorded_on)
    ).all()
    calorie_values = [float(row.kcal or 0) for row in calorie_rows]
    calories_yesterday = next(
        (float(row.kcal or 0) for row in calorie_rows if row.recorded_on == today - timedelta(days=1)), 0.0
    )

    water_today = db.scalar(
        select(func.coalesce(func.sum(WaterEntry.amount_ml), 0)).where(
            WaterEntry.user_id == user.id, WaterEntry.recorded_on == today
        )
    ) or 0

    forecast = prediction.predict(
        entries=weights,
        goal_kg=user.goal_weight_kg,
        start_kg=user.start_weight_kg,
        height_cm=user.height_cm,
        weekly_goal_kg=user.weekly_goal_kg,
        today=today,
    )

    return {
        "date": today.isoformat(),
        "current_weight_kg": current_kg,
        "weight_change_7d_kg": weight_change_7d,
        "weigh_ins_last_30d": len(weights),
        "trend_kg_per_week": round(forecast.trend_kg_per_week, 2),
        "trend_confidence": forecast.confidence,
        "plateau_detected": forecast.plateau_detected,
        "goal_weight_kg": user.goal_weight_kg,
        "remaining_kg": round(forecast.remaining_kg, 1),
        "calorie_target": user.daily_calorie_target,
        "calories_yesterday": round(calories_yesterday),
        "calories_avg_7d": round(sum(calorie_values) / len(calorie_values)) if calorie_values else 0,
        "days_logged_last_7": len(calorie_values),
        "steps_today": steps_today,
        "steps_avg_7d": round(sum(step_values) / len(step_values)) if step_values else 0,
        "step_target": user.daily_step_target,
        "water_ml_today": int(water_today),
        "water_target_ml": user.daily_water_ml_target,
    }


def _fallback_analysis(metrics: Dict[str, Any]) -> Dict[str, Any]:
    """Deterministic analysis used when the AI is unreachable.

    A check-in that silently fails is worse than a plain one, so this always returns
    something grounded in the numbers.
    """
    recommendations: List[str] = []

    if metrics["days_logged_last_7"] < 4:
        recommendations.append("Log your meals on at least four days this week — the coaching gets sharper with more data.")
    if metrics["steps_avg_7d"] and metrics["steps_avg_7d"] < metrics["step_target"] * 0.7:
        recommendations.append("Add a 15-minute walk after your largest meal; it closes most of the step gap on its own.")
    if metrics["water_ml_today"] < metrics["water_target_ml"] * 0.5:
        recommendations.append("You're behind on water for today. A glass now and one with each remaining meal covers it.")
    if metrics["plateau_detected"]:
        recommendations.append("Weigh in at the same time each morning this week so the trend line is comparable.")
    if not recommendations:
        recommendations.append("Keep doing what you're doing — the pattern in your numbers is working.")

    if metrics["current_weight_kg"] is None:
        summary = "No weigh-ins logged in the last month, so there's no trend to read yet. One entry a day at the same time gives us something to work with inside a fortnight."
    else:
        direction = "down" if metrics["trend_kg_per_week"] < -0.05 else "up" if metrics["trend_kg_per_week"] > 0.05 else "flat"
        summary = (
            f"You're at {metrics['current_weight_kg']} kg and the trend is {direction} "
            f"({metrics['trend_kg_per_week']:+.2f} kg a week). "
            f"You logged food on {metrics['days_logged_last_7']} of the last 7 days "
            f"and averaged {metrics['steps_avg_7d']:,} steps."
        )

    return {
        "summary": summary,
        "recommendations": recommendations[:3],
        "focus": "Consistency over intensity",
        "provider": "fallback",
    }


async def analyse(db: Session, user: User, answers: Dict[str, Any], metrics: Dict[str, Any]) -> Dict[str, Any]:
    """Produce summary, recommendations and focus for a check-in."""
    free_text = " ".join(str(value) for value in answers.values() if isinstance(value, str))
    if free_text and coach.has_risk_language(free_text):
        return {
            "summary": (
                "I'm going to set the numbers aside today. What you wrote sounds heavy, and it deserves a real "
                "person rather than an app. Please talk to your doctor or a mental-health professional — in the US "
                "you can call or text 988 any time, and findahelpline.com lists services elsewhere."
            ),
            "recommendations": [
                "Reach out to someone you trust today, even briefly.",
                "Eat something regular today regardless of what the numbers say.",
            ],
            "focus": "Looking after yourself",
            "provider": "safety",
        }

    context = coach.build_context(db, user)
    payload = {"metrics": metrics, "answers": answers}
    user_prompt = (
        f"{context}\n\nToday's check-in data (JSON):\n{payload}\n\n"
        "Write the check-in analysis as JSON."
    )

    try:
        raw, provider = await ai.chat(
            [{"role": "user", "content": user_prompt}],
            system=CHECKIN_SYSTEM,
            max_tokens=600,
            temperature=0.3,
        )
        parsed = ai.parse_json(raw)
    except (ai.AIUnavailable, ValueError, KeyError):
        return _fallback_analysis(metrics)

    summary = str(parsed.get("summary") or "").strip()
    recommendations = [str(r).strip() for r in (parsed.get("recommendations") or []) if str(r).strip()]
    if not summary or not recommendations:
        return _fallback_analysis(metrics)

    return {
        "summary": summary[:1200],
        "recommendations": recommendations[:3],
        "focus": str(parsed.get("focus") or "").strip()[:160] or None,
        "provider": provider,
    }


def streak(db: Session, user: User, today: Optional[date] = None) -> int:
    """Consecutive days ending today (or yesterday) with a completed check-in."""
    today = today or date.today()
    days = set(
        db.scalars(
            select(DailyCheckIn.recorded_on)
            .where(DailyCheckIn.user_id == user.id, DailyCheckIn.recorded_on >= today - timedelta(days=400))
        ).all()
    )
    if not days:
        return 0

    cursor = today if today in days else today - timedelta(days=1)
    count = 0
    while cursor in days:
        count += 1
        cursor -= timedelta(days=1)
    return count
