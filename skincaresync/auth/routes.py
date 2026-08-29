"""Authentication HTTP endpoints.

Routes translate between HTTP and `service.py` and do no policy work of their
own. Two things are enforced at this layer because they are properties of the
transport rather than the domain: per-client rate limits, and the uniform
responses that keep registration and password reset from confirming whether an
address has an account.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from ..ratelimit import RateLimiter, limiter_dependency
from .cookies import clear_auth_cookies, safe_redirect_path, set_csrf_cookie, set_session_cookie
from .db import get_db
from .dependencies import (
    AuthenticatedUser,
    enforce_csrf,
    get_optional_user,
    get_request_context,
    require_admin,
    require_user,
)
from .models import User, UserRole
from .schemas import (
    AuthEventResponse,
    LinkedIdentityResponse,
    ChangePasswordRequest,
    DeleteAccountRequest,
    ForgotPasswordRequest,
    LoginRequest,
    LoginResponse,
    MessageResponse,
    RegisterRequest,
    ResendVerificationRequest,
    ResetPasswordRequest,
    SessionResponse,
    TokenRequest,
    UpdateRoleRequest,
    UserResponse,
)
from . import service
from .service import AuthError, RequestContext

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth", tags=["auth"])
admin_router = APIRouter(prefix="/api/admin", tags=["admin"])

# Credential-guessing and mail-flooding surfaces get their own tight budgets.
# These are per client address and complement the per-account lockout in
# service.authenticate, which catches a distributed attack on one account.
_login_limiter = RateLimiter(limit=10, window_seconds=300)
_register_limiter = RateLimiter(limit=5, window_seconds=3600)
_email_limiter = RateLimiter(limit=5, window_seconds=3600)
_token_limiter = RateLimiter(limit=20, window_seconds=3600)

rate_limit_login = Depends(limiter_dependency(_login_limiter))
rate_limit_register = Depends(limiter_dependency(_register_limiter))
rate_limit_email = Depends(limiter_dependency(_email_limiter))
rate_limit_token = Depends(limiter_dependency(_token_limiter))

# Returned verbatim for every registration, resend and reset request, whether or
# not the address exists.
GENERIC_EMAIL_SENT = (
    "If that email address needs confirming, we have sent a message to it. "
    "Check your inbox, including spam."
)
GENERIC_RESET_SENT = (
    "If an account exists for that email address, we have sent password reset "
    "instructions to it."
)


def reset_rate_limiters() -> None:
    """Clear all auth rate-limit counters. Used by tests."""
    for limiter in (_login_limiter, _register_limiter, _email_limiter, _token_limiter):
        limiter.reset()


def _user_response(user: User) -> UserResponse:
    return UserResponse(
        user_id=user.user_id,
        email=user.email,
        display_name=user.display_name,
        role=user.role,
        status=user.status,
        email_verified=user.is_email_verified,
        has_password=user.has_password,
        created_at=user.created_at,
    )


def _handle(error: AuthError) -> HTTPException:
    return HTTPException(status_code=error.status_code, detail=error.message)


# ---------------------------------------------------------------------------
# Registration and verification
# ---------------------------------------------------------------------------


@router.post("/register", response_model=MessageResponse, dependencies=[rate_limit_register])
def register(
    payload: RegisterRequest,
    db: Session = Depends(get_db),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    result = service.register(
        db, payload.email, payload.password, payload.display_name, context
    )
    # Identical response for a new address and one already registered.
    return MessageResponse(message=GENERIC_EMAIL_SENT, dev_token=result.dev_token)


@router.post("/verify-email", response_model=MessageResponse, dependencies=[rate_limit_token])
def verify_email(
    payload: TokenRequest,
    db: Session = Depends(get_db),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    try:
        service.verify_email(db, payload.token, context)
    except AuthError as error:
        raise _handle(error) from None
    return MessageResponse(message="Your email address is confirmed. You can sign in now.")


@router.post("/resend-verification", response_model=MessageResponse, dependencies=[rate_limit_email])
def resend_verification(
    payload: ResendVerificationRequest,
    db: Session = Depends(get_db),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    dev_token = service.resend_verification(db, payload.email, context)
    return MessageResponse(message=GENERIC_EMAIL_SENT, dev_token=dev_token)


# ---------------------------------------------------------------------------
# Sign in and out
# ---------------------------------------------------------------------------


@router.post("/login", response_model=LoginResponse, dependencies=[rate_limit_login])
def login(
    payload: LoginRequest,
    response: Response,
    db: Session = Depends(get_db),
    context: RequestContext = Depends(get_request_context),
) -> LoginResponse:
    try:
        user = service.authenticate(db, payload.email, payload.password, context)
    except AuthError as error:
        raise _handle(error) from None

    issued = service.create_session(db, user, context)
    set_session_cookie(response, issued.token)
    csrf_token = set_csrf_cookie(response)

    return LoginResponse(
        user=_user_response(user),
        csrf_token=csrf_token,
        # Never trusted as given; reduced to a site-relative path.
        redirect_to=safe_redirect_path(payload.next, fallback="/"),
    )


@router.post("/logout", response_model=MessageResponse, dependencies=[Depends(enforce_csrf)])
def logout(
    response: Response,
    db: Session = Depends(get_db),
    current: AuthenticatedUser | None = Depends(get_optional_user),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    # Idempotent: signing out without a session still clears cookies and reports
    # success, so a stale tab cannot get stuck on an error.
    if current is not None:
        service.revoke_session(db, current.session, reason="logout")
        service.record_event(db, "logout", user_id=current.user.user_id, context=context)
    clear_auth_cookies(response)
    return MessageResponse(message="You are signed out.")


@router.post("/logout-all", response_model=MessageResponse, dependencies=[Depends(enforce_csrf)])
def logout_all(
    response: Response,
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_user),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    count = service.revoke_all_sessions(db, current.user, reason="logout_all")
    service.record_event(
        db, "logout_all", user_id=current.user.user_id, context=context,
        detail={"sessions_revoked": count},
    )
    clear_auth_cookies(response)
    return MessageResponse(message=f"Signed out of {count} device(s).")


@router.get("/me", response_model=UserResponse)
def me(current: AuthenticatedUser = Depends(require_user)) -> UserResponse:
    return _user_response(current.user)


@router.get("/session", response_model=LoginResponse | None)
def current_session(
    response: Response,
    current: AuthenticatedUser | None = Depends(get_optional_user),
) -> LoginResponse | None:
    """Bootstrap endpoint: who am I, and a fresh CSRF token.

    Called on page load. Returns null rather than 401 when signed out, because
    "no session" is the normal state for a visitor, not an error.
    """
    if current is None:
        return None
    csrf_token = set_csrf_cookie(response)
    return LoginResponse(
        user=_user_response(current.user), csrf_token=csrf_token, redirect_to="/"
    )


# ---------------------------------------------------------------------------
# Password reset and change
# ---------------------------------------------------------------------------


@router.post("/forgot-password", response_model=MessageResponse, dependencies=[rate_limit_email])
def forgot_password(
    payload: ForgotPasswordRequest,
    db: Session = Depends(get_db),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    dev_token = service.request_password_reset(db, payload.email, context)
    return MessageResponse(message=GENERIC_RESET_SENT, dev_token=dev_token)


@router.post("/reset-password", response_model=MessageResponse, dependencies=[rate_limit_token])
def reset_password(
    payload: ResetPasswordRequest,
    response: Response,
    db: Session = Depends(get_db),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    try:
        service.reset_password(db, payload.token, payload.password, context)
    except AuthError as error:
        raise _handle(error) from None
    # Every session was revoked, including possibly this browser's. Clearing the
    # cookies keeps the client from holding one it can no longer use.
    clear_auth_cookies(response)
    return MessageResponse(
        message="Your password is updated and all devices were signed out. Sign in with your new password."
    )


@router.post("/change-password", response_model=MessageResponse, dependencies=[Depends(enforce_csrf)])
def change_password(
    payload: ChangePasswordRequest,
    response: Response,
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_user),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    try:
        revoked = service.change_password(
            db,
            current.user,
            payload.current_password,
            payload.password,
            context,
            current_session_id=current.session.session_id,
        )
    except AuthError as error:
        raise _handle(error) from None

    # This session survives, but its CSRF token is reissued alongside.
    set_csrf_cookie(response)
    return MessageResponse(
        message=f"Your password is updated. {revoked} other device(s) were signed out."
    )


# ---------------------------------------------------------------------------
# Sessions and audit
# ---------------------------------------------------------------------------


@router.get("/sessions", response_model=list[SessionResponse])
def list_sessions(
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_user),
) -> list[SessionResponse]:
    return [
        SessionResponse(
            session_id=s.session_id,
            created_at=s.created_at,
            last_seen_at=s.last_seen_at,
            ip_address=str(s.ip_address) if s.ip_address else None,
            user_agent=s.user_agent,
            current=s.session_id == current.session.session_id,
        )
        for s in service.list_sessions(db, current.user)
    ]


@router.delete("/sessions/{session_id}", response_model=MessageResponse,
               dependencies=[Depends(enforce_csrf)])
def revoke_session(
    session_id: int,
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_user),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    target = next(
        (s for s in service.list_sessions(db, current.user) if s.session_id == session_id),
        None,
    )
    # Scoped to the caller's own sessions, so passing another user's id is a 404
    # and not a cross-account revocation.
    if target is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Session not found.")

    service.revoke_session(db, target, reason="revoked_by_user")
    service.record_event(
        db, "session.revoked", user_id=current.user.user_id, context=context,
        detail={"session_id": session_id},
    )
    return MessageResponse(message="That device was signed out.")


@router.get("/events", response_model=list[AuthEventResponse])
def list_events(
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_user),
) -> list[AuthEventResponse]:
    return [
        AuthEventResponse(
            event_type=event.event_type,
            created_at=event.created_at,
            ip_address=str(event.ip_address) if event.ip_address else None,
            detail=event.detail,
        )
        for event in service.list_auth_events(db, current.user)
    ]


# ---------------------------------------------------------------------------
# Linked provider accounts
# ---------------------------------------------------------------------------


@router.get("/identities", response_model=list[LinkedIdentityResponse])
def list_identities(
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_user),
) -> list[LinkedIdentityResponse]:
    from .oauth import service as oauth_service

    return [
        LinkedIdentityResponse(
            provider=identity.provider,
            email=identity.email,
            created_at=identity.created_at,
            last_login_at=identity.last_login_at,
        )
        for identity in oauth_service.list_identities(db, current.user)
    ]


@router.delete("/identities/{provider_key}", response_model=MessageResponse,
               dependencies=[Depends(enforce_csrf)])
def unlink_identity(
    provider_key: str,
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_user),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    from .oauth import service as oauth_service

    try:
        oauth_service.unlink(db, current.user, provider_key, context)
    except AuthError as error:
        raise _handle(error) from None
    return MessageResponse(message="That account is disconnected.")


# ---------------------------------------------------------------------------
# Account lifecycle
# ---------------------------------------------------------------------------


@router.post("/deactivate", response_model=MessageResponse, dependencies=[Depends(enforce_csrf)])
def deactivate(
    response: Response,
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_user),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    service.deactivate_account(db, current.user, context)
    clear_auth_cookies(response)
    return MessageResponse(
        message="Your account is deactivated. Contact support to restore it."
    )


@router.post("/delete", response_model=MessageResponse, dependencies=[Depends(enforce_csrf)])
def delete_account(
    payload: DeleteAccountRequest,
    response: Response,
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_user),
    context: RequestContext = Depends(get_request_context),
) -> MessageResponse:
    # Re-authentication, so an unattended signed-in browser cannot erase the
    # account.
    from .security import verify_password

    if not verify_password(current.user.password_hash, payload.current_password):
        service.record_event(
            db, "account.delete_failed", user_id=current.user.user_id, context=context
        )
        raise HTTPException(status_code=400, detail="Your current password is incorrect.")

    service.delete_account(db, current.user, context)
    clear_auth_cookies(response)
    return MessageResponse(message="Your account and personal details have been removed.")


# ---------------------------------------------------------------------------
# Administration
# ---------------------------------------------------------------------------


@admin_router.get("/users", response_model=list[UserResponse])
def admin_list_users(
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_admin),
    limit: int = 50,
    offset: int = 0,
) -> list[UserResponse]:
    from sqlalchemy import select

    limit = max(1, min(limit, 200))
    rows = db.scalars(
        select(User).order_by(User.created_at.desc()).limit(limit).offset(max(0, offset))
    ).all()
    return [_user_response(user) for user in rows]


@admin_router.post("/users/{user_id}/role", response_model=UserResponse,
                   dependencies=[Depends(enforce_csrf)])
def admin_set_role(
    user_id: int,
    payload: UpdateRoleRequest,
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_admin),
    context: RequestContext = Depends(get_request_context),
) -> UserResponse:
    target = service.get_user(db, user_id)
    if target is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")
    try:
        service.set_role(db, current.user, target, UserRole(payload.role), context)
    except AuthError as error:
        raise _handle(error) from None
    return _user_response(target)


@admin_router.get("/auth-events", response_model=list[AuthEventResponse])
def admin_list_events(
    db: Session = Depends(get_db),
    current: AuthenticatedUser = Depends(require_admin),
    limit: int = 100,
) -> list[AuthEventResponse]:
    from sqlalchemy import select

    from .models import AuthEvent

    limit = max(1, min(limit, 500))
    rows = db.scalars(
        select(AuthEvent).order_by(AuthEvent.created_at.desc()).limit(limit)
    ).all()
    return [
        AuthEventResponse(
            event_type=event.event_type,
            created_at=event.created_at,
            ip_address=str(event.ip_address) if event.ip_address else None,
            detail=event.detail,
        )
        for event in rows
    ]
