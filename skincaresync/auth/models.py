"""ORM models for the authentication schema.

These mirror `migrations/007_auth.sql`, which is the source of truth. Columns
that Postgres computes -- `email_normalized`, `created_at`, `updated_at` -- are
mapped read-only so application code cannot fight the database over them.
"""

from __future__ import annotations

import enum
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Computed,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import INET, JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class UserRole(str, enum.Enum):
    USER = "user"
    ADMIN = "admin"


class UserStatus(str, enum.Enum):
    ACTIVE = "active"
    DEACTIVATED = "deactivated"
    DELETED = "deleted"


class TokenPurpose(str, enum.Enum):
    EMAIL_VERIFICATION = "email_verification"
    PASSWORD_RESET = "password_reset"


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    user_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    email: Mapped[str] = mapped_column(Text, nullable=False)
    # Computed by Postgres and never assigned from Python. Declaring it as
    # Computed makes SQLAlchemy read it back rather than try to write it.
    email_normalized: Mapped[str] = mapped_column(
        Text, Computed("lower(btrim(email))", persisted=True)
    )
    # NULL when the account signs in only through a linked provider. Never a
    # placeholder -- a placeholder in a password column eventually gets compared.
    password_hash: Mapped[str | None] = mapped_column(Text)
    display_name: Mapped[str | None] = mapped_column(Text)
    role: Mapped[str] = mapped_column(Text, nullable=False, default=UserRole.USER.value)
    status: Mapped[str] = mapped_column(Text, nullable=False, default=UserStatus.ACTIVE.value)
    email_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    credentials_changed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    failed_login_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    sessions: Mapped[list[UserSession]] = relationship(
        back_populates="user", cascade="all, delete-orphan", lazy="selectin"
    )
    tokens: Mapped[list[AuthToken]] = relationship(
        back_populates="user", cascade="all, delete-orphan", lazy="selectin"
    )
    identities: Mapped[list[UserIdentity]] = relationship(
        back_populates="user", cascade="all, delete-orphan", lazy="selectin"
    )

    __table_args__ = (
        CheckConstraint("btrim(email) <> ''", name="users_email_not_blank"),
        CheckConstraint(
            "(status = 'deleted') = (deleted_at IS NOT NULL)", name="users_deleted_consistent"
        ),
        Index("users_email_normalized_key", "email_normalized", unique=True),
    )

    @property
    def is_admin(self) -> bool:
        return self.role == UserRole.ADMIN.value

    @property
    def is_active(self) -> bool:
        return self.status == UserStatus.ACTIVE.value

    @property
    def is_email_verified(self) -> bool:
        return self.email_verified_at is not None

    @property
    def has_password(self) -> bool:
        return bool(self.password_hash)

    def is_locked(self, now: datetime | None = None) -> bool:
        if self.locked_until is None:
            return False
        return self.locked_until > (now or utcnow())


class UserSession(Base):
    __tablename__ = "user_sessions"

    session_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False
    )
    # SHA-256 of the cookie value. The token itself is never persisted.
    token_hash: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)

    user_agent: Mapped[str | None] = mapped_column(Text)
    ip_address: Mapped[str | None] = mapped_column(INET)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_reason: Mapped[str | None] = mapped_column(Text)

    user: Mapped[User] = relationship(back_populates="sessions")

    __table_args__ = (Index("user_sessions_token_hash_key", "token_hash", unique=True),)

    def is_usable(self, idle_max_age_seconds: int, now: datetime | None = None) -> bool:
        now = now or utcnow()
        if self.revoked_at is not None or self.expires_at <= now:
            return False
        idle = (now - self.last_seen_at).total_seconds()
        return idle < idle_max_age_seconds


class AuthToken(Base):
    __tablename__ = "auth_tokens"

    auth_token_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False
    )
    purpose: Mapped[str] = mapped_column(Text, nullable=False)
    token_hash: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped[User] = relationship(back_populates="tokens")

    __table_args__ = (Index("auth_tokens_token_hash_key", "token_hash", unique=True),)

    def is_redeemable(self, now: datetime | None = None) -> bool:
        now = now or utcnow()
        return self.consumed_at is None and self.expires_at > now


class AuthEvent(Base):
    __tablename__ = "auth_events"

    auth_event_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.user_id", ondelete="SET NULL")
    )
    event_type: Mapped[str] = mapped_column(Text, nullable=False)
    detail: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    ip_address: Mapped[str | None] = mapped_column(INET)
    user_agent: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


class OAuthProviderKey(str, enum.Enum):
    GOOGLE = "google"
    APPLE = "apple"


class UserIdentity(Base):
    """A provider account linked to a local user."""

    __tablename__ = "user_identities"

    identity_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("users.user_id", ondelete="CASCADE"), nullable=False
    )
    provider: Mapped[str] = mapped_column(Text, nullable=False)

    # The provider's stable id for the account. This is the identity, not the
    # email: an email can be reassigned by whoever controls the domain.
    subject: Mapped[str] = mapped_column(Text, nullable=False)

    email: Mapped[str | None] = mapped_column(Text)
    email_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped[User] = relationship(back_populates="identities")

    __table_args__ = (
        Index("user_identities_provider_subject_key", "provider", "subject", unique=True),
        Index("user_identities_user_provider_key", "user_id", "provider", unique=True),
    )


class OAuthFlow(Base):
    """Server-side state for one in-progress social sign-in."""

    __tablename__ = "oauth_flows"

    oauth_flow_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    flow_key_hash: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    provider: Mapped[str] = mapped_column(Text, nullable=False)

    state: Mapped[str] = mapped_column(Text, nullable=False)
    code_verifier: Mapped[str] = mapped_column(Text, nullable=False)
    nonce: Mapped[str] = mapped_column(Text, nullable=False)

    redirect_to: Mapped[str] = mapped_column(Text, nullable=False, default="/")
    link_user_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("users.user_id", ondelete="CASCADE")
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    __table_args__ = (Index("oauth_flows_key_hash_key", "flow_key_hash", unique=True),)

    def is_usable(self, now: datetime | None = None) -> bool:
        now = now or utcnow()
        return self.consumed_at is None and self.expires_at > now
