"""initial schema

Revision ID: 0001
Revises:
Create Date: 2025-01-01

This migration is a frozen snapshot of the schema as it stood at this revision.

It deliberately does NOT call `Base.metadata.create_all()` across the whole
metadata. Doing so makes the migration track whatever the models happen to look
like today, so it creates tables belonging to *later* revisions and every
subsequent migration then fails with "relation already exists". Freezing the
table list here is what makes the chain replayable from an empty database.

Columns added to these tables by later revisions are dropped back out at the end
of the upgrade, so 0001 leaves the database in exactly the shape 0002 expects.
"""
from typing import Sequence, Union

from alembic import op

from app.models import Base

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# The 23 tables that existed at revision 0001. Do not add to this list:
# new tables belong in a new migration.
TABLES_AT_0001 = (
    "users",
    "devices",
    "refresh_tokens",
    "password_reset_tokens",
    "weight_entries",
    "step_entries",
    "water_entries",
    "foods",
    "favorite_foods",
    "meal_logs",
    "meal_plans",
    "habits",
    "habit_logs",
    "badges",
    "user_badges",
    "challenges",
    "challenge_participants",
    "chat_messages",
    "user_memories",
    "subscriptions",
    "notifications",
    "reminder_settings",
    "analytics_events",
)

# Columns the models carry now but which arrived after 0001.
COLUMNS_ADDED_LATER = {
    "challenge_participants": ("current_streak", "longest_streak", "last_qualified_on"),
}


def upgrade() -> None:
    bind = op.get_bind()
    op.execute('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"')
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    Base.metadata.create_all(
        bind=bind,
        tables=[Base.metadata.tables[name] for name in TABLES_AT_0001],
        checkfirst=True,
    )

    # create_all builds tables from today's models, so strip the columns that
    # later revisions are responsible for adding.
    for table, columns in COLUMNS_ADDED_LATER.items():
        for column in columns:
            op.execute(f"ALTER TABLE {table} DROP COLUMN IF EXISTS {column}")

    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_meal_logs_user_day ON meal_logs (user_id, recorded_on)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_water_entries_user_day ON water_entries (user_id, recorded_on)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_chat_messages_user_created ON chat_messages (user_id, created_at DESC)"
    )
    op.execute("CREATE INDEX IF NOT EXISTS ix_foods_name_lower ON foods (lower(name))")


def downgrade() -> None:
    Base.metadata.drop_all(
        bind=op.get_bind(),
        tables=[Base.metadata.tables[name] for name in TABLES_AT_0001],
    )
