"""APScheduler process: reminder cycles, subscription reconciliation, housekeeping."""
import logging
from datetime import datetime, timezone

from apscheduler.schedulers.blocking import BlockingScheduler
from sqlalchemy import select

from app.db.session import SessionLocal
from app.models import Subscription, User
from app.worker.reminders import purge_expired, run_cycle

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("awlc.worker")


def reconcile_subscriptions() -> int:
    db = SessionLocal()
    changed = 0
    try:
        now = datetime.now(timezone.utc)
        expired = db.scalars(
            select(Subscription).where(Subscription.status == "active", Subscription.expires_at < now)
        ).all()
        for sub in expired:
            sub.status = "expired"
            user = db.get(User, sub.user_id)
            if user:
                user.is_premium = False
                db.add(user)
            db.add(sub)
            changed += 1
        db.commit()
    finally:
        db.close()
    logger.info("reconciled %s expired subscriptions", changed)
    return changed


def main() -> None:
    scheduler = BlockingScheduler(timezone="UTC")
    scheduler.add_job(run_cycle, "interval", minutes=15, id="reminders", max_instances=1, coalesce=True)
    scheduler.add_job(reconcile_subscriptions, "interval", hours=1, id="subscriptions", max_instances=1)
    scheduler.add_job(purge_expired, "cron", hour=3, minute=30, id="purge")
    logger.info("scheduler started")
    scheduler.start()


if __name__ == "__main__":
    main()
