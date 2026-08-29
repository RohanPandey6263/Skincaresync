"""Social sign-in endpoints.

Two routes per provider, plus a discovery endpoint the UI uses so it never shows
a button for a provider that is not configured.

These are ordinary top-level browser navigations, not XHR, because that is what
OAuth requires. They therefore end in redirects rather than JSON, and errors are
carried back to the sign-in screen as a short code rather than a message, so
nothing from a provider is reflected into the page.
"""

from __future__ import annotations

import json
import logging

from fastapi import APIRouter, Depends, Form, HTTPException, Request, Response, status
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session

from ...config import get_settings
from ...ratelimit import RateLimiter, limiter_dependency
from ..cookies import SameSite, safe_redirect_path, set_csrf_cookie, set_session_cookie
from ..db import get_db
from ..dependencies import AuthenticatedUser, get_request_context, require_user
from ..service import AuthError, RequestContext, create_session, record_event
from . import service as oauth_service
from .client import OAuthError, build_authorization_url, exchange_code, identity_from_claims, verify_id_token
from . import providers as provider_registry

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth/oauth", tags=["auth"])

# Starting a flow writes a row, so it is throttled like any other write.
_oauth_limiter = RateLimiter(limit=20, window_seconds=600)
rate_limit_oauth = Depends(limiter_dependency(_oauth_limiter))

FLOW_COOKIE = "skincaresync_oauth"


def reset_oauth_rate_limiter() -> None:
    _oauth_limiter.reset()


def _callback_url(provider_key: str) -> str:
    """The redirect URI registered with the provider.

    Built from API_BASE_URL, not APP_BASE_URL: the callback route lives on this
    API, which is a different origin from the frontend whenever the two are
    served separately -- the normal development setup. Pointing it at the
    frontend produces a dead URL that fails only after the user has already
    approved at the provider.

    Never derived from the request, and must match the provider registration
    byte for byte.
    """
    return f"{get_settings().api_base_url}/api/auth/oauth/{provider_key}/callback"


def _set_flow_cookie(response: Response, flow_key: str, cross_site: bool) -> None:
    """Attach the short-lived cookie that binds the callback to this browser.

    Apple answers with a cross-site form POST, and a `SameSite=Lax` cookie is not
    sent on one -- the flow would break with a state mismatch that looks like an
    attack. Such a flow therefore needs `SameSite=None`, which browsers only
    honour on a `Secure` cookie, which means Apple cannot be exercised over
    plain http. That constraint is Apple's, not ours.
    """
    settings = get_settings()
    same_site: SameSite = "none" if (cross_site and settings.cookie_secure) else "lax"
    response.set_cookie(
        key=FLOW_COOKIE,
        value=flow_key,
        max_age=oauth_service.FLOW_TTL_SECONDS,
        httponly=True,
        secure=settings.cookie_secure,
        samesite=same_site,
        path="/api/auth/oauth",
        domain=settings.cookie_domain,
    )


def _clear_flow_cookie(response: Response) -> None:
    settings = get_settings()
    response.delete_cookie(
        key=FLOW_COOKIE, path="/api/auth/oauth", domain=settings.cookie_domain
    )


def _failure_redirect(code: str) -> RedirectResponse:
    """Send the user back to sign-in with a short, fixed error code.

    A code rather than a message: nothing a provider returns is reflected into
    the page, and the client owns the wording.
    """
    settings = get_settings()
    return RedirectResponse(f"{settings.app_base_url}/signin?error={code}", status_code=303)


@router.get("/providers")
def list_providers() -> list[dict]:
    """Providers with complete credentials, for rendering the buttons."""
    return [
        {"key": provider.key, "display_name": provider.display_name}
        for provider in provider_registry.get_providers().values()
    ]


@router.get("/{provider_key}/start", dependencies=[rate_limit_oauth])
def start(
    provider_key: str,
    request: Request,
    next: str = "/",
    db: Session = Depends(get_db),
) -> RedirectResponse:
    """Begin a sign-in and redirect to the provider."""
    provider = provider_registry.get_provider(provider_key)
    if provider is None:
        # Unconfigured providers do not exist as far as callers are concerned.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")

    # Reduced to a site-relative path before it is ever stored, so the value that
    # comes back out of the database at callback time is already safe.
    redirect_to = safe_redirect_path(next, fallback="/")

    flow = oauth_service.start_flow(db, provider, redirect_to)
    target = build_authorization_url(
        provider,
        redirect_uri=_callback_url(provider.key),
        state=flow.state,
        nonce=flow.nonce,
        code_challenge=flow.code_challenge,
    )

    response = RedirectResponse(target, status_code=303)
    _set_flow_cookie(response, flow.flow_key, cross_site=provider.uses_form_post)
    return response


