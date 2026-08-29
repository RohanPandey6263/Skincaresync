"""Session and CSRF cookie handling, plus safe redirect validation."""

from __future__ import annotations

import secrets
from typing import Literal, cast
from urllib.parse import urlparse

from fastapi import Response

from ..config import Settings, get_settings

SameSite = Literal["lax", "strict", "none"]


def _samesite(settings: Settings) -> SameSite:
    """Config validation already restricted this to the three legal values."""
    return cast(SameSite, settings.cookie_samesite)

# Browsers cap cookies around 4KB; ours are far smaller, but a bound keeps a
# malformed request from being handed to the cookie parser at all.
MAX_TOKEN_LENGTH = 512


def set_session_cookie(response: Response, token: str, settings: Settings | None = None) -> None:
    """Attach the session cookie.

    HttpOnly so script cannot read it, which is what keeps an XSS bug from
    becoming account theft, and why the token is not in localStorage. `Secure`
    and `SameSite` come from configuration and are validated at startup.
    """
    settings = settings or get_settings()
    response.set_cookie(
        key=settings.session_cookie_name,
        value=token,
        max_age=settings.session_absolute_max_age_seconds,
        httponly=True,
        secure=settings.cookie_secure,
        samesite=_samesite(settings),
        domain=settings.cookie_domain,
        path="/",
    )


def set_csrf_cookie(response: Response, settings: Settings | None = None) -> str:
    """Issue a CSRF token and return it.

    Deliberately *not* HttpOnly: the double-submit pattern needs the frontend to
    read this value and echo it in a header. That is safe because it is not a
    credential on its own -- it only proves the caller can read a cookie from
    our own origin, which a cross-site attacker cannot.
    """
    settings = settings or get_settings()
    token = secrets.token_urlsafe(32)
    response.set_cookie(
        key=settings.csrf_cookie_name,
        value=token,
        max_age=settings.session_absolute_max_age_seconds,
        httponly=False,
        secure=settings.cookie_secure,
        samesite=_samesite(settings),
        domain=settings.cookie_domain,
        path="/",
    )
    return token


def clear_auth_cookies(response: Response, settings: Settings | None = None) -> None:
    settings = settings or get_settings()
    for name in (settings.session_cookie_name, settings.csrf_cookie_name):
        response.delete_cookie(
            key=name,
            path="/",
            domain=settings.cookie_domain,
            httponly=name == settings.session_cookie_name,
            secure=settings.cookie_secure,
            samesite=_samesite(settings),
        )


def safe_redirect_path(candidate: str | None, fallback: str = "/") -> str:
    """Reduce a caller-supplied `next` value to a same-site path, or the fallback.

    Post-sign-in redirects are a classic open-redirect sink: an attacker sends
    `/signin?next=https://evil.example` and the victim is bounced off-site
    still trusting the page they started on. Only a plain, single-slash,
    site-relative path survives this.
    """
    if not candidate or not isinstance(candidate, str):
        return fallback

    candidate = candidate.strip()
    if not candidate.startswith("/"):
        return fallback
    # "//evil.com" and "/\evil.com" are protocol-relative; browsers treat both
    # as absolute URLs to another host.
    if candidate.startswith("//") or candidate.startswith("/\\"):
        return fallback
    # A control character can be used to smuggle a header or split the path.
    if any(ch in candidate for ch in ("\r", "\n", "\t", "\x00")):
        return fallback

    parsed = urlparse(candidate)
    if parsed.scheme or parsed.netloc:
        return fallback
    return candidate or fallback
