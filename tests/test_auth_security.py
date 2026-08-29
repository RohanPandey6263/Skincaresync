"""Authorization, CSRF, open redirects, rate limits, and production config.

These cover the properties that hold the system together rather than any one
flow: that authorization is decided on the server, that a signed-in user cannot
reach another account, and that an unsafe production configuration refuses to
start.
"""

from __future__ import annotations

import pytest
from sqlalchemy import select

from skincaresync.auth import service
from skincaresync.auth.cookies import safe_redirect_path
from skincaresync.auth.models import User, UserRole
from tests.test_auth_accounts import PASSWORD, register_and_verify
from tests.test_auth_password import sign_in


def make_admin(db_session, email: str) -> User:
    user = db_session.scalar(select(User).where(User.email_normalized == email))
    user.role = UserRole.ADMIN.value
    db_session.flush()
    return user


# ---------------------------------------------------------------------------
# Protected routes
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "method,path",
    [
        ("get", "/api/auth/me"),
        ("get", "/api/auth/sessions"),
        ("get", "/api/auth/events"),
        ("get", "/api/gaps"),
        ("get", "/api/admin/users"),
        ("get", "/api/admin/auth-events"),
        ("post", "/api/auth/logout-all"),
        ("post", "/api/auth/deactivate"),
    ],
)
def test_protected_routes_reject_anonymous_callers(api_client, method, path):
    response = getattr(api_client, method)(path)
    assert response.status_code in (401, 403, 404), f"{path} returned {response.status_code}"


def test_protected_routes_accept_a_signed_in_caller(api_client):
    register_and_verify(api_client)
    sign_in(api_client)

    assert api_client.get("/api/auth/me").status_code == 200
    assert api_client.get("/api/auth/sessions").status_code == 200


def test_session_endpoint_reports_anonymous_without_erroring(api_client):
    """Being signed out is the normal state for a visitor, not an error."""
    response = api_client.get("/api/auth/session")
    assert response.status_code == 200
    assert response.json() is None


# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------


def test_a_normal_user_cannot_reach_administrative_routes(api_client, db_session):
    """404, not 403: an admin surface should not confirm it exists."""
    register_and_verify(api_client, "normal@example.com")
    sign_in(api_client, "normal@example.com")

    assert api_client.get("/api/admin/users").status_code == 404
    assert api_client.get("/api/admin/auth-events").status_code == 404
    assert api_client.get("/api/gaps").status_code == 404


def test_an_admin_can_reach_administrative_routes(api_client, db_session):
    register_and_verify(api_client, "boss@example.com")
    make_admin(db_session, "boss@example.com")
    sign_in(api_client, "boss@example.com")

    assert api_client.get("/api/admin/users").status_code == 200
    assert api_client.get("/api/admin/auth-events").status_code == 200


def test_new_accounts_are_never_administrators(api_client, db_session):
    register_and_verify(api_client, "fresh@example.com")
    user = db_session.scalar(select(User).where(User.email_normalized == "fresh@example.com"))
    assert user.role == "user"


def test_a_normal_user_cannot_promote_themselves(api_client, db_session):
    register_and_verify(api_client, "climber@example.com")
    csrf = sign_in(api_client, "climber@example.com")
    user = db_session.scalar(select(User).where(User.email_normalized == "climber@example.com"))

    response = api_client.post(
        f"/api/admin/users/{user.user_id}/role",
        json={"role": "admin"},
        headers={"X-CSRF-Token": csrf},
    )

    assert response.status_code == 404
    db_session.refresh(user)
    assert user.role == "user"


def test_an_admin_can_change_a_role_and_it_revokes_their_sessions(api_client, db_session):
    register_and_verify(api_client, "target@example.com")
    from fastapi.testclient import TestClient

    from skincaresync.api import app

    target_client = TestClient(app, base_url="http://testserver")
    target_client.post(
        "/api/auth/login", json={"email": "target@example.com", "password": PASSWORD}
    )
    assert target_client.get("/api/auth/me").status_code == 200

    register_and_verify(api_client, "admin@example.com")
    make_admin(db_session, "admin@example.com")
    csrf = sign_in(api_client, "admin@example.com")
    target = db_session.scalar(select(User).where(User.email_normalized == "target@example.com"))

    response = api_client.post(
        f"/api/admin/users/{target.user_id}/role",
        json={"role": "admin"},
        headers={"X-CSRF-Token": csrf},
    )

    assert response.status_code == 200
    assert response.json()["role"] == "admin"
    # A privilege change must not leave a session running under the old role.
    assert target_client.get("/api/auth/me").status_code == 401


