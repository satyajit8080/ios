from datetime import datetime, time, timezone
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import ensure_reminder_settings, get_current_user
from app.db.session import get_db
from app.models import Device, Notification, User
from app.schemas.misc import DeviceRegister, NotificationOut, ReminderSettingsIn, ReminderSettingsOut

router = APIRouter(prefix="/notifications", tags=["notifications"])


def _parse_time(value: str) -> time:
    hours, _, minutes = value.partition(":")
    return time(int(hours), int(minutes or 0))


@router.post("/devices", status_code=204)
def register_device(payload: DeviceRegister, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    device = db.scalar(select(Device).where(Device.token == payload.token))
    if device is None:
        device = Device(token=payload.token)
    device.user_id = user.id
    device.platform = payload.platform
    device.app_version = payload.app_version
    db.add(device)
    db.commit()


@router.delete("/devices/{token}", status_code=204)
def unregister_device(token: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    db.query(Device).filter(Device.token == token, Device.user_id == user.id).delete()
    db.commit()


@router.get("", response_model=List[NotificationOut])
def list_notifications(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(Notification)
        .where(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc())
        .limit(50)
    ).all()
    return [NotificationOut.model_validate(r) for r in rows]


@router.post("/{notification_id}/read", status_code=204)
def mark_read(notification_id: UUID, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.scalar(
        select(Notification).where(Notification.id == notification_id, Notification.user_id == user.id)
    )
    if not row:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "That notification no longer exists.")
    row.read_at = datetime.now(timezone.utc)
    db.add(row)
    db.commit()


@router.get("/settings", response_model=ReminderSettingsOut)
def get_settings(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = ensure_reminder_settings(db, user)
    return _to_out(row)


@router.patch("/settings", response_model=ReminderSettingsOut)
def update_settings(
    payload: ReminderSettingsIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)
):
    row = ensure_reminder_settings(db, user)
    data = payload.model_dump(exclude_unset=True)
    for field, value in data.items():
        if field in ("day_start", "day_end", "weigh_in_time") and value is not None:
            setattr(row, field, _parse_time(value))
        elif value is not None:
            setattr(row, field, value)
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_out(row)


def _to_out(row) -> ReminderSettingsOut:
    return ReminderSettingsOut(
        water_enabled=row.water_enabled,
        water_interval_minutes=row.water_interval_minutes,
        day_start=row.day_start.strftime("%H:%M"),
        day_end=row.day_end.strftime("%H:%M"),
        weigh_in_enabled=row.weigh_in_enabled,
        weigh_in_time=row.weigh_in_time.strftime("%H:%M"),
        meal_log_enabled=row.meal_log_enabled,
        step_nudge_enabled=row.step_nudge_enabled,
        coach_checkin_enabled=row.coach_checkin_enabled,
    )
