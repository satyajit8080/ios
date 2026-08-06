from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.deps import get_current_admin
from app.db.session import get_db
from app.models import (
    AnalyticsEvent,
    ChatMessage,
    MealLog,
    StepEntry,
    Subscription,
    User,
    WeightEntry,
)
from app.services.subscriptions import PRICES

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(get_current_admin)])


@router.get("/overview")
def overview(db: Session = Depends(get_db)) -> Dict[str, Any]:
    now = datetime.now(timezone.utc)
    day_ago = now - timedelta(days=1)
    week_ago = now - timedelta(days=7)
    month_ago = now - timedelta(days=30)

    total_users = db.scalar(select(func.count(User.id))) or 0
    new_7d = db.scalar(select(func.count(User.id)).where(User.created_at >= week_ago)) or 0
    dau = db.scalar(select(func.count(User.id)).where(User.last_active_at >= day_ago)) or 0
    wau = db.scalar(select(func.count(User.id)).where(User.last_active_at >= week_ago)) or 0
    mau = db.scalar(select(func.count(User.id)).where(User.last_active_at >= month_ago)) or 0
    premium = db.scalar(select(func.count(User.id)).where(User.is_premium.is_(True))) or 0

    active_subs = db.scalars(
        select(Subscription).where(Subscription.status == "active", Subscription.expires_at > now)
    ).all()
    mrr = 0.0
    for sub in active_subs:
        price = PRICES.get(sub.product_id, 0.0)
        mrr += price if "monthly" in sub.product_id else price / 12

    revenue_30d = (
        db.scalar(
            select(func.sum(Subscription.price_usd)).where(Subscription.purchased_at >= month_ago)
        )
        or 0.0
    )

    return {
        "users": {
            "total": total_users,
            "new_7d": new_7d,
            "dau": dau,
            "wau": wau,
            "mau": mau,
            "stickiness_pct": round(dau / mau * 100, 1) if mau else 0.0,
        },
        "revenue": {
            "mrr_usd": round(mrr, 2),
            "arr_usd": round(mrr * 12, 2),
            "revenue_30d_usd": round(float(revenue_30d), 2),
            "arpu_usd": round(mrr / total_users, 2) if total_users else 0.0,
        },
        "subscriptions": {
            "active": len(active_subs),
            "premium_users": premium,
            "conversion_pct": round(premium / total_users * 100, 1) if total_users else 0.0,
            "monthly": sum(1 for s in active_subs if "monthly" in s.product_id),
            "annual": sum(1 for s in active_subs if "annual" in s.product_id),
        },
        "engagement": {
            "weigh_ins_7d": db.scalar(
                select(func.count(WeightEntry.id)).where(WeightEntry.created_at >= week_ago)
            ) or 0,
            "meals_logged_7d": db.scalar(
                select(func.count(MealLog.id)).where(MealLog.created_at >= week_ago)
            ) or 0,
            "coach_messages_7d": db.scalar(
                select(func.count(ChatMessage.id)).where(
                    ChatMessage.created_at >= week_ago, ChatMessage.role == "user"
                )
            ) or 0,
            "steps_synced_7d": db.scalar(
                select(func.count(StepEntry.id)).where(StepEntry.created_at >= week_ago)
            ) or 0,
        },
    }


@router.get("/signups")
def signups(days: int = Query(30, ge=7, le=180), db: Session = Depends(get_db)) -> List[Dict[str, Any]]:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = db.execute(
        select(func.date(User.created_at), func.count(User.id))
        .where(User.created_at >= since)
        .group_by(func.date(User.created_at))
        .order_by(func.date(User.created_at))
    ).all()
    return [{"date": str(r[0]), "count": r[1]} for r in rows]


@router.get("/revenue")
def revenue(days: int = Query(90, ge=7, le=365), db: Session = Depends(get_db)) -> List[Dict[str, Any]]:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = db.execute(
        select(func.date(Subscription.purchased_at), func.sum(Subscription.price_usd), func.count(Subscription.id))
        .where(Subscription.purchased_at >= since)
        .group_by(func.date(Subscription.purchased_at))
        .order_by(func.date(Subscription.purchased_at))
    ).all()
    return [{"date": str(r[0]), "revenue_usd": round(float(r[1] or 0), 2), "count": r[2]} for r in rows]


@router.get("/users")
def list_users(
    q: str = Query("", max_length=120),
    premium_only: bool = False,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    stmt = select(User)
    if q:
        stmt = stmt.where(func.lower(User.email).like(f"%{q.lower()}%"))
    if premium_only:
        stmt = stmt.where(User.is_premium.is_(True))
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    rows = db.scalars(stmt.order_by(User.created_at.desc()).limit(limit).offset(offset)).all()
    return {
        "total": total,
        "items": [
            {
                "id": str(u.id),
                "email": u.email,
                "full_name": u.full_name,
                "is_premium": u.is_premium,
                "is_active": u.is_active,
                "is_admin": u.is_admin,
                "xp": u.xp,
                "created_at": u.created_at.isoformat(),
                "last_active_at": u.last_active_at.isoformat() if u.last_active_at else None,
            }
            for u in rows
        ],
    }


@router.post("/users/{user_id}/toggle-active", status_code=204)
def toggle_active(user_id: UUID, db: Session = Depends(get_db)):
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That user no longer exists.")
    user.is_active = not user.is_active
    db.add(user)
    db.commit()


@router.get("/subscriptions")
def list_subscriptions(limit: int = Query(100, ge=1, le=500), db: Session = Depends(get_db)):
    rows = db.execute(
        select(Subscription, User.email)
        .join(User, User.id == Subscription.user_id)
        .order_by(Subscription.created_at.desc())
        .limit(limit)
    ).all()
    return [
        {
            "id": str(s.id),
            "email": email,
            "product_id": s.product_id,
            "status": s.status,
            "price_usd": s.price_usd,
            "purchased_at": s.purchased_at.isoformat(),
            "expires_at": s.expires_at.isoformat() if s.expires_at else None,
            "auto_renew": s.auto_renew,
            "environment": s.environment,
        }
        for s, email in rows
    ]


@router.get("/events")
def event_counts(days: int = Query(7, ge=1, le=90), db: Session = Depends(get_db)):
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = db.execute(
        select(AnalyticsEvent.name, func.count(AnalyticsEvent.id))
        .where(AnalyticsEvent.created_at >= since)
        .group_by(AnalyticsEvent.name)
        .order_by(func.count(AnalyticsEvent.id).desc())
    ).all()
    return [{"name": r[0], "count": r[1]} for r in rows]


@router.get("/retention")
def retention(db: Session = Depends(get_db)):
    today = date.today()
    cohorts = []
    for week in range(6):
        start = today - timedelta(days=(week + 1) * 7)
        end = today - timedelta(days=week * 7)
        signed = db.scalars(select(User).where(User.created_at >= start, User.created_at < end)).all()
        retained = sum(
            1 for u in signed if u.last_active_at and (u.last_active_at.date() - u.created_at.date()).days >= 7
        )
        cohorts.append(
            {
                "cohort": start.isoformat(),
                "signups": len(signed),
                "retained_d7": retained,
                "rate_pct": round(retained / len(signed) * 100, 1) if signed else 0.0,
            }
        )
    return list(reversed(cohorts))