@router.get("/{provider_key}/link", dependencies=[rate_limit_oauth])
def start_link(
    provider_key: str,
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_user),
) -> RedirectResponse:
    """Begin linking a provider to the account that is already signed in."""
    provider = provider_registry.get_provider(provider_key)
    if provider is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")

    flow = oauth_service.start_flow(
        db, provider, redirect_to="/account/security", link_user_id=current.user.user_id
    )
    target = build_authorization_url(
        provider,
        redirect_uri=_callback_url(provider.key),
        state=flow.state,
        nonce=flow.nonce,
        code_challenge=flow.code_challenge,
    )
    response = RedirectResponse(target, status_code=303)
    _set_flow_cookie(response, flow.flow_key, cross_site=provider.uses_form_post)
    return response


def _complete(
    provider_key: str,
    request: Request,
    db: Session,
    context: RequestContext,
    code: str | None,
    state: str | None,
    error: str | None,
    apple_user: str | None,
) -> RedirectResponse:
    """Shared callback handling for both the GET and POST forms."""
    settings = get_settings()
    provider = provider_registry.get_provider(provider_key)
    if provider is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Not found")

    if error:
        # The user declined, or the provider refused. Not an application error.
        logger.info("%s sign-in returned error=%s", provider_key, error[:40])
        return _failure_redirect("cancelled")

    flow_key = request.cookies.get(FLOW_COOKIE)
    if not flow_key or not code:
        return _failure_redirect("invalid_request")

    try:
        flow = oauth_service.consume_flow(db, flow_key, provider_key, state or "")
    except AuthError:
        return _failure_redirect("expired")

    try:
        tokens = exchange_code(
            provider, code, redirect_uri=_callback_url(provider.key), code_verifier=flow.code_verifier
        )
        claims = verify_id_token(provider, tokens["id_token"], flow.nonce)
    except OAuthError as exc:
        record_event(db, "oauth.failed", context=context,
                     detail={"provider": provider_key, "reason": exc.code})
        return _failure_redirect(exc.code)

    apple_payload = None
    if apple_user:
        # Apple sends the name once, as a JSON string in the first callback body.
        try:
            apple_payload = json.loads(apple_user)
        except (ValueError, TypeError):
            apple_payload = None

    identity = identity_from_claims(provider, claims, apple_payload)

    try:
        if flow.link_user_id is not None:
            from ..models import User

            user = db.get(User, flow.link_user_id)
            if user is None or not user.is_active:
                return _failure_redirect("account_unavailable")
            oauth_service.link_to_current_user(db, user, identity, context)
            response = RedirectResponse(
                f"{settings.app_base_url}{flow.redirect_to}?linked={provider_key}", status_code=303
            )
            _clear_flow_cookie(response)
            return response

        user = oauth_service.resolve_sign_in(db, identity, context)
    except AuthError as exc:
        return _failure_redirect(exc.code)

    issued = create_session(db, user, context)
    # `redirect_to` was reduced to a site-relative path before storage, so this
    # cannot leave the site.
    response = RedirectResponse(f"{settings.app_base_url}{flow.redirect_to}", status_code=303)
    set_session_cookie(response, issued.token)
    set_csrf_cookie(response)
    _clear_flow_cookie(response)
    return response


@router.get("/{provider_key}/callback")
def callback(
    provider_key: str,
    request: Request,
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
    db: Session = Depends(get_db),
    context: RequestContext = Depends(get_request_context),
) -> RedirectResponse:
    """Redirect-style callback. Google uses this."""
    return _complete(provider_key, request, db, context, code, state, error, None)


@router.post("/{provider_key}/callback")
def callback_form_post(
    provider_key: str,
    request: Request,
    code: str | None = Form(default=None),
    state: str | None = Form(default=None),
    error: str | None = Form(default=None),
    user: str | None = Form(default=None),
    db: Session = Depends(get_db),
    context: RequestContext = Depends(get_request_context),
) -> RedirectResponse:
    """Form-post callback. Apple uses this when name or email scopes are requested.

    Exempt from the application's CSRF check: this request comes from Apple, not
    from our own page, so it cannot carry our CSRF token. The OAuth `state`
    parameter is the equivalent protection and is verified in `consume_flow`.
    """
    return _complete(provider_key, request, db, context, code, state, error, user)
