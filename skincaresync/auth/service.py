"""Authentication business logic.

Everything that decides whether a request is allowed lives here, so the HTTP
layer stays a thin translation to status codes and the rules can be tested
without a client.

Two principles run through the module:

*Do not leak which addresses have accounts.* Registration, sign-in, verification
resend and password reset all return the same response and take roughly the same
time whether or not the address exists. Sign-in for an unknown address still
burns an Argon2 verification, because a fast "no such user" is an oracle no
amount of careful wording closes.

*Revoke by clock, not by sweep.* `users.credentials_changed_at` is bumped on any
sensitive change. Sessions and tokens issued before that instant are refused on
sight, so a password change cannot leave a live session behind because a delete
missed a row. Rows are deleted as well, but correctness does not depend on it.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import Settings, get_settings
from ..emailing import get_sender
from ..emailing.templates import (
    password_changed_email,
    password_reset_email,
    verification_email,
)
from .models import (
    AuthEvent,
    AuthToken,
    TokenPurpose,
    User,
    UserRole,
    UserSession,
    UserStatus,
    utcnow,
)
from .security import (
    dummy_verify,
    generate_token,
    hash_password,
    hash_token,
    needs_rehash,
    verify_password,
)

logger = logging.getLogger(__name__)

# After this many consecutive failures the account is locked for a short period.
# This is per-account and complements the per-address rate limit, which alone
# cannot stop a distributed guessing attack on one account.
MAX_FAILED_LOGINS = 10
ACCOUNT_LOCK_DURATION = timedelta(minutes=15)


class AuthError(Exception):
    """A failure the caller should surface. `code` is a stable machine token."""

    def __init__(self, code: str, message: str, status_code: int = 400):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code


# The single message used for every sign-in failure. One string, one code, so a
# caller cannot tell "no such account" from "wrong password" from "locked".
INVALID_CREDENTIALS = AuthError(
    "invalid_credentials", "Email or password is incorrect.", status_code=401
)


@dataclass(frozen=True)
class RequestContext:
    """Client metadata attached to audit events. Never used for authorization."""

    ip_address: str | None = None
    user_agent: str | None = None

    @property
    def truncated_user_agent(self) -> str | None:
        return self.user_agent[:400] if self.user_agent else None


@dataclass
class IssuedSession:
    session: UserSession
    token: str  # returned once, to be put in the cookie; never persisted


def normalize_email(email: str) -> str:
    """Match the `email_normalized` generated column exactly."""
    return email.strip().lower()


def record_event(
    db: Session,
    event_type: str,
    *,
    user_id: int | None = None,
    context: RequestContext | None = None,
    detail: dict | None = None,
) -> None:
    """Append a security audit event.

    `detail` is caller-supplied and must never contain a token, hash, password
    or reset link. Callers pass classifications ("reason": "expired"), not
    secrets.
    """
    db.add(
        AuthEvent(
            user_id=user_id,
            event_type=event_type,
            detail=detail or {},
            ip_address=context.ip_address if context else None,
            user_agent=context.truncated_user_agent if context else None,
        )
    )


def get_user_by_email(db: Session, email: str) -> User | None:
    return db.scalar(select(User).where(User.email_normalized == normalize_email(email)))


def get_user(db: Session, user_id: int) -> User | None:
    return db.get(User, user_id)


# ---------------------------------------------------------------------------
# Tokens
# ---------------------------------------------------------------------------


def issue_token(
    db: Session,
    user: User,
    purpose: TokenPurpose,
    ttl_seconds: int,
) -> str:
    """Mint a single-use token, invalidating any outstanding one of the same kind.

    Superseding earlier tokens is what makes "resend" safe: a user who clicks
    resend three times ends up with exactly one working link, and an older link
    that leaked from a mail archive is already dead.
    """
    db.execute(
        update(AuthToken)
        .where(
            AuthToken.user_id == user.user_id,
            AuthToken.purpose == purpose.value,
            AuthToken.consumed_at.is_(None),
        )
        .values(consumed_at=func.now())
    )

    token = generate_token()
    db.add(
        AuthToken(
            user_id=user.user_id,
            purpose=purpose.value,
            token_hash=hash_token(token),
            expires_at=utcnow() + timedelta(seconds=ttl_seconds),
        )
    )
    db.flush()
    return token


def consume_token(db: Session, token: str, purpose: TokenPurpose) -> AuthToken:
    """Redeem a token, or raise. Marks it used in the same transaction.

    The row is located by hash, so an invalid token is indistinguishable from a
    token for another purpose: both simply miss.
    """
    row = db.scalar(
        select(AuthToken)
        .where(AuthToken.token_hash == hash_token(token), AuthToken.purpose == purpose.value)
        .with_for_update()
    )
    if row is None:
        raise AuthError("invalid_token", "This link is invalid or has already been used.")
    if row.consumed_at is not None:
        raise AuthError("invalid_token", "This link is invalid or has already been used.")
    if row.expires_at <= utcnow():
        raise AuthError("expired_token", "This link has expired. Request a new one.")

    user = db.get(User, row.user_id)
    # A token minted before the last credential change is stale by definition:
    # a completed reset must not leave a second reset link live.
    if user is not None and row.created_at < user.credentials_changed_at:
        raise AuthError("invalid_token", "This link is invalid or has already been used.")

    row.consumed_at = utcnow()
    db.flush()
    return row


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------


def create_session(
    db: Session,
    user: User,
    context: RequestContext,
    settings: Settings | None = None,
) -> IssuedSession:
    settings = settings or get_settings()
    token = generate_token()
    session = UserSession(
        user_id=user.user_id,
        token_hash=hash_token(token),
        user_agent=context.truncated_user_agent,
        ip_address=context.ip_address,
        expires_at=utcnow() + timedelta(seconds=settings.session_absolute_max_age_seconds),
    )
    db.add(session)
    db.flush()
    return IssuedSession(session=session, token=token)


def resolve_session(
    db: Session,
    token: str,
    settings: Settings | None = None,
) -> tuple[User, UserSession] | None:
    """Return the user and session for a cookie value, or None.

    Returns None for every failure mode -- unknown, revoked, expired, idle too
    long, superseded by a credential change, or belonging to an account that is
    no longer active. The caller cannot distinguish them, and should not.
    """
    settings = settings or get_settings()
    session = db.scalar(select(UserSession).where(UserSession.token_hash == hash_token(token)))
    if session is None or not session.is_usable(settings.session_idle_max_age_seconds):
        return None

    user = db.get(User, session.user_id)
    if user is None or not user.is_active:
        return None
    if session.created_at < user.credentials_changed_at:
        return None

    # Sliding idle window. Written at most once a minute so that reading a page
    # does not mean a write on every request.
    now = utcnow()
    if (now - session.last_seen_at).total_seconds() > 60:
        session.last_seen_at = now
        db.flush()
    return user, session


def revoke_session(db: Session, session: UserSession, reason: str) -> None:
    if session.revoked_at is None:
        session.revoked_at = utcnow()
        session.revoked_reason = reason
        db.flush()


def revoke_all_sessions(
    db: Session,
    user: User,
    reason: str,
    *,
    except_session_id: int | None = None,
) -> int:
    """Revoke every live session, optionally sparing the caller's own."""
    stmt = (
        update(UserSession)
        .where(UserSession.user_id == user.user_id, UserSession.revoked_at.is_(None))
        .values(revoked_at=func.now(), revoked_reason=reason)
    )
    if except_session_id is not None:
        stmt = stmt.where(UserSession.session_id != except_session_id)
    result = db.execute(stmt)
    db.flush()
    return result.rowcount or 0


