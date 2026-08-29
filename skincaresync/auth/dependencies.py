"""FastAPI dependencies: current user, role gates, and CSRF enforcement.

Authorization is decided here and in the service layer, on the server. The
frontend hides controls a user cannot use, but that is presentation only -- every
protected route re-checks, so calling the API directly gains nothing.
"""

from __future__ import annotations

import ipaddress
import logging
import os
from dataclasses import dataclass

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from ..config import Settings, get_settings
from .cookies import MAX_TOKEN_LENGTH
from .db import get_db
from .models import User, UserSession
from .security import tokens_equal
from .service import RequestContext, resolve_session

logger = logging.getLogger(__name__)

# Methods that must not change state, and so need no CSRF token.
SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS", "TRACE"})


def _coerce_ip(value: str | None) -> str | None:
    """Return `value` only if it parses as an IP address.

    `auth_events.ip_address` and `user_sessions.ip_address` are INET columns.
    A client host is not guaranteed to be an address -- a unix socket, a test
    client, or a forged X-Forwarded-For can all put arbitrary text here, and
    passing that straight to Postgres turns an audit write into a 500.
    """
    if not value:
        return None
    try:
        return str(ipaddress.ip_address(value.strip()))
    except ValueError:
        return None


def get_request_context(request: Request) -> RequestContext:
    settings = get_settings()
    client_host = request.client.host if request.client else None
    # X-Forwarded-For is attacker-controlled unless a proxy is known to be in
    # front rewriting it, so it is only consulted when the deployment says so.
    if settings.environment != "production" or _trust_proxy():
        forwarded = request.headers.get("x-forwarded-for", "")
        if forwarded:
            client_host = forwarded.split(",")[0].strip() or client_host
    return RequestContext(
        ip_address=_coerce_ip(client_host),
        user_agent=request.headers.get("user-agent"),
    )


def _trust_proxy() -> bool:
    return os.getenv("TRUST_PROXY", "").strip().lower() in {"1", "true", "yes", "on"}


@dataclass
class AuthenticatedUser:
    user: User
    session: UserSession


def _session_token(request: Request, settings: Settings) -> str | None:
    token = request.cookies.get(settings.session_cookie_name)
    if not token or len(token) > MAX_TOKEN_LENGTH:
        return None
    return token


def get_optional_user(
    request: Request,
    db: Session = Depends(get_db),
) -> AuthenticatedUser | None:
    """Resolve the caller if signed in. Never raises."""
    settings = get_settings()
    token = _session_token(request, settings)
    if token is None:
        return None
    resolved = resolve_session(db, token, settings)
    if resolved is None:
        return None
    user, session = resolved
    return AuthenticatedUser(user=user, session=session)


def require_user(
    current: AuthenticatedUser | None = Depends(get_optional_user),
) -> AuthenticatedUser:
    """Gate a route behind a valid session."""
    if current is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sign in to continue.",
            # Tells the client this is an expired/absent session rather than a
            # permissions problem, so it can redirect to sign-in instead of
            # showing an error.
            headers={"WWW-Authenticate": "Cookie"},
        )
    return current


def require_verified_user(
    current: AuthenticatedUser = Depends(require_user),
) -> AuthenticatedUser:
    """Gate a route behind a confirmed email address."""
    if not current.user.is_email_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Confirm your email address to continue.",
        )
    return current


def require_admin(
    current: AuthenticatedUser = Depends(require_user),
) -> AuthenticatedUser:
    """Gate a route behind the admin role.

    Returns 404, not 403, for a signed-in non-admin: an administrative surface
    should not confirm its own existence to someone who cannot use it.
    """
    if not current.user.is_admin:
        logger.warning(
            "non-admin user %s attempted an administrative route", current.user.user_id
        )
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")
    return current


def enforce_csrf(request: Request) -> None:
    """Double-submit CSRF check on state-changing requests.

    The session cookie is `SameSite=Lax`, which already blocks cross-site form
    posts. This is the second layer: the caller must echo the value of a cookie
    only same-origin script can read. A cross-site attacker can cause a request
    but cannot read our cookie, so cannot produce the header.
    """
    if request.method.upper() in SAFE_METHODS:
        return

    settings = get_settings()
    # Unauthenticated endpoints (sign-in, registration, reset) are exempt: there
    # is no session to ride, and requiring a token would mean handing one out to
    # anonymous callers for no gain.
    if not request.cookies.get(settings.session_cookie_name):
        return

    cookie_token = request.cookies.get(settings.csrf_cookie_name)
    header_token = request.headers.get("x-csrf-token")

    if not cookie_token or not header_token or not tokens_equal(cookie_token, header_token):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your session could not be verified. Refresh the page and try again.",
        )
