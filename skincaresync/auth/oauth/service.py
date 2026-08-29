"""Social sign-in: flow state, account resolution, and linking rules.

The linking rules are the security-critical part, so they are stated plainly:

1. A provider account is identified by `(provider, sub)`, never by email. An
   email address can be reassigned by whoever controls the domain; `sub` is
   stable and unique to the provider.

2. An existing local account is joined to a provider account only when the
   provider asserts `email_verified` for the matching address. That assertion is
   the provider vouching for mailbox control, which is the same standard our own
   verification link meets.

3. When the provider does *not* verify the address and a local account already
   holds it, the sign-in is refused rather than either linking or silently
   creating a second account. Linking would hand over an account to whoever can
   set an unverified address at the provider; creating a duplicate would leave
   two accounts fighting over one identity.

4. Unlinking the last sign-in method is refused. An account with no password and
   no identities cannot be signed into at all.
"""

from __future__ import annotations

import logging
import secrets
from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ...config import Settings, get_settings
from ..models import OAuthFlow, User, UserIdentity, UserStatus, utcnow
from ..security import generate_token, hash_token
from ..service import AuthError, RequestContext, record_event
from .client import OAuthIdentity, generate_pkce_pair
from .providers import OAuthProvider

logger = logging.getLogger(__name__)

# Long enough for a slow sign-in with a password manager and a second factor,
# short enough that an abandoned flow row is not useful to anyone.
FLOW_TTL_SECONDS = 600


@dataclass
class StartedFlow:
    flow_key: str  # goes in a short-lived HttpOnly cookie; never persisted
    state: str
    nonce: str
    code_verifier: str
    code_challenge: str


def start_flow(
    db: Session,
    provider: OAuthProvider,
    redirect_to: str,
    link_user_id: int | None = None,
) -> StartedFlow:
    """Create server-side state for a sign-in and return what the redirect needs.

    State, PKCE verifier and nonce live in the database rather than in a signed
    cookie, so nothing here has to choose or implement a signing construction.
    The browser holds only an opaque key, and only its hash is stored.
    """
    flow_key = generate_token()
    state = secrets.token_urlsafe(32)
    nonce = secrets.token_urlsafe(32)
    verifier, challenge = generate_pkce_pair()

    db.add(
        OAuthFlow(
            flow_key_hash=hash_token(flow_key),
            provider=provider.key,
            state=state,
            code_verifier=verifier,
            nonce=nonce,
            redirect_to=redirect_to,
            link_user_id=link_user_id,
            expires_at=utcnow() + timedelta(seconds=FLOW_TTL_SECONDS),
        )
    )
    db.flush()
    return StartedFlow(flow_key, state, nonce, verifier, challenge)


def consume_flow(db: Session, flow_key: str, provider_key: str, state: str) -> OAuthFlow:
    """Redeem the flow for a callback, or raise.

    Three things must agree: the cookie the browser presents, the state the
    provider echoes, and the provider the callback arrived on. The state check is
    what stops a cross-site request from completing a sign-in the victim never
    started -- an attacker can cause the callback but cannot produce a state that
    matches the victim's cookie.
    """
    row = db.scalar(
        select(OAuthFlow).where(OAuthFlow.flow_key_hash == hash_token(flow_key)).with_for_update()
    )
    if row is None or not row.is_usable():
        raise AuthError("invalid_flow", "This sign-in link has expired. Please try again.")
    if row.provider != provider_key:
        raise AuthError("invalid_flow", "This sign-in link has expired. Please try again.")
    if not secrets.compare_digest(row.state, state or ""):
        logger.warning("oauth state mismatch for provider %s", provider_key)
        raise AuthError("invalid_flow", "This sign-in link has expired. Please try again.")

    # Single-use: a replayed callback finds it already consumed.
    row.consumed_at = utcnow()
    db.flush()
    return row


def purge_expired_flows(db: Session) -> int:
    from sqlalchemy import delete

    return db.execute(delete(OAuthFlow).where(OAuthFlow.expires_at < utcnow())).rowcount or 0


def _find_identity(db: Session, provider: str, subject: str) -> UserIdentity | None:
    return db.scalar(
        select(UserIdentity).where(
            UserIdentity.provider == provider, UserIdentity.subject == subject
        )
    )


