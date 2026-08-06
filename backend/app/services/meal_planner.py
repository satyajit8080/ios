"""AI meal plan + grocery list generation."""
from datetime import date, timedelta
from typing import Any, Dict, List

from app.services import ai

PLAN_SYSTEM = """You generate practical meal plans for a weight-loss app. Return JSON only.

Schema:
{"days":[{"date":"YYYY-MM-DD","total_calories":number,"meals":[{"meal_type":"breakfast|lunch|dinner|snack",
"name":str,"calories":number,"protein_g":number,"carbs_g":number,"fat_g":number,"ingredients":[str],"prep_minutes":number,
"recipe":str}]}],
"grocery_list":{"produce":[str],"protein":[str],"dairy":[str],"pantry":[str],"other":[str]},
"notes":str}

Rules:
- Each day's total must land within 5% of the requested calorie target and never below it by more than 5%.
- Hit at least the protein target each day. Include fibre-rich foods and at least 3 vegetable servings daily.
- Repeat ingredients across days so the grocery list stays affordable; keep prep under 30 minutes on weekdays.
- Respect every stated exclusion and allergy without exception.
- Recipes are 2-4 sentences of plain instructions."""


async def generate(
    kind: str,
    start: date,
    calorie_target: int,
    protein_target: int,
    preferences: str,
    exclusions: List[str],
) -> Dict[str, Any]:
    days = 1 if kind == "day" else 7
    dates = [(start + timedelta(days=i)).isoformat() for i in range(days)]
    prompt = (
        f"Build a {days}-day plan for these dates: {', '.join(dates)}.\n"
        f"Daily calorie target: {calorie_target} kcal. Daily protein target: {protein_target} g.\n"
        f"Preferences: {preferences or 'none stated'}.\n"
        f"Must exclude: {', '.join(exclusions) if exclusions else 'nothing'}."
    )
    data = await ai.chat_json([{"role": "user", "content": prompt}], system=PLAN_SYSTEM, max_tokens=6000)
    data.setdefault("days", [])
    data.setdefault("grocery_list", {})
    data.setdefault("notes", "")
    return data