def test_an_admin_cannot_demote_themselves(api_client, db_session):
    register_and_verify(api_client, "solo@example.com")
    admin = make_admin(db_session, "solo@example.com")
    csrf = sign_in(api_client, "solo@example.com")

    response = api_client.post(
        f"/api/admin/users/{admin.user_id}/role",
        json={"role": "user"},
        headers={"X-CSRF-Token": csrf},
    )
    assert response.status_code == 400


def test_an_unknown_role_is_rejected(api_client, db_session):
    register_and_verify(api_client, "admin2@example.com")
    admin = make_admin(db_session, "admin2@example.com")
    csrf = sign_in(api_client, "admin2@example.com")

    assert api_client.post(
        f"/api/admin/users/{admin.user_id}/role",
        json={"role": "superuser"},
        headers={"X-CSRF-Token": csrf},
    ).status_code == 422


# ---------------------------------------------------------------------------
# Cross-account access
# ---------------------------------------------------------------------------


def test_a_user_sees_only_their_own_audit_events(api_client, db_session):
    from fastapi.testclient import TestClient

    from skincaresync.api import app

    register_and_verify(api_client, "first@example.com")
    first = TestClient(app, base_url="http://testserver")
    first.post("/api/auth/login", json={"email": "first@example.com", "password": PASSWORD})

    register_and_verify(api_client, "second@example.com")
    sign_in(api_client, "second@example.com")

    events = api_client.get("/api/auth/events").json()
    assert events
    # Every event belongs to the caller; nothing from the other account leaks.
    assert all("first@example.com" not in str(event) for event in events)


def test_a_user_sees_only_their_own_sessions(api_client, db_session):
    from fastapi.testclient import TestClient

    from skincaresync.api import app

    register_and_verify(api_client, "owner2@example.com")
    other = TestClient(app, base_url="http://testserver")
    other.post("/api/auth/login", json={"email": "owner2@example.com", "password": PASSWORD})

    register_and_verify(api_client, "nosy@example.com")
    sign_in(api_client, "nosy@example.com")

    assert len(api_client.get("/api/auth/sessions").json()) == 1


# ---------------------------------------------------------------------------
# CSRF
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "path,body",
    [
        ("/api/auth/logout-all", None),
        ("/api/auth/deactivate", None),
        ("/api/auth/change-password", {"current_password": PASSWORD, "password": "a new passphrase!"}),
    ],
)
def test_state_changing_routes_require_a_csrf_token(api_client, path, body):
    register_and_verify(api_client)
    sign_in(api_client)

    response = api_client.post(path, json=body)
    assert response.status_code == 403


def test_a_mismatched_csrf_token_is_rejected(api_client):
    register_and_verify(api_client)
    sign_in(api_client)

    response = api_client.post(
        "/api/auth/logout-all", headers={"X-CSRF-Token": "not-the-right-token"}
    )
    assert response.status_code == 403


def test_the_analysis_endpoint_is_csrf_protected(api_client):
    register_and_verify(api_client)
    sign_in(api_client)
    body = {
        "skin_profile": {"skin_type": "normal", "concerns": []},
        "am_products": [
            {"brand": "E", "name": "A", "raw_ingredient_list": "Aqua, Glycerin"},
            {"brand": "E", "name": "B", "raw_ingredient_list": "Aqua, Retinol"},
        ],
        "pm_products": [],
    }
    assert api_client.post("/api/analyze", json=body).status_code == 403


def test_safe_methods_need_no_csrf_token(api_client):
    register_and_verify(api_client)
    sign_in(api_client)
    assert api_client.get("/api/auth/me").status_code == 200


def test_anonymous_endpoints_are_csrf_exempt(api_client):
    """There is no session to ride, so a token would add nothing."""
    assert api_client.post(
        "/api/auth/forgot-password", json={"email": "nobody@example.com"}
    ).status_code == 200


# ---------------------------------------------------------------------------
# Open redirect
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "candidate",
    [
        "https://evil.example/steal",
        "//evil.example",
        "/\\evil.example",
        "http://evil.example",
        "javascript:alert(1)",
        "  https://evil.example",
        "/path\r\nSet-Cookie: x=1",
        "\\\\evil.example",
        None,
        "",
        "not-absolute",
    ],
)
def test_unsafe_redirect_targets_fall_back_to_the_root(candidate):
    assert safe_redirect_path(candidate) == "/"


@pytest.mark.parametrize(
    "candidate",
    ["/", "/account/security", "/catalog?q=retinol", "/report#top"],
)
def test_site_relative_redirect_targets_are_preserved(candidate):
    assert safe_redirect_path(candidate) == candidate


def test_sign_in_never_redirects_off_site(api_client):
    register_and_verify(api_client)
    response = api_client.post(
        "/api/auth/login",
        json={
            "email": "alice@example.com",
            "password": PASSWORD,
            "next": "https://evil.example/harvest",
        },
    )
    assert response.status_code == 200
    assert response.json()["redirect_to"] == "/"


