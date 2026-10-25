"""Initial Lango schema."""

import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "users",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("email", sa.String(254), nullable=False, unique=True),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("display_name", sa.String(80), nullable=False),
        sa.Column("native_language", sa.String(20), nullable=False),
        sa.Column("target_language", sa.String(20), nullable=False),
        sa.Column("level", sa.String(4), nullable=False),
        sa.Column("goal", sa.Text(), nullable=False),
        sa.Column("interests", sa.Text(), nullable=False),
        sa.Column("voice", sa.String(30), nullable=False),
        sa.Column("speech_rate", sa.Float(), nullable=False),
        sa.Column("memory_enabled", sa.Boolean(), nullable=False),
        sa.Column("onboarding_completed", sa.Boolean(), nullable=False),
        sa.Column("is_admin", sa.Boolean(), nullable=False),
        sa.Column("memory_epoch", sa.Integer(), nullable=False),
        sa.Column("memory_since", sa.Float(), nullable=False),
        sa.Column("active_connection", sa.String(32)),
        sa.Column("connection_until", sa.Float(), nullable=False),
    )
    op.create_table(
        "invites",
        sa.Column("digest", sa.String(64), primary_key=True),
        sa.Column("max_uses", sa.Integer(), nullable=False),
        sa.Column("uses", sa.Integer(), nullable=False),
        sa.Column("expires_at", sa.Float(), nullable=False),
    )
    op.create_table(
        "refresh_tokens",
        sa.Column("digest", sa.String(64), primary_key=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("family", sa.String(32), nullable=False),
        sa.Column("expires_at", sa.Float(), nullable=False),
        sa.Column("used", sa.Boolean(), nullable=False),
        sa.Column("revoked", sa.Boolean(), nullable=False),
    )
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])
    op.create_index("ix_refresh_tokens_family", "refresh_tokens", ["family"])
    op.create_table(
        "tickets",
        sa.Column("digest", sa.String(64), primary_key=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("expires_at", sa.Float(), nullable=False),
        sa.Column("used", sa.Boolean(), nullable=False),
    )
    op.create_table(
        "sessions",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("title", sa.String(100), nullable=False),
        sa.Column("scenario_id", sa.String(80)),
        sa.Column("engine", sa.String(12), nullable=False),
        sa.Column("started_at", sa.Float(), nullable=False),
        sa.Column("ended_at", sa.Float()),
        sa.Column("duration_seconds", sa.Float(), nullable=False),
        sa.Column("completed_goals", sa.JSON(), nullable=False),
    )
    op.create_index("ix_sessions_user_id", "sessions", ["user_id"])
    op.create_table(
        "turns",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("session_id", sa.String(32), sa.ForeignKey("sessions.id"), nullable=False),
        sa.Column("role", sa.String(12), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("created_at", sa.Float(), nullable=False),
        sa.Column("interrupted", sa.Boolean(), nullable=False),
    )
    op.create_index("ix_turns_session_id", "turns", ["session_id"])
    op.create_table(
        "usage",
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id"), primary_key=True),
        sa.Column("day", sa.String(10), primary_key=True),
        sa.Column("seconds", sa.Float(), nullable=False),
    )
    op.create_table(
        "rate_buckets",
        sa.Column("key", sa.String(128), primary_key=True),
        sa.Column("count", sa.Integer(), nullable=False),
        sa.Column("until", sa.Float(), nullable=False),
    )
    op.create_table(
        "memories",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("epoch", sa.Integer(), nullable=False),
        sa.Column("memory", sa.Text(), nullable=False),
        sa.Column("created_at", sa.Float(), nullable=False),
    )
    op.create_index("ix_memories_user_id", "memories", ["user_id"])
    op.create_table(
        "memory_jobs",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("user_id", sa.String(32), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("epoch", sa.Integer(), nullable=False),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("available_at", sa.Float(), nullable=False),
        sa.Column("lease_until", sa.Float(), nullable=False),
        sa.Column("lease_token", sa.String(32)),
        sa.Column("last_error", sa.String(64)),
    )
    op.create_index("ix_memory_jobs_user_id", "memory_jobs", ["user_id"])
    op.create_index("ix_memory_jobs_status", "memory_jobs", ["status"])


def downgrade():
    for table in (
        "memory_jobs",
        "memories",
        "rate_buckets",
        "usage",
        "turns",
        "sessions",
        "tickets",
        "refresh_tokens",
        "invites",
        "users",
    ):
        op.drop_table(table)
