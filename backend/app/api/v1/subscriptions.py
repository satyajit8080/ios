import logging
from datetime import datetime, timezone
from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user
from app.db.session import get_db
from app.models import Subscription, User
from app.schemas.misc import SubscriptionStatus, VerifyPurchaseRequest
from app.services import subscriptions as svc

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])


@router.post("/verify", response_model=SubscriptionStatus)
def verify(payload: VerifyPurchaseRequest, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    tx: Dict[str, Any] = {
        "product_id": payload.product_id,
        "original_transaction_id": payload.original_transaction_id,
        "transaction_id": payload.transaction_id,
        "environment": payload.environment,
        "purchased_at": svc.ms_to_dt(payload.purchase_date_ms) or datetime.now(timezone.utc),
        "expires_at": svc.ms_to_dt(payload.expires_date_ms),
        "auto_renew": True,
        "status": "active",
        "raw": payload.model_dump(),
    }
    if payload.signed_transaction:
        try:
            decoded = svc.decode_jws_payload(payload.signed_transaction)
            tx["product_id"] = decoded.get("productId", tx["product_id"])
            tx["original_transaction_id"] = decoded.get("originalTransactionId", tx["original_transaction_id"])
            tx["transaction_id"] = decoded.get("transactionId", tx["transaction_id"])
            tx["purchased_at"] = svc.ms_to_dt(decoded.get("purchaseDate")) or tx["purchased_at"]
            tx["expires_at"] = svc.ms_to_dt(decoded.get("expiresDate")) or tx["expires_at"]
            tx["environment"] = decoded.get("environment", tx["environment"])
            tx["raw"] = decoded
        except Exception as exc:
            logger.warning("could not decode signed transaction: %s", exc)

    try:
        sub = svc.apply_transaction(db, user, tx)
    except ValueError:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "That product isn't recognised.")

    return SubscriptionStatus(
        is_premium=user.is_premium,
        product_id=sub.product_id,
        expires_at=sub.expires_at,
        auto_renew=sub.auto_renew,
        status=sub.status,
    )


@router.get("/status", response_model=SubscriptionStatus)
def status_endpoint(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    active = svc.refresh_user_premium(db, user)
    sub = db.scalar(
        select(Subscription)
        .where(Subscription.user_id == user.id)
        .order_by(Subscription.expires_at.desc().nullslast())
    )
    return SubscriptionStatus(
        is_premium=active,
        product_id=sub.product_id if sub else None,
        expires_at=sub.expires_at if sub else None,
        auto_renew=sub.auto_renew if sub else False,
        status=sub.status if sub else "none",
    )


@router.post("/apple/notifications", status_code=200)
async def app_store_notifications(request: Request, db: Session = Depends(get_db)):
    """App Store Server Notifications V2 endpoint."""
    body = await request.json()
    signed_payload = body.get("signedPayload")
    if not signed_payload:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Missing signedPayload.")

    try:
        payload = svc.decode_jws_payload(signed_payload)
        data = payload.get("data", {})
        tx_info = svc.decode_jws_payload(data["signedTransactionInfo"])
        renewal = svc.decode_jws_payload(data["signedRenewalInfo"]) if data.get("signedRenewalInfo") else {}
    except Exception:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Malformed notification.")

    original_id = tx_info.get("originalTransactionId")
    sub = db.scalar(select(Subscription).where(Subscription.original_transaction_id == original_id))
    if not sub:
        logger.info("notification for unknown transaction %s", original_id)
        return {"received": True}

    user = db.get(User, sub.user_id)
    if not user:
        return {"received": True}

    notification_type = payload.get("notificationType", "")
    subtype = payload.get("subtype", "")
    status_map = {
        "EXPIRED": "expired",
        "REFUND": "refunded",
        "REVOKE": "refunded",
        "GRACE_PERIOD_EXPIRED": "expired",
        "DID_FAIL_TO_RENEW": "grace" if subtype == "GRACE_PERIOD" else "expired",
    }
    tx = {
        "product_id": tx_info.get("productId", sub.product_id),
        "original_transaction_id": original_id,
        "transaction_id": tx_info.get("transactionId", sub.transaction_id),
        "environment": tx_info.get("environment", sub.environment),
        "purchased_at": svc.ms_to_dt(tx_info.get("purchaseDate")) or sub.purchased_at,
        "expires_at": svc.ms_to_dt(tx_info.get("expiresDate")),
        "auto_renew": bool(renewal.get("autoRenewStatus", 1)),
        "status": status_map.get(notification_type, "active"),
        "raw": {"notificationType": notification_type, "subtype": subtype, "transaction": tx_info},
    }
    svc.apply_transaction(db, user, tx)
    return {"received": True}