def test_sign_in_preserves_an_internal_destination(api_client):
    register_and_verify(api_client)
    response = api_client.post(
        "/api/auth/login",
        json={"email": "alice@example.com", "password": PASSWORD, "next": "/account/security"},
    )
    assert response.json()["redirect_to"] == "/account/security"


# ---------------------------------------------------------------------------
# Rate limiting
# ---------------------------------------------------------------------------


def test_sign_in_is_rate_limited(api_client, monkeypatch):
    from skincaresync.auth import routes

    monkeypatch.setattr(routes._login_limiter, "limit", 3)
    routes._login_limiter.reset()
    register_and_verify(api_client, "limited@example.com")

    statuses = [
        api_client.post(
            "/api/auth/login", json={"email": "limited@example.com", "password": "wrong pass!!"}
        ).status_code
        for _ in range(5)
    ]

    assert statuses[:3] == [401, 401, 401]
    assert statuses[3:] == [429, 429]


def test_registration_is_rate_limited(api_client, monkeypatch):
    from skincaresync.auth import routes

    monkeypatch.setattr(routes._register_limiter, "limit", 2)
    routes._register_limiter.reset()

    statuses = [
        api_client.post(
            "/api/auth/register",
            json={"email": f"user{i}@example.com", "password": PASSWORD},
        ).status_code
        for i in range(4)
    ]
    assert statuses == [200, 200, 429, 429]


def test_password_reset_is_rate_limited(api_client, monkeypatch):
    from skincaresync.auth import routes

    monkeypatch.setattr(routes._email_limiter, "limit", 2)
    routes._email_limiter.reset()

    statuses = [
        api_client.post(
            "/api/auth/forgot-password", json={"email": "someone@example.com"}
        ).status_code
        for _ in range(4)
    ]
    assert statuses == [200, 200, 429, 429]


def test_a_rate_limited_response_says_when_to_retry(api_client, monkeypatch):
    from skincaresync.auth import routes

    monkeypatch.setattr(routes._login_limiter, "limit", 1)
    routes._login_limiter.reset()
    api_client.post("/api/auth/login", json={"email": "a@example.com", "password": PASSWORD})
    response = api_client.post(
        "/api/auth/login", json={"email": "a@example.com", "password": PASSWORD}
    )

    assert response.status_code == 429
    assert int(response.headers["retry-after"]) >= 1


# ---------------------------------------------------------------------------
# Configuration safety
# ---------------------------------------------------------------------------


def test_production_rejects_an_insecure_configuration(monkeypatch):
    """A misconfigured deploy must fail at startup, not leak quietly."""
    from skincaresync import config

    monkeypatch.setenv("SKINCARESYNC_ENV", "production")
    monkeypatch.setenv("APP_BASE_URL", "http://app.example.com")  # not https
    monkeypatch.setenv("SESSION_COOKIE_SECURE", "false")
    monkeypatch.setenv("EMAIL_PROVIDER", "console")
    monkeypatch.setenv("AUTH_DEV_ECHO_TOKENS", "1")
    config.reset_settings_cache()

    with pytest.raises(config.ConfigError) as excinfo:
        config.get_settings()

    message = str(excinfo.value)
    assert "https" in message
    assert "SESSION_COOKIE_SECURE" in message
    assert "console" in message
    config.reset_settings_cache()


def test_development_token_echo_cannot_be_enabled_in_production(monkeypatch):
    from skincaresync import config

    monkeypatch.setenv("SKINCARESYNC_ENV", "production")
    monkeypatch.setenv("APP_BASE_URL", "https://app.example.com")
    monkeypatch.setenv("API_BASE_URL", "https://api.example.com")
    monkeypatch.setenv("SESSION_COOKIE_SECURE", "true")
    monkeypatch.setenv("EMAIL_PROVIDER", "smtp")
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    monkeypatch.setenv("AUTH_DEV_ECHO_TOKENS", "1")
    config.reset_settings_cache()

    settings = config.get_settings()
    # Forced off regardless of what the environment asked for.
    assert settings.dev_echo_tokens is False
    config.reset_settings_cache()


def test_production_cookies_are_secure(monkeypatch):
    from skincaresync import config

    monkeypatch.setenv("SKINCARESYNC_ENV", "production")
    monkeypatch.setenv("APP_BASE_URL", "https://app.example.com")
    monkeypatch.setenv("API_BASE_URL", "https://api.example.com")
    monkeypatch.setenv("EMAIL_PROVIDER", "smtp")
    monkeypatch.setenv("SMTP_HOST", "smtp.example.com")
    monkeypatch.delenv("SESSION_COOKIE_SECURE", raising=False)
    config.reset_settings_cache()

    settings = config.get_settings()
    assert settings.cookie_secure is True
    assert settings.is_production is True
    config.reset_settings_cache()