def resolve_sign_in(
    db: Session,
    identity: OAuthIdentity,
    context: RequestContext,
    settings: Settings | None = None,
) -> User:
    """Return the user this provider identity signs in as, creating one if needed."""
    settings = settings or get_settings()
    existing = _find_identity(db, identity.provider, identity.subject)

    if existing is not None:
        user = db.get(User, existing.user_id)
        if user is None or not user.is_active:
            record_event(
                db, "oauth.blocked", user_id=existing.user_id, context=context,
                detail={"provider": identity.provider, "reason": "inactive"},
            )
            raise AuthError(
                "account_unavailable", "This account is not available.", status_code=403
            )

        existing.last_login_at = utcnow()
        # Keep the provider's view of the address current for display.
        existing.email = identity.email
        existing.email_verified = identity.email_verified
        db.flush()
        record_event(
            db, "oauth.login", user_id=user.user_id, context=context,
            detail={"provider": identity.provider},
        )
        return user

    # No identity yet. Does an account already hold this address?
    if identity.email:
        owner = db.scalar(select(User).where(User.email_normalized == identity.email))
        if owner is not None:
            if not identity.email_verified:
                # Rule 3: refuse rather than link or duplicate.
                record_event(
                    db, "oauth.link_refused", user_id=owner.user_id, context=context,
                    detail={"provider": identity.provider, "reason": "email_unverified"},
                )
                raise AuthError(
                    "email_unverified",
                    f"{identity.provider.title()} has not verified that email address. "
                    "Sign in with your password instead, then link the account from "
                    "your security settings.",
                    status_code=403,
                )
            if not owner.is_active:
                raise AuthError(
                    "account_unavailable", "This account is not available.", status_code=403
                )
            return _link(db, owner, identity, context, reason="auto_verified_email")

    return _create_user(db, identity, context)


def _link(
    db: Session,
    user: User,
    identity: OAuthIdentity,
    context: RequestContext,
    reason: str,
) -> User:
    db.add(
        UserIdentity(
            user_id=user.user_id,
            provider=identity.provider,
            subject=identity.subject,
            email=identity.email,
            email_verified=identity.email_verified,
            last_login_at=utcnow(),
        )
    )
    try:
        db.flush()
    except IntegrityError:
        # Either this provider account was linked elsewhere in a race, or this
        # user already has this provider. Both are refusals, not errors to paper
        # over: silently reassigning an identity is how accounts get stolen.
        db.rollback()
        raise AuthError(
            "already_linked",
            "That account is already connected to a different SkincareSync account.",
            status_code=409,
        ) from None

    # Signing in through a provider that verified the address also confirms it
    # here; the provider has proven the same thing our own link would.
    if identity.email_verified and not user.is_email_verified:
        user.email_verified_at = utcnow()
        db.flush()

    record_event(
        db, "oauth.linked", user_id=user.user_id, context=context,
        detail={"provider": identity.provider, "reason": reason},
    )
    return user


def _create_user(db: Session, identity: OAuthIdentity, context: RequestContext) -> User:
    if not identity.email:
        # Apple relay addresses still arrive as an address; a provider that sends
        # none leaves us unable to contact or de-duplicate the account.
        raise AuthError(
            "no_email",
            "That provider did not share an email address, which this account needs.",
            status_code=400,
        )

    user = User(
        email=identity.email,
        # No password. Not a placeholder: the column is nullable precisely so
        # that "cannot sign in with a password" is representable.
        password_hash=None,
        display_name=identity.display_name,
        status=UserStatus.ACTIVE.value,
        email_verified_at=utcnow() if identity.email_verified else None,
    )
    db.add(user)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise AuthError(
            "account_conflict", "Could not complete sign-in. Please try again.", status_code=409
        ) from None

    record_event(
        db, "oauth.registered", user_id=user.user_id, context=context,
        detail={"provider": identity.provider},
    )
    return _link(db, user, identity, context, reason="new_account")


def link_to_current_user(
    db: Session,
    user: User,
    identity: OAuthIdentity,
    context: RequestContext,
) -> User:
    """Link a provider to the signed-in account, from security settings."""
    existing = _find_identity(db, identity.provider, identity.subject)
    if existing is not None:
        if existing.user_id == user.user_id:
            return user
        raise AuthError(
            "already_linked",
            "That account is already connected to a different SkincareSync account.",
            status_code=409,
        )
    return _link(db, user, identity, context, reason="user_initiated")


def list_identities(db: Session, user: User) -> list[UserIdentity]:
    return list(
        db.scalars(
            select(UserIdentity)
            .where(UserIdentity.user_id == user.user_id)
            .order_by(UserIdentity.provider)
        ).all()
    )


def unlink(db: Session, user: User, provider_key: str, context: RequestContext) -> None:
    """Remove a linked provider, unless it is the only way in."""
    identities = list_identities(db, user)
    target = next((i for i in identities if i.provider == provider_key), None)
    if target is None:
        raise AuthError("not_linked", "That account is not connected.", status_code=404)

    # Rule 4. Without this an account can be locked out of itself permanently.
    if not user.has_password and len(identities) == 1:
        raise AuthError(
            "last_sign_in_method",
            "Set a password before disconnecting your only sign-in method.",
        )

    db.delete(target)
    db.flush()
    record_event(
        db, "oauth.unlinked", user_id=user.user_id, context=context,
        detail={"provider": provider_key},
    )


def revoke_identities_for_deleted_user(db: Session, user_id: int) -> None:
    """Drop provider links when an account is deleted.

    Deletion scrambles the email so the address can be reused; leaving the
    identity rows would let the old provider account sign straight back into the
    deleted shell.
    """
    from sqlalchemy import delete

    db.execute(delete(UserIdentity).where(UserIdentity.user_id == user_id))
    db.execute(update(OAuthFlow).where(OAuthFlow.link_user_id == user_id).values(consumed_at=utcnow()))
    db.flush()
