"""Session lifecycle: creation, expiry, revocation, sign-out."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from skincaresync.auth.models import UserSession, utcnow
from tests.test_auth_accounts import PASSWORD, STRONG, register_and_verify
from tests.test_auth_password import sign_in


def second_client(api_client, db_session):
    """A second, independent client sharing the same test database session.

    Stands in for a second device: its own cookie jar, same account.
    """
    from fastapi.testclient import TestClient

    from skincaresync.api import app

    return TestClient(app, base_url="http://testserver")


def test_signing_in_creates_a_session(api_client, db_session):
    register_and_verify(api_client)
    sign_in(api_client)

    sessions = db_session.scalars(select(UserSession)).all()
    assert len(sessions) == 1
    assert sessions[0].revoked_at is None


def test_the_session_token_is_not_stored_in_the_database(api_client, db_session):
    register_and_verify(api_client)
    sign_in(api_client)
    cookie = api_client.cookies.get("skincaresync_session")

    session = db_session.scalar(select(UserSession))
    assert cookie is not None
    # Stored as a SHA-256 digest, so a database dump cannot be replayed.
    assert isinstance(session.token_hash, (bytes, memoryview))
    assert len(bytes(session.token_hash)) == 32
    assert cookie.encode() not in bytes(session.token_hash)


def test_the_session_cookie_is_httponly(api_client):
    register_and_verify(api_client)
    response = api_client.post(
        "/api/auth/login", json={"email": "alice@example.com", "password": PASSWORD}
    )
    cookie_headers = " ".join(response.headers.get_list("set-cookie"))
    assert "skincaresync_session" in cookie_headers
    assert "HttpOnly" in cookie_headers
    assert "SameSite=lax" in cookie_headers.lower() or "samesite=lax" in cookie_headers.lower()


def test_the_csrf_cookie_is_readable_by_script(api_client):
    """Deliberately not HttpOnly: double-submit needs the page to read it."""
    register_and_verify(api_client)
    response = api_client.post(
        "/api/auth/login", json={"email": "alice@example.com", "password": PASSWORD}
    )
    csrf_header = next(
        h for h in response.headers.get_list("set-cookie") if "skincaresync_csrf" in h
    )
    assert "HttpOnly" not in csrf_header


def test_signing_out_revokes_the_session(api_client, db_session):
    register_and_verify(api_client)
    csrf = sign_in(api_client)

    response = api_client.post("/api/auth/logout", headers={"X-CSRF-Token": csrf})

    assert response.status_code == 200
    assert api_client.get("/api/auth/me").status_code == 401
    assert db_session.scalar(select(UserSession)).revoked_at is not None


def test_signing_out_without_a_session_still_succeeds(api_client):
    """A stale tab must not get stuck on an error."""
    assert api_client.post("/api/auth/logout").status_code == 200


def test_a_revoked_session_cannot_be_reused(api_client, db_session):
    register_and_verify(api_client)
    csrf = sign_in(api_client)
    cookie = api_client.cookies.get("skincaresync_session")
    api_client.post("/api/auth/logout", headers={"X-CSRF-Token": csrf})

    # Present the revoked cookie again.
    api_client.cookies.set("skincaresync_session", cookie)
    assert api_client.get("/api/auth/me").status_code == 401


def test_an_expired_session_is_refused(api_client, db_session):
    register_and_verify(api_client)
    sign_in(api_client)
    session = db_session.scalar(select(UserSession))
    session.expires_at = utcnow() - timedelta(seconds=1)
    db_session.flush()

    assert api_client.get("/api/auth/me").status_code == 401


def test_an_idle_session_is_refused(api_client, db_session, auth_env):
    """Separate from absolute expiry: a session untouched for too long dies."""
    register_and_verify(api_client)
    sign_in(api_client)
    session = db_session.scalar(select(UserSession))
    session.last_seen_at = utcnow() - timedelta(
        seconds=auth_env.session_idle_max_age_seconds + 60
    )
    db_session.flush()

    assert api_client.get("/api/auth/me").status_code == 401


def test_an_unknown_session_cookie_is_refused(api_client):
    api_client.cookies.set("skincaresync_session", "a" * 43)
    assert api_client.get("/api/auth/me").status_code == 401


def test_an_oversized_session_cookie_is_refused(api_client):
    api_client.cookies.set("skincaresync_session", "a" * 5000)
    assert api_client.get("/api/auth/me").status_code == 401


def test_sessions_are_listed_for_the_owner(api_client):
    register_and_verify(api_client)
    sign_in(api_client)

    sessions = api_client.get("/api/auth/sessions").json()

    assert len(sessions) == 1
    assert sessions[0]["current"] is True
    # No token material is exposed to the client.
    assert "token_hash" not in sessions[0]
    assert "token" not in str(sessions[0])


def test_sign_out_all_devices_revokes_every_session(api_client, db_session):
    register_and_verify(api_client)
    csrf = sign_in(api_client)
    # A second sign-in from another device.
    other = second_client(api_client, db_session)
    other.post("/api/auth/login", json={"email": "alice@example.com", "password": PASSWORD})
    assert len(db_session.scalars(select(UserSession)).all()) == 2

    response = api_client.post("/api/auth/logout-all", headers={"X-CSRF-Token": csrf})

    assert response.status_code == 200
    assert api_client.get("/api/auth/me").status_code == 401
    assert other.get("/api/auth/me").status_code == 401
    live = [s for s in db_session.scalars(select(UserSession)).all() if s.revoked_at is None]
    assert live == []


def test_revoking_one_session_leaves_the_others(api_client, db_session):
    register_and_verify(api_client)
    other = second_client(api_client, db_session)
    other.post("/api/auth/login", json={"email": "alice@example.com", "password": PASSWORD})
    csrf = sign_in(api_client)

    sessions = api_client.get("/api/auth/sessions").json()
    victim = next(s for s in sessions if not s["current"])
    response = api_client.delete(
        f"/api/auth/sessions/{victim['session_id']}", headers={"X-CSRF-Token": csrf}
    )

    assert response.status_code == 200
    assert api_client.get("/api/auth/me").status_code == 200
    assert other.get("/api/auth/me").status_code == 401


def test_a_user_cannot_revoke_another_users_session(api_client, db_session):
    """Cross-account revocation must be a 404, not a successful sign-out."""
    register_and_verify(api_client, "owner@example.com")
    owner = second_client(api_client, db_session)
    owner.post("/api/auth/login", json={"email": "owner@example.com", "password": PASSWORD})
    owner_session = db_session.scalar(select(UserSession))

    register_and_verify(api_client, "attacker@example.com")
    csrf = sign_in(api_client, "attacker@example.com")

    response = api_client.delete(
        f"/api/auth/sessions/{owner_session.session_id}", headers={"X-CSRF-Token": csrf}
    )

    assert response.status_code == 404
    assert owner.get("/api/auth/me").status_code == 200


def test_changing_a_password_signs_out_other_devices_only(api_client, db_session):
    register_and_verify(api_client)
    other = second_client(api_client, db_session)
    other.post("/api/auth/login", json={"email": "alice@example.com", "password": PASSWORD})
    csrf = sign_in(api_client)

    api_client.post(
        "/api/auth/change-password",
        json={"current_password": PASSWORD, "password": STRONG},
        headers={"X-CSRF-Token": csrf},
    )

    assert api_client.get("/api/auth/me").status_code == 200
    assert other.get("/api/auth/me").status_code == 401
