"""Password reset and password change."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select

from skincaresync.auth.models import AuthToken, User, utcnow
from skincaresync.auth.routes import GENERIC_RESET_SENT
from tests.test_auth_accounts import PASSWORD, STRONG, register, register_and_verify


def sign_in(client, email="alice@example.com", password=PASSWORD):
    response = client.post("/api/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    return response.json()["csrf_token"]


def request_reset(client, email="alice@example.com") -> str:
    response = client.post("/api/auth/forgot-password", json={"email": email})
    assert response.status_code == 200
    return response.json()["dev_token"]


# ---------------------------------------------------------------------------
# Forgot password
# ---------------------------------------------------------------------------


def test_reset_request_for_an_existing_account_sends_a_link(api_client, mailbox):
    register_and_verify(api_client)
    mailbox.clear()

    response = api_client.post("/api/auth/forgot-password", json={"email": "alice@example.com"})

    assert response.status_code == 200
    assert response.json()["message"] == GENERIC_RESET_SENT
    assert len(mailbox.messages) == 1
    assert "/reset-password?token=" in mailbox.last.text_body


def test_reset_request_for_an_unknown_account_looks_identical(api_client, mailbox):
    """Same status, same body, no mail. Otherwise this endpoint enumerates."""
    register_and_verify(api_client, "known@example.com")
    known = api_client.post("/api/auth/forgot-password", json={"email": "known@example.com"})
    mailbox.clear()
    unknown = api_client.post("/api/auth/forgot-password", json={"email": "ghost@example.com"})

    assert known.status_code == unknown.status_code == 200
    assert known.json()["message"] == unknown.json()["message"] == GENERIC_RESET_SENT
    assert mailbox.messages == []


def test_reset_email_is_not_built_from_the_request_host(api_client, mailbox, auth_env):
    register_and_verify(api_client)
    mailbox.clear()
    api_client.post(
        "/api/auth/forgot-password",
        json={"email": "alice@example.com"},
        headers={"Host": "attacker.example", "X-Forwarded-Host": "attacker.example"},
    )
    assert "attacker.example" not in mailbox.last.text_body
    assert auth_env.app_base_url in mailbox.last.text_body


# ---------------------------------------------------------------------------
# Completing a reset
# ---------------------------------------------------------------------------


def test_reset_sets_the_new_password(api_client):
    register_and_verify(api_client)
    token = request_reset(api_client)

    response = api_client.post(
        "/api/auth/reset-password", json={"token": token, "password": STRONG}
    )

    assert response.status_code == 200
    assert api_client.post(
        "/api/auth/login", json={"email": "alice@example.com", "password": STRONG}
    ).status_code == 200
    assert api_client.post(
        "/api/auth/login", json={"email": "alice@example.com", "password": PASSWORD}
    ).status_code == 401


def test_a_reset_token_works_only_once(api_client):
    register_and_verify(api_client)
    token = request_reset(api_client)
    api_client.post("/api/auth/reset-password", json={"token": token, "password": STRONG})

    replay = api_client.post(
        "/api/auth/reset-password", json={"token": token, "password": "yet another passphrase"}
    )
    assert replay.status_code == 400


def test_an_expired_reset_token_is_refused(api_client, db_session):
    register_and_verify(api_client)
    token = request_reset(api_client)
    row = db_session.scalar(
        select(AuthToken).where(AuthToken.purpose == "password_reset")
    )
    row.created_at = utcnow() - timedelta(hours=4)
    row.expires_at = utcnow() - timedelta(hours=3)
    db_session.flush()

    response = api_client.post(
        "/api/auth/reset-password", json={"token": token, "password": STRONG}
    )
    assert response.status_code == 400
    assert "expired" in response.json()["detail"].lower()


def test_an_invalid_reset_token_is_refused(api_client):
    response = api_client.post(
        "/api/auth/reset-password",
        json={"token": "totally-made-up-token-value", "password": STRONG},
    )
    assert response.status_code == 400


def test_requesting_a_second_reset_invalidates_the_first_link(api_client):
    register_and_verify(api_client)
    first = request_reset(api_client)
    second = request_reset(api_client)

    assert first != second
    assert api_client.post(
        "/api/auth/reset-password", json={"token": first, "password": STRONG}
    ).status_code == 400
    assert api_client.post(
        "/api/auth/reset-password", json={"token": second, "password": STRONG}
    ).status_code == 200


def test_a_reset_link_issued_before_a_completed_reset_is_dead(api_client):
    """Two links outstanding; using one must kill the other."""
    register_and_verify(api_client)
    stale = request_reset(api_client)
    fresh = request_reset(api_client)
    api_client.post("/api/auth/reset-password", json={"token": fresh, "password": STRONG})

    assert api_client.post(
        "/api/auth/reset-password", json={"token": stale, "password": "a third passphrase!!"}
    ).status_code == 400


def test_reset_signs_out_every_device(api_client, db_session):
    """The point of a reset: an attacker's live session dies."""
    register_and_verify(api_client)
    sign_in(api_client)
    assert api_client.get("/api/auth/me").status_code == 200

    token = request_reset(api_client)
    api_client.post("/api/auth/reset-password", json={"token": token, "password": STRONG})

    assert api_client.get("/api/auth/me").status_code == 401