def list_sessions(db: Session, user: User) -> list[UserSession]:
    settings = get_settings()
    rows = db.scalars(
        select(UserSession)
        .where(UserSession.user_id == user.user_id, UserSession.revoked_at.is_(None))
        .order_by(UserSession.last_seen_at.desc())
    ).all()
    return [s for s in rows if s.is_usable(settings.session_idle_max_age_seconds)]


def _invalidate_credentials(db: Session, user: User) -> datetime:
    """Mark every session and token issued before now as stale.

    Returns the exact instant used. Callers that need to spare a session must
    stamp it with this same value: mixing a Python timestamp here with a
    Postgres `now()` there means comparing two clocks, and the surviving session
    can end up microseconds on the wrong side of the cutoff and be rejected.
    """
    changed_at = utcnow()
    user.credentials_changed_at = changed_at
    db.flush()
    return changed_at


# ---------------------------------------------------------------------------
# Registration and verification
# ---------------------------------------------------------------------------


@dataclass
class RegistrationResult:
    # Present only when AUTH_DEV_ECHO_TOKENS is on, which production forbids.
    dev_token: str | None = None


def register(
    db: Session,
    email: str,
    password: str,
    display_name: str | None,
    context: RequestContext,
    settings: Settings | None = None,
) -> RegistrationResult:
    """Create an account and send a verification email.

    An address that already exists produces the same response as a new one. The
    existing owner is emailed instead of the caller learning anything: either
    they really are trying to sign up again and get a useful nudge, or someone
    is probing and the owner finds out.
    """
    settings = settings or get_settings()
    normalized = normalize_email(email)
    existing = db.scalar(select(User).where(User.email_normalized == normalized))

    if existing is not None:
        record_event(
            db, "register.duplicate", user_id=existing.user_id, context=context
        )
        if existing.is_active and not existing.is_email_verified:
            # Genuinely useful: they registered and never confirmed.
            token = issue_token(
                db,
                existing,
                TokenPurpose.EMAIL_VERIFICATION,
                settings.email_verification_ttl_seconds,
            )
            _send_verification(existing, token, settings)
            return RegistrationResult(dev_token=token if settings.dev_echo_tokens else None)
        # Active and verified, or deactivated: say nothing, send nothing new.
        return RegistrationResult()

    user = User(
        email=email.strip(),
        password_hash=hash_password(password),
        display_name=(display_name or "").strip() or None,
        role=UserRole.USER.value,
        status=UserStatus.ACTIVE.value,
    )
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        # Lost a race against a concurrent registration for the same address.
        # Indistinguishable from the duplicate branch above, by design.
        db.rollback()
        return RegistrationResult()

    token = issue_token(
        db, user, TokenPurpose.EMAIL_VERIFICATION, settings.email_verification_ttl_seconds
    )
    record_event(db, "register.success", user_id=user.user_id, context=context)
    _send_verification(user, token, settings)
    return RegistrationResult(dev_token=token if settings.dev_echo_tokens else None)


