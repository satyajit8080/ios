from fastapi import APIRouter

from app.api.v1 import (
    admin,
    analytics,
    auth,
    challenges,
    checkin,
    coach,
    dashboard,
    habits,
    meal_plans,
    notifications,
    nutrition,
    steps,
    subscriptions,
    users,
    water,
    weight,
)

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(dashboard.router)
api_router.include_router(weight.router)
api_router.include_router(steps.router)
api_router.include_router(water.router)
api_router.include_router(nutrition.router)
api_router.include_router(meal_plans.router)
api_router.include_router(coach.router)
api_router.include_router(checkin.router)
api_router.include_router(habits.router)
api_router.include_router(challenges.router)
api_router.include_router(subscriptions.router)
api_router.include_router(notifications.router)
api_router.include_router(analytics.router)
api_router.include_router(admin.router)
