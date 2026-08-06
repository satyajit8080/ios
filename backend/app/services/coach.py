"""AI coach context builder + long-term user memory extraction."""
import json
import logging
from datetime import date, timedelta
from typing import Dict, List

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import ChatMessage, HabitLog, MealLog, StepEntry, User, UserMemory, WaterEntry, WeightEntry
from app.services import ai
from app.services.metrics import bmi, bmi_category

logger = logging.getLogger(__name__)

MEMORY_SYSTEM = """Extract durable facts about the user worth remembering for future coaching.
Return JSON only: {"memories":[{"key":str,"value":str}]}
Allowed keys: diet_style, allergies, dislikes, likes, injuries, schedule, motivation, medical_note, equipment, cooking_skill.
Only include facts that will still be true next month. Return an empty array if there is nothing durable.
Never store weights, calorie numbers, or anything about self-harm."""

# Substring matches. Kept deliberately broad: a false positive costs one supportive
# reply, a false negative sends coaching numbers to someone in crisis.
RISK_TERMS = [
    # purging
    "purge", "purging", "vomit", "throw up", "threw up", "throwing up", "make myself sick",
    "made myself sick", "laxative", "diuretic", "chew and spit",
    # restriction
    "starve", "starving", "not eating", "stopped eating", "skip meals", "skipping meals",
    "haven't eaten", "havent eaten", "nothing to eat all day", "fasting for days",
    # diagnoses and identity
    "anorexi", "bulimi", "ed relapse", "eating disorder", "binge and purge",
    # self-directed harm and hopelessness
    "hate my body", "disgusting body", "kill myself", "suicid", "end it all",
    "self harm", "self-harm", "cutting myself", "hurt myself", "worthless",
    "better off dead", "no point anymore", "hate myself",
]


def has_risk_language(text: str) -> bool:
    """True when the text contains language that should bypass coaching entirely.

    Substring matching is intentional. "throw up" catches "throwing up" only via the
    separate entry, so common inflections are listed explicitly rather than relying
    on stemming, which would add a dependency for no real gain here.
    """
    lowered = text.lower()
    return any(term in lowered for term in RISK_TERMS)


def build_context(db: Session, user: User) -> str:
    today = date.today()
    week_ago = today - timedelta(days=7)
    month_ago = today - timedelta(days=30)

    latest_weight = db.scalar(
        select(WeightEntry).where(WeightEntry.user_id == user.id).order_by(WeightEntry.recorded_on.desc())
    )
    month_weight = db.scalar(
        select(WeightEntry)
        .where(WeightEntry.user_id == user.id, WeightEntry.recorded_on >= month_ago)
        .order_by(WeightEntry.recorded_on.asc())
    )
    avg_steps = db.scalar(
        select(func.avg(StepEntry.steps)).where(StepEntry.user_id == user.id, StepEntry.recorded_on >= week_ago)
    )
    avg_cals = db.scalar(
        select(func.avg(MealLog.calories)).where(MealLog.user_id == user.id, MealLog.recorded_on >= week_ago)
    )
    today_cals = db.scalar(
        select(func.sum(MealLog.calories)).where(MealLog.user_id == user.id, MealLog.recorded_on == today)
    )
    today_water = db.scalar(
        select(func.sum(WaterEntry.amount_ml)).where(WaterEntry.user_id == user.id, WaterEntry.recorded_on == today)
    )
    habit_days = db.scalar(
        select(func.count(func.distinct(HabitLog.recorded_on))).where(
            HabitLog.user_id == user.id, HabitLog.recorded_on >= week_ago
        )
    )

    current = latest_weight.weight_kg if latest_weight else None
    value = bmi(current, user.height_cm)
    memories = db.scalars(select(UserMemory).where(UserMemory.user_id == user.id)).all()

    lines = [
        f"Name: {user.full_name or 'not given'}",
        f"Goal weight: {user.goal_weight_kg} kg | Start: {user.start_weight_kg} kg | Current: {current} kg",
        f"Weekly goal: {user.weekly_goal_kg} kg/week | Activity: {user.activity_level}",
        f"BMI: {value} ({bmi_category(value)})" if value else "BMI: unknown",
        f"Daily targets: {user.daily_calorie_target} kcal, {user.daily_water_ml_target} ml water, {user.daily_step_target} steps",
        f"Today so far: {int(today_cals or 0)} kcal, {int(today_water or 0)} ml water",
        f"7-day averages: {int(avg_steps or 0)} steps/day, {int(avg_cals or 0)} kcal per logged meal",
        f"Habit days logged this week: {habit_days or 0}",
    ]
    if month_weight and current is not None:
        lines.append(f"30-day weight change: {round(current - month_weight.weight_kg, 1)} kg")
    if memories:
        lines.append("Remembered about this user: " + "; ".join(f"{m.key}={m.value}" for m in memories))
    return "\n".join(lines)


def history(db: Session, user: User, limit: int = 20) -> List[Dict[str, str]]:
    rows = db.scalars(
        select(ChatMessage)
        .where(ChatMessage.user_id == user.id)
        .order_by(ChatMessage.created_at.desc())
        .limit(limit)
    ).all()
    return [{"role": r.role, "content": r.content} for r in reversed(rows)]


async def extract_memories(db: Session, user: User, transcript: List[Dict[str, str]]) -> int:
    try:
        payload = await ai.chat_json(
            [{"role": "user", "content": json.dumps(transcript[-6:])}],
            system=MEMORY_SYSTEM,
            max_tokens=600,
        )
    except Exception as exc:
        logger.info("memory extraction skipped: %s", exc)
        return 0

    saved = 0
    for item in payload.get("memories", [])[:10]:
        key, value = str(item.get("key", ""))[:64], str(item.get("value", ""))[:400]
        if not key or not value:
            continue
        existing = db.scalar(select(UserMemory).where(UserMemory.user_id == user.id, UserMemory.key == key))
        if existing:
            existing.value = value
        else:
            db.add(UserMemory(user_id=user.id, key=key, value=value))
        saved += 1
    db.commit()
    return saved
