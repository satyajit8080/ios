from datetime import date, timedelta
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, require_premium, throttle
from app.db.session import get_db
from app.models import MealPlan, User
from app.schemas.nutrition import MealPlanOut, MealPlanRequest
from app.services import ai, meal_planner

router = APIRouter(prefix="/meal-plans", tags=["meal-plans"])


@router.post(
    "",
    response_model=MealPlanOut,
    status_code=201,
    dependencies=[Depends(throttle("mealplan", 10, 86400))],
)
async def generate_plan(
    payload: MealPlanRequest,
    user: User = Depends(require_premium),
    db: Session = Depends(get_db),
):
    start = payload.start_date or date.today()
    days = 1 if payload.kind == "day" else 7
    try:
        data = await meal_planner.generate(
            payload.kind,
            start,
            user.daily_calorie_target,
            user.daily_protein_target_g,
            payload.preferences or "",
            payload.exclusions,
        )
    except ai.AIUnavailable:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Plan generation is unavailable right now.")
    except ValueError:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Couldn't build that plan. Try again.")

    plan = MealPlan(
        user_id=user.id,
        start_date=start,
        end_date=start + timedelta(days=days - 1),
        kind=payload.kind,
        calorie_target=user.daily_calorie_target,
        preferences=payload.preferences,
        days={"days": data.get("days", []), "notes": data.get("notes", "")},
        grocery_list=data.get("grocery_list", {}),
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return MealPlanOut.model_validate(plan)


@router.get("", response_model=List[MealPlanOut])
def list_plans(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(MealPlan).where(MealPlan.user_id == user.id).order_by(MealPlan.start_date.desc()).limit(20)
    ).all()
    return [MealPlanOut.model_validate(r) for r in rows]


@router.get("/current", response_model=MealPlanOut)
def current_plan(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    plan = db.scalar(
        select(MealPlan)
        .where(MealPlan.user_id == user.id, MealPlan.end_date >= date.today())
        .order_by(MealPlan.start_date.asc())
    )
    if not plan:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No active plan. Generate one to get started.")
    return MealPlanOut.model_validate(plan)


@router.delete("/{plan_id}", status_code=204)
def delete_plan(plan_id: UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    plan = db.scalar(select(MealPlan).where(MealPlan.id == plan_id, MealPlan.user_id == user.id))
    if not plan:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That plan no longer exists.")
    db.delete(plan)
    db.commit()