def test_samesite_none_requires_secure(monkeypatch):
    from skincaresync import config

    monkeypatch.setenv("SKINCARESYNC_ENV", "development")
    monkeypatch.setenv("SESSION_COOKIE_SAMESITE", "none")
    monkeypatch.setenv("SESSION_COOKIE_SECURE", "false")
    config.reset_settings_cache()

    with pytest.raises(config.ConfigError, match="SameSite=none|SESSION_COOKIE_SAMESITE"):
        config.get_settings()
    config.reset_settings_cache()


@pytest.mark.parametrize("base_url", ["not-a-url", "ftp://example.com", "", "//evil.example"])
def test_invalid_base_urls_are_rejected(monkeypatch, base_url):
    from skincaresync import config

    monkeypatch.setenv("SKINCARESYNC_ENV", "development")
    monkeypatch.setenv("APP_BASE_URL", base_url)
    config.reset_settings_cache()

    with pytest.raises(config.ConfigError):
        config.get_settings()
    config.reset_settings_cache()


def test_a_trailing_slash_in_the_base_url_is_normalized_away(monkeypatch):
    """Otherwise every generated link would carry a double slash."""
    from skincaresync import config

    monkeypatch.setenv("SKINCARESYNC_ENV", "development")
    monkeypatch.setenv("APP_BASE_URL", "https://app.example.com/")
    config.reset_settings_cache()

    assert config.get_settings().app_base_url == "https://app.example.com"
    config.reset_settings_cache()


# ---------------------------------------------------------------------------
# Account lifecycle
# ---------------------------------------------------------------------------


def test_deactivation_signs_the_user_out_and_blocks_sign_in(api_client, db_session):
    register_and_verify(api_client, "quitter@example.com")
    csrf = sign_in(api_client, "quitter@example.com")

    response = api_client.post("/api/auth/deactivate", headers={"X-CSRF-Token": csrf})

    assert response.status_code == 200
    assert api_client.get("/api/auth/me").status_code == 401
    assert api_client.post(
        "/api/auth/login", json={"email": "quitter@example.com", "password": PASSWORD}
    ).status_code == 401


def test_deletion_requires_the_current_password(api_client):
    register_and_verify(api_client, "keeper@example.com")
    csrf = sign_in(api_client, "keeper@example.com")

    response = api_client.post(
        "/api/auth/delete",
        json={"current_password": "wrong password!!", "confirm": "DELETE"},
        headers={"X-CSRF-Token": csrf},
    )

    assert response.status_code == 400
    assert api_client.get("/api/auth/me").status_code == 200


def test_deletion_requires_typed_confirmation(api_client):
    register_and_verify(api_client, "careful@example.com")
    csrf = sign_in(api_client, "careful@example.com")

    assert api_client.post(
        "/api/auth/delete",
        json={"current_password": PASSWORD, "confirm": "yes"},
        headers={"X-CSRF-Token": csrf},
    ).status_code == 422


def test_deletion_removes_personal_data_but_keeps_the_audit_trail(api_client, db_session):
    register_and_verify(api_client, "gone@example.com")
    csrf = sign_in(api_client, "gone@example.com")
    user_id = db_session.scalar(
        select(User).where(User.email_normalized == "gone@example.com")
    ).user_id

    response = api_client.post(
        "/api/auth/delete",
        json={"current_password": PASSWORD, "confirm": "DELETE"},
        headers={"X-CSRF-Token": csrf},
    )

    assert response.status_code == 200
    user = db_session.get(User, user_id)
    assert user.status == "deleted"
    assert "gone@example.com" not in user.email
    assert user.display_name is None
    # NULL rather than a sentinel string: nothing can authenticate against a
    # missing hash, and there is no placeholder to be compared by accident.
    assert user.password_hash is None
    assert api_client.get("/api/auth/me").status_code == 401
    # The audit history survives.
    assert service.list_auth_events(db_session, user)


def test_a_deleted_account_frees_its_address_for_reuse(api_client, db_session):
    register_and_verify(api_client, "recycle@example.com")
    csrf = sign_in(api_client, "recycle@example.com")
    api_client.post(
        "/api/auth/delete",
        json={"current_password": PASSWORD, "confirm": "DELETE"},
        headers={"X-CSRF-Token": csrf},
    )

    again = api_client.post(
        "/api/auth/register", json={"email": "recycle@example.com", "password": PASSWORD}
    )
    assert again.status_code == 200
    assert again.json()["dev_token"], "a brand-new account should get a verification link"
