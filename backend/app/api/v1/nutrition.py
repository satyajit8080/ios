from datetime import date, datetime, timezone
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, throttle
from app.db.session import get_db
from app.models import FavoriteFood, Food, MealLog, User
from app.schemas.nutrition import (
    DaySummary,
    FoodCreate,
    FoodOut,
    MealLogCreate,
    MealLogOut,
    VisionItem,
    VisionResult,
)
from app.services import ai
from app.services.gamification import award_xp

router = APIRouter(tags=["nutrition"])
MAX_IMAGE_BYTES = 8 * 1024 * 1024


@router.get("/foods/search", response_model=List[FoodOut])
def search_foods(
    q: str = Query(min_length=1, max_length=80),
    limit: int = Query(25, ge=1, le=50),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    term = f"%{q.lower()}%"
    rows = db.scalars(
        select(Food)
        .where(
            or_(Food.is_public.is_(True), Food.created_by == user.id),
            or_(func.lower(Food.name).like(term), func.lower(func.coalesce(Food.brand, "")).like(term)),
        )
        .order_by(func.length(Food.name).asc())
        .limit(limit)
    ).all()
    return [FoodOut.model_validate(r) for r in rows]


@router.post("/foods", response_model=FoodOut, status_code=201)
def create_food(payload: FoodCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    food = Food(**payload.model_dump(), is_public=False, created_by=user.id)
    db.add(food)
    db.commit()
    db.refresh(food)
    return FoodOut.model_validate(food)


@router.get("/foods/favorites", response_model=List[FoodOut])
def list_favorites(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(Food).join(FavoriteFood, FavoriteFood.food_id == Food.id).where(FavoriteFood.user_id == user.id)
    ).all()
    return [FoodOut.model_validate(r) for r in rows]


@router.post("/foods/{food_id}/favorite", status_code=204)
def add_favorite(food_id: UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not db.get(Food, food_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That food no longer exists.")
    if not db.scalar(
        select(FavoriteFood).where(FavoriteFood.user_id == user.id, FavoriteFood.food_id == food_id)
    ):
        db.add(FavoriteFood(user_id=user.id, food_id=food_id))
        db.commit()


@router.delete("/foods/{food_id}/favorite", status_code=204)
def remove_favorite(food_id: UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.scalar(
        select(FavoriteFood).where(FavoriteFood.user_id == user.id, FavoriteFood.food_id == food_id)
    )
    if row:
        db.delete(row)
        db.commit()


@router.post("/meals", response_model=MealLogOut, status_code=201)
def log_meal(payload: MealLogCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    entry = MealLog(
        user_id=user.id,
        food_id=payload.food_id,
        name=payload.name,
        meal_type=payload.meal_type,
        quantity_g=payload.quantity_g,
        calories=payload.calories,
        protein_g=payload.protein_g,
        carbs_g=payload.carbs_g,
        fat_g=payload.fat_g,
        source=payload.source,
        image_url=payload.image_url,
        recorded_on=payload.recorded_on or date.today(),
        logged_at=datetime.now(timezone.utc),
    )
    db.add(entry)
    award_xp(db, user, "meal_logged")
    db.commit()
    db.refresh(entry)
    return MealLogOut.model_validate(entry)


@router.get("/meals", response_model=DaySummary)
def day_summary(
    day: date = Query(default_factory=date.today),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    rows = db.scalars(
        select(MealLog)
        .where(MealLog.user_id == user.id, MealLog.recorded_on == day)
        .order_by(MealLog.logged_at.asc())
    ).all()
    calories = sum(r.calories for r in rows)
    return DaySummary(
        recorded_on=day,
        calorie_target=user.daily_calorie_target,
        calories=round(calories, 1),
        protein_g=round(sum(r.protein_g for r in rows), 1),
        carbs_g=round(sum(r.carbs_g for r in rows), 1),
        fat_g=round(sum(r.fat_g for r in rows), 1),
        remaining_calories=round(user.daily_calorie_target - calories, 1),
        meals=[MealLogOut.model_validate(r) for r in rows],
    )


@router.delete("/meals/{meal_id}", status_code=204)
def delete_meal(meal_id: UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    entry = db.scalar(select(MealLog).where(MealLog.id == meal_id, MealLog.user_id == user.id))
    if not entry:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That entry no longer exists.")
    db.delete(entry)
    db.commit()


@router.post(
    "/vision/analyze",
    response_model=VisionResult,
    dependencies=[Depends(throttle("vision", 30, 3600))],
)
async def analyze_photo(
    file: UploadFile = File(...),
    hint: str = Query("", max_length=140),
    user: User = Depends(get_current_user),
):
    if file.content_type not in ("image/jpeg", "image/png", "image/heic", "image/webp"):
        raise HTTPException(status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, "Upload a JPEG, PNG, HEIC or WebP photo.")
    payload = await file.read()
    if len(payload) > MAX_IMAGE_BYTES:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "That photo is larger than 8 MB.")

    mime = "image/jpeg" if file.content_type == "image/heic" else file.content_type
    try:
        data = await ai.analyze_food_image(payload, mime=mime, hint=hint)
    except ai.AIUnavailable:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Photo analysis is unavailable right now.")
    except ValueError:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "Couldn't read that photo. Try a clearer shot.")

    items: List[VisionItem] = []
    for raw in data.get("items", [])[:12]:
        try:
            items.append(
                VisionItem(
                    name=str(raw.get("name", "Food"))[:120],
                    quantity_g=max(float(raw.get("quantity_g", 100)), 0),
                    calories=max(float(raw.get("calories", 0)), 0),
                    protein_g=max(float(raw.get("protein_g", 0)), 0),
                    carbs_g=max(float(raw.get("carbs_g", 0)), 0),
                    fat_g=max(float(raw.get("fat_g", 0)), 0),
                    confidence=min(max(float(raw.get("confidence", 0.5)), 0), 1),
                )
            )
        except (TypeError, ValueError):
            continue

    return VisionResult(
        items=items,
        total_calories=round(sum(i.calories for i in items), 1),
        total_protein_g=round(sum(i.protein_g for i in items), 1),
        total_carbs_g=round(sum(i.carbs_g for i in items), 1),
        total_fat_g=round(sum(i.fat_g for i in items), 1),
        notes=str(data.get("notes", ""))[:500],
    )