def _send_verification(user: User, token: str, settings: Settings) -> None:
    url = f"{settings.app_base_url}/verify-email?token={token}"
    get_sender().send(
        verification_email(user.email, url, settings.email_verification_ttl_seconds // 3600)
    )


def resend_verification(
    db: Session,
    email: str,
    context: RequestContext,
    settings: Settings | None = None,
) -> str | None:
    """Re-send a verification link. Silent about whether the address exists."""
    settings = settings or get_settings()
    user = get_user_by_email(db, email)
    if user is None or not user.is_active or user.is_email_verified:
        return None
    token = issue_token(
        db, user, TokenPurpose.EMAIL_VERIFICATION, settings.email_verification_ttl_seconds
    )
    record_event(db, "verification.resent", user_id=user.user_id, context=context)
    _send_verification(user, token, settings)
    return token if settings.dev_echo_tokens else None


def verify_email(db: Session, token: str, context: RequestContext) -> User:
    row = consume_token(db, token, TokenPurpose.EMAIL_VERIFICATION)
    user = db.get(User, row.user_id)
    if user is None or not user.is_active:
        raise AuthError("invalid_token", "This link is invalid or has already been used.")

    if not user.is_email_verified:
        user.email_verified_at = utcnow()
        db.flush()
    record_event(db, "email.verified", user_id=user.user_id, context=context)
    return user


# ---------------------------------------------------------------------------
# Sign-in
# ---------------------------------------------------------------------------


def authenticate(
    db: Session,
    email: str,
    password: str,
    context: RequestContext,
) -> User:
    """Verify credentials or raise `INVALID_CREDENTIALS`.

    Every failure path raises the identical error. The unknown-user path still
    performs an Argon2 verification so it costs the same as a real attempt.
    """
    user = get_user_by_email(db, email)

    if user is None:
        dummy_verify()
        record_event(db, "login.failure", context=context, detail={"reason": "unknown_email"})
        raise INVALID_CREDENTIALS

    if user.is_locked():
        dummy_verify()
        record_event(db, "login.blocked", user_id=user.user_id, context=context,
                     detail={"reason": "locked"})
        raise INVALID_CREDENTIALS

    if not user.is_active:
        dummy_verify()
        record_event(db, "login.blocked", user_id=user.user_id, context=context,
                     detail={"reason": user.status})
        raise INVALID_CREDENTIALS

    if not user.has_password:
        # Provider-only account. Same generic failure as any other, so this does
        # not become an oracle for "which accounts use Google".
        dummy_verify()
        record_event(db, "login.failure", user_id=user.user_id, context=context,
                     detail={"reason": "no_password_set"})
        raise INVALID_CREDENTIALS

    if not verify_password(user.password_hash, password):
        user.failed_login_count += 1
        if user.failed_login_count >= MAX_FAILED_LOGINS:
            user.locked_until = utcnow() + ACCOUNT_LOCK_DURATION
            record_event(db, "login.locked", user_id=user.user_id, context=context)
        record_event(db, "login.failure", user_id=user.user_id, context=context,
                     detail={"reason": "bad_password"})
        db.flush()
        raise INVALID_CREDENTIALS

    # Transparently upgrade a hash whose cost parameters have since been raised.
    if needs_rehash(user.password_hash):
        user.password_hash = hash_password(password)

    user.failed_login_count = 0
    user.locked_until = None
    db.flush()
    record_event(db, "login.success", user_id=user.user_id, context=context)
    return user


# ---------------------------------------------------------------------------
# Password reset and change
# ---------------------------------------------------------------------------


def request_password_reset(
    db: Session,
    email: str,
    context: RequestContext,
    settings: Settings | None = None,
) -> str | None:
    """Send a reset link if the address has an active account. Always silent."""
    settings = settings or get_settings()
    user = get_user_by_email(db, email)
    if user is None or not user.is_active:
        record_event(db, "password_reset.requested_unknown", context=context)
        return None

    token = issue_token(
        db, user, TokenPurpose.PASSWORD_RESET, settings.password_reset_ttl_seconds
    )
    record_event(db, "password_reset.requested", user_id=user.user_id, context=context)
    url = f"{settings.app_base_url}/reset-password?token={token}"
    get_sender().send(
        password_reset_email(user.email, url, settings.password_reset_ttl_seconds // 60)
    )
    return token if settings.dev_echo_tokens else None


def reset_password(
    db: Session,
    token: str,
    new_password: str,
    context: RequestContext,
    settings: Settings | None = None,
) -> User:
    """Complete a reset: set the password and sign every device out.

    Signing out everywhere is the point of a reset. If the account was taken
    over, the attacker's session dies here.
    """
    settings = settings or get_settings()
    row = consume_token(db, token, TokenPurpose.PASSWORD_RESET)
    user = db.get(User, row.user_id)
    if user is None or not user.is_active:
        raise AuthError("invalid_token", "This link is invalid or has already been used.")

    user.password_hash = hash_password(new_password)
    user.failed_login_count = 0
    user.locked_until = None
    # A reset proves control of the mailbox, so it also confirms the address.
    if not user.is_email_verified:
        user.email_verified_at = utcnow()

    _invalidate_credentials(db, user)
    revoked = revoke_all_sessions(db, user, reason="password_reset")
    record_event(db, "password.reset", user_id=user.user_id, context=context,
                 detail={"sessions_revoked": revoked})

    get_sender().send(password_changed_email(user.email, f"{settings.app_base_url}/account/security"))
    return user


def change_password(
    db: Session,
    user: User,
    current_password: str,
    new_password: str,
    context: RequestContext,
    current_session_id: int | None = None,
    settings: Settings | None = None,
) -> int:
    """Change a signed-in user's password. Returns how many sessions were cut.

    The current password is required even though the caller is authenticated, so
    a borrowed unlocked browser cannot be used to take the account over. Other
    sessions are revoked; this one survives so the user is not signed out of the
    page they are standing on.
    """
    settings = settings or get_settings()
    setting_first_password = not user.has_password

    # A provider-only account has no current password to prove. Holding a valid
    # session is the authorisation for setting the first one; requiring a
    # password they do not have would make the feature unreachable.
    if not setting_first_password and not verify_password(user.password_hash, current_password):
        record_event(db, "password.change_failed", user_id=user.user_id, context=context)
        raise AuthError(
            "invalid_credentials", "Your current password is incorrect.", status_code=400
        )

    user.password_hash = hash_password(new_password)
    changed_at = _invalidate_credentials(db, user)

    # credentials_changed_at now post-dates every session, so the surviving one
    # is re-stamped rather than special-cased in resolve_session. It is stamped
    # with the identical instant, not func.now(), so the two cannot disagree.
    revoked = revoke_all_sessions(db, user, reason="password_change",
                                  except_session_id=current_session_id)
    if current_session_id is not None:
        db.execute(
            update(UserSession)
            .where(UserSession.session_id == current_session_id)
            .values(created_at=changed_at)
        )
    db.flush()

    record_event(
        db,
        "password.set" if setting_first_password else "password.changed",
        user_id=user.user_id, context=context,
        detail={"sessions_revoked": revoked},
    )
    get_sender().send(password_changed_email(user.email, f"{settings.app_base_url}/account/security"))
    return revoked


# ---------------------------------------------------------------------------
# Account lifecycle
# ---------------------------------------------------------------------------


def deactivate_account(
    db: Session, user: User, context: RequestContext, reason: str = "self_service"
) -> None:
    """Reversible: sign out everywhere and refuse sign-in until reactivated."""
    user.status = UserStatus.DEACTIVATED.value
    _invalidate_credentials(db, user)
    revoke_all_sessions(db, user, reason="account_deactivated")
    record_event(db, "account.deactivated", user_id=user.user_id, context=context,
                 detail={"reason": reason})


def reactivate_account(db: Session, user: User, context: RequestContext) -> None:
    if user.status != UserStatus.DEACTIVATED.value:
        raise AuthError("invalid_state", "This account is not deactivated.")
    user.status = UserStatus.ACTIVE.value
    db.flush()
    record_event(db, "account.reactivated", user_id=user.user_id, context=context)


def delete_account(db: Session, user: User, context: RequestContext) -> None:
    """Irreversible erasure of personal data, keeping the row for audit integrity.

    A hard DELETE would cascade the audit trail away with it. Instead the
    identifying fields are overwritten and the password hash replaced with an
    unusable value, so nothing can authenticate as this account again. The
    address is scrambled so it no longer collides with the unique index and can
    be registered afresh.
    """
    user_id = user.user_id
    revoke_all_sessions(db, user, reason="account_deleted")
    db.execute(delete(AuthToken).where(AuthToken.user_id == user_id))

    from .oauth.service import revoke_identities_for_deleted_user

    # Without this the linked provider account could sign straight back in and
    # land on the deleted shell, since identities are keyed on `sub`, not email.
    revoke_identities_for_deleted_user(db, user_id)

    now = utcnow()
    user.email = f"deleted+{user_id}@deleted.invalid"
    user.display_name = None
    # NULL, not a sentinel: nothing can authenticate against a missing hash.
    user.password_hash = None
    user.status = UserStatus.DELETED.value
    user.deleted_at = now
    user.email_verified_at = None
    user.credentials_changed_at = now
    db.flush()

    record_event(db, "account.deleted", user_id=user_id, context=context)


# ---------------------------------------------------------------------------
# Administration
# ---------------------------------------------------------------------------


def set_role(db: Session, actor: User, target: User, role: UserRole, context: RequestContext) -> None:
    if not actor.is_admin:
        raise AuthError("forbidden", "Administrator privileges are required.", status_code=403)
    if actor.user_id == target.user_id and role is not UserRole.ADMIN:
        # Stops an administrator removing the last set of admin hands by accident.
        raise AuthError("invalid_state", "You cannot remove your own administrator role.")

    target.role = role.value
    # A privilege change should not leave sessions running under the old role.
    _invalidate_credentials(db, target)
    revoke_all_sessions(db, target, reason="role_changed")
    db.flush()
    record_event(db, "role.changed", user_id=target.user_id, context=context,
                 detail={"role": role.value, "actor_user_id": actor.user_id})


def list_auth_events(db: Session, user: User, limit: int = 50) -> list[AuthEvent]:
    return list(
        db.scalars(
            select(AuthEvent)
            .where(AuthEvent.user_id == user.user_id)
            .order_by(AuthEvent.created_at.desc())
            .limit(limit)
        ).all()
    )


def purge_expired(db: Session) -> dict[str, int]:
    """Housekeeping for expired sessions and tokens. Safe to run repeatedly."""
    now = datetime.now(timezone.utc)
    sessions = db.execute(delete(UserSession).where(UserSession.expires_at < now)).rowcount or 0
    tokens = db.execute(delete(AuthToken).where(AuthToken.expires_at < now)).rowcount or 0
    return {"sessions": sessions, "tokens": tokens}