def test_reset_confirms_an_unverified_address(api_client, db_session):
    """Completing a reset proves control of the mailbox."""
    token = register(api_client).json()["dev_token"]
    assert token
    reset_token = request_reset(api_client)
    api_client.post("/api/auth/reset-password", json={"token": reset_token, "password": STRONG})

    user = db_session.scalar(select(User).where(User.email_normalized == "alice@example.com"))
    assert user.email_verified_at is not None


def test_reset_rejects_a_weak_new_password(api_client):
    register_and_verify(api_client)
    token = request_reset(api_client)
    assert api_client.post(
        "/api/auth/reset-password", json={"token": token, "password": "password123"}
    ).status_code == 422


def test_a_notification_email_follows_a_reset(api_client, mailbox):
    register_and_verify(api_client)
    token = request_reset(api_client)
    mailbox.clear()
    api_client.post("/api/auth/reset-password", json={"token": token, "password": STRONG})

    assert any("was changed" in m.subject for m in mailbox.messages)


# ---------------------------------------------------------------------------
# Changing a password while signed in
# ---------------------------------------------------------------------------


def test_change_password_requires_the_current_one(api_client):
    register_and_verify(api_client)
    csrf = sign_in(api_client)

    response = api_client.post(
        "/api/auth/change-password",
        json={"current_password": "not the right one", "password": STRONG},
        headers={"X-CSRF-Token": csrf},
    )
    assert response.status_code == 400
    # The old password still works, so nothing changed.
    assert api_client.post(
        "/api/auth/login", json={"email": "alice@example.com", "password": PASSWORD}
    ).status_code == 200


def test_change_password_updates_the_credential(api_client):
    register_and_verify(api_client)
    csrf = sign_in(api_client)

    response = api_client.post(
        "/api/auth/change-password",
        json={"current_password": PASSWORD, "password": STRONG},
        headers={"X-CSRF-Token": csrf},
    )

    assert response.status_code == 200
    assert api_client.post(
        "/api/auth/login", json={"email": "alice@example.com", "password": STRONG}
    ).status_code == 200


def test_change_password_keeps_the_current_session_alive(api_client):
    """The user should not be signed out of the page they are standing on."""
    register_and_verify(api_client)
    csrf = sign_in(api_client)

    api_client.post(
        "/api/auth/change-password",
        json={"current_password": PASSWORD, "password": STRONG},
        headers={"X-CSRF-Token": csrf},
    )

    assert api_client.get("/api/auth/me").status_code == 200


def test_change_password_rejects_a_weak_new_password(api_client):
    register_and_verify(api_client)
    csrf = sign_in(api_client)
    assert api_client.post(
        "/api/auth/change-password",
        json={"current_password": PASSWORD, "password": "letmein"},
        headers={"X-CSRF-Token": csrf},
    ).status_code == 422
