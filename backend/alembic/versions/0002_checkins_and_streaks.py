"""Daily check-ins and challenge streak tracking

Revision ID: 0002
Revises: 0001
Create Date: 2026-08-06

Adds the daily_checkins table behind the AI coach check-in, and two columns on
challenge_participants so a challenge can track a run of qualifying days rather
than only a cumulative total.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "daily_checkins",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("recorded_on", sa.Date(), nullable=False),
        sa.Column("answers", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb")),
        sa.Column("metrics", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'{}'::jsonb")),
        sa.Column("mood", sa.Integer(), nullable=True),
        sa.Column("energy", sa.Integer(), nullable=True),
        sa.Column("adherence", sa.Integer(), nullable=True),
        sa.Column("summary", sa.Text(), nullable=True),
        sa.Column("recommendations", postgresql.JSONB(astext_type=sa.Text()), server_default=sa.text("'[]'::jsonb")),
        sa.Column("focus", sa.String(length=160), nullable=True),
        sa.Column("provider", sa.String(length=24), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("user_id", "recorded_on", name="uq_checkin_user_day"),
    )
    op.create_index("ix_daily_checkins_user_id", "daily_checkins", ["user_id"])
    op.create_index("ix_daily_checkins_recorded_on", "daily_checkins", ["recorded_on"])
    op.create_index(
        "ix_daily_checkins_user_day_desc", "daily_checkins", ["user_id", sa.text("recorded_on DESC")]
    )

    op.add_column(
        "challenge_participants",
        sa.Column("current_streak", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "challenge_participants",
        sa.Column("longest_streak", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "challenge_participants",
        sa.Column("last_qualified_on", sa.Date(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("challenge_participants", "last_qualified_on")
    op.drop_column("challenge_participants", "longest_streak")
    op.drop_column("challenge_participants", "current_streak")

    op.drop_index("ix_daily_checkins_user_day_desc", table_name="daily_checkins")
    op.drop_index("ix_daily_checkins_recorded_on", table_name="daily_checkins")
    op.drop_index("ix_daily_checkins_user_id", table_name="daily_checkins")
    op.drop_table("daily_checkins")
