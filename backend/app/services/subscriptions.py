"""App Store subscription state handling (StoreKit 2 client verification + server notifications)."""
import base64
import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models import Subscription, User

logger = logging.getLogger(__name__)

PRICES = {
    "com.awlc.coach.premium.monthly": 9.99,
    "com.awlc.coach.premium.annual": 59.99,
}


def ms_to_dt(value: Optional[int]) -> Optional[datetime]:
    if not value:
        return None
    return datetime.fromtimestamp(value / 1000, tz=timezone.utc)


def decode_jws_payload(jws: str) -> Dict[str, Any]:
    """Decode the payload segment of an App Store signed transaction."""
    parts = jws.split(".")
    if len(parts) != 3:
        raise ValueError("malformed JWS")
    payload = parts[1] + "=" * (-len(parts[1]) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))


def apply_transaction(db: Session, user: User, tx: Dict[str, Any]) -> Subscription:
    product_id = tx["product_id"]
    if product_id not in settings.PREMIUM_PRODUCTS:
        raise ValueError("unknown product")

    expires_at = tx.get("expires_at")
    now = datetime.now(timezone.utc)
    active = bool(expires_at and expires_at > now) and tx.get("status", "active") == "active"

    sub = db.scalar(
        select(Subscription).where(
            Subscription.original_transaction_id == tx["original_transaction_id"]
        )
    )
    if sub is None:
        sub = Subscription(
            user_id=user.id,
            original_transaction_id=tx["original_transaction_id"],
        )
        db.add(sub)

    sub.user_id = user.id
    sub.product_id = product_id
    sub.transaction_id = tx["transaction_id"]
    sub.environment = tx.get("environment", "Production")
    sub.status = tx.get("status", "active" if active else "expired")
    sub.purchased_at = tx["purchased_at"]
    sub.expires_at = expires_at
    sub.auto_renew = tx.get("auto_renew", True)
    sub.price_usd = PRICES.get(product_id, 0.0)
    sub.raw = tx.get("raw", {})

    user.is_premium = active
    user.premium_expires_at = expires_at
    db.add(user)
    db.commit()
    db.refresh(sub)
    return sub


def refresh_user_premium(db: Session, user: User) -> bool:
    sub = db.scalar(
        select(Subscription)
        .where(Subscription.user_id == user.id)
        .order_by(Subscription.expires_at.desc().nullslast())
    )
    active = bool(
        sub and sub.expires_at and sub.expires_at > datetime.now(timezone.utc) and sub.status in ("active", "grace")
    )
    if user.is_premium != active:
        user.is_premium = active
        user.premium_expires_at = sub.expires_at if sub else None
        db.add(user)
        db.commit()
    return active
