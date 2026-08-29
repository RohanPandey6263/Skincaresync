"""Registration, email verification and sign-in."""

from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import select

from skincaresync.auth import service
from skincaresync.auth.models import AuthToken, User, utcnow
from skincaresync.auth.routes import GENERIC_EMAIL_SENT

PASSWORD = "correct horse battery staple"
STRONG = "another perfectly fine passphrase"


def register(client, email=" Alice@Example.COM ", password=PASSWORD, **extra):
    body = {"email": email.strip(), "password": password, **extra}
    return client.post("/api/auth/register", json=body)


def register_and_verify(client, email="alice@example.com", password=PASSWORD):
    token = register(client, email=email, password=password).json()["dev_token"]
    client.post("/api/auth/verify-email", json={"token": token})
    return email, password


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------


def test_registration_creates_an_account_and_sends_verification(api_client, mailbox, db_session):
    response = register(api_client)

    assert response.status_code == 200
    assert response.json()["message"] == GENERIC_EMAIL_SENT
    user = db_session.scalar(select(User).where(User.email_normalized == "alice@example.com"))
    assert user is not None
    assert user.email_verified_at is None
    assert user.role == "user"
    assert len(mailbox.messages) == 1


def test_password_is_never_stored_in_plaintext(api_client, db_session):
    register(api_client)
    user = db_session.scalar(select(User).where(User.email_normalized == "alice@example.com"))

    assert PASSWORD not in user.password_hash
    assert user.password_hash.startswith("$argon2id$")


def test_email_is_normalized_for_uniqueness(api_client, db_session):
    """Alice@Example.COM and alice@example.com are one account, not two."""
    register(api_client, email="Alice@Example.COM")
    register(api_client, email="alice@example.com")
    register(api_client, email="  ALICE@EXAMPLE.COM  ")

    users = db_session.scalars(
        select(User).where(User.email_normalized == "alice@example.com")
    ).all()
    assert len(users) == 1
    # Stored lowercased and trimmed, so the stored value and the generated
    # normalized column always agree.
    assert users[0].email == "alice@example.com"


def test_duplicate_registration_is_indistinguishable_from_a_new_one(api_client, mailbox):
    """A different response here would turn registration into an address oracle."""
    first = register(api_client, email="taken@example.com")
    mailbox.clear()
    second = register(api_client, email="taken@example.com")

    assert first.status_code == second.status_code == 200
    assert first.json()["message"] == second.json()["message"] == GENERIC_EMAIL_SENT


def test_registering_an_already_verified_address_sends_nothing_new(api_client, mailbox):
    register_and_verify(api_client, "verified@example.com")
    mailbox.clear()

    response = register(api_client, email="verified@example.com")

    assert response.status_code == 200
    assert response.json()["message"] == GENERIC_EMAIL_SENT
    assert mailbox.messages == []


@pytest.mark.parametrize(
    "email",
    ["not-an-email", "@example.com", "alice@", "alice example.com", "", "a" * 250 + "@x.com"],
)
def test_malformed_emails_are_rejected(api_client, email):
    assert register(api_client, email=email).status_code == 422


@pytest.mark.parametrize(
    "password",
    ["short", "password123", "aaaaaaaaaaaaaaa", "", "        "],
)
def test_weak_passwords_are_rejected(api_client, password):
    assert register(api_client, password=password).status_code == 422


def test_password_at_the_length_boundary(api_client):
    """MIN_PASSWORD_LENGTH is 12: eleven characters is refused, twelve is not."""
    assert register(api_client, email="a@example.com", password="Passphrase1").status_code == 422
    assert register(api_client, email="b@example.com", password="Passphrase12").status_code == 200


def test_display_name_rejects_control_characters(api_client):
    """Control characters can corrupt a log line or an email header."""
    assert register(api_client, display_name="Alice\u0000Smith").status_code == 422
    assert register(api_client, email="c@example.com", display_name="Alice\u001bSmith").status_code == 422


# ---------------------------------------------------------------------------
# Email verification
# ---------------------------------------------------------------------------


def test_verification_marks_the_address_confirmed(api_client, db_session):
    token = register(api_client).json()["dev_token"]

    response = api_client.post("/api/auth/verify-email", json={"token": token})

    assert response.status_code == 200
    user = db_session.scalar(select(User).where(User.email_normalized == "alice@example.com"))
    assert user.email_verified_at is not None


def test_a_verification_token_works_only_once(api_client):
    token = register(api_client).json()["dev_token"]
    api_client.post("/api/auth/verify-email", json={"token": token})

    replay = api_client.post("/api/auth/verify-email", json={"token": token})

    assert replay.status_code == 400
    assert "invalid" in replay.json()["detail"].lower()


def test_an_invalid_verification_token_is_refused(api_client):
    response = api_client.post("/api/auth/verify-email", json={"token": "n0t-a-real-token-value"})
    assert response.status_code == 400


def test_an_expired_verification_token_is_refused(api_client, db_session):
    token = register(api_client).json()["dev_token"]
    row = db_session.scalar(select(AuthToken).where(AuthToken.purpose == "email_verification"))
    # Age the whole row rather than waiting 24 hours. Both timestamps move, so
    # auth_tokens_expires_after_creation still holds.
    row.created_at = utcnow() - timedelta(hours=48)
    row.expires_at = utcnow() - timedelta(hours=24)
    db_session.flush()

    response = api_client.post("/api/auth/verify-email", json={"token": token})
    assert response.status_code == 400
    assert "expired" in response.json()["detail"].lower()


def test_resending_verification_invalidates_the_previous_link(api_client):
    first = register(api_client).json()["dev_token"]
    second = api_client.post(
        "/api/auth/resend-verification", json={"email": "alice@example.com"}
    ).json()["dev_token"]

    assert first != second
    assert api_client.post("/api/auth/verify-email", json={"token": first}).status_code == 400
    assert api_client.post("/api/auth/verify-email", json={"token": second}).status_code == 200


def test_resend_for_an_unknown_address_reveals_nothing(api_client, mailbox):
    response = api_client.post(
        "/api/auth/resend-verification", json={"email": "nobody@example.com"}
    )

    assert response.status_code == 200
    assert response.json()["message"] == GENERIC_EMAIL_SENT
    assert mailbox.messages == []


def test_verification_email_link_uses_the_configured_base_url(api_client, mailbox, auth_env):
    register(api_client)
    assert f"{auth_env.app_base_url}/verify-email?token=" in mailbox.last.text_body


def test_verification_email_is_not_sent_from_an_untrusted_host(api_client, mailbox):
    """A forged Host header must not end up in the emailed link."""
    register(api_client)
    api_client.post(
        "/api/auth/resend-verification",
        json={"email": "alice@example.com"},
        headers={"Host": "evil.example.com", "X-Forwarded-Host": "evil.example.com"},
    )
    assert "evil.example.com" not in mailbox.last.text_body


# ---------------------------------------------------------------------------
# Sign-in
# ---------------------------------------------------------------------------


def test_sign_in_with_valid_credentials(api_client):
    register_and_verify(api_client)

    response = api_client.post(
        "/api/auth/login", json={"email": "alice@example.com", "password": PASSWORD}
    )

    assert response.status_code == 200
    assert response.json()["user"]["email"] == "alice@example.com"
    assert response.json()["csrf_token"]


def test_sign_in_is_case_insensitive_on_email(api_client):
    register_and_verify(api_client, "alice@example.com")

    response = api_client.post(
        "/api/auth/login", json={"email": "  ALICE@Example.com ", "password": PASSWORD}
    )
    assert response.status_code == 200


def test_sign_in_works_before_verification(api_client):
    """Verification gates protected features, not sign-in itself, so a user can
    get back in and request a new link."""
    register(api_client)
    response = api_client.post(
        "/api/auth/login", json={"email": "alice@example.com", "password": PASSWORD}
    )
    assert response.status_code == 200
    assert response.json()["user"]["email_verified"] is False


def test_wrong_password_is_rejected(api_client):
    register_and_verify(api_client)
    response = api_client.post(
        "/api/auth/login", json={"email": "alice@example.com", "password": "wrong password here"}
    )
    assert response.status_code == 401


def test_unknown_and_wrong_password_are_indistinguishable(api_client):
    """Identical status and body, or sign-in becomes an account oracle."""
    register_and_verify(api_client, "real@example.com")

    unknown = api_client.post(
        "/api/auth/login", json={"email": "ghost@example.com", "password": PASSWORD}
    )
    wrong = api_client.post(
        "/api/auth/login", json={"email": "real@example.com", "password": "definitely wrong pw"}
    )

    assert unknown.status_code == wrong.status_code == 401
    assert unknown.json() == wrong.json()


def test_repeated_failures_lock_the_account(api_client, db_session, monkeypatch):
    """Per-account lockout, distinct from the per-address rate limit.

    The address limit is lifted here so the lockout itself is what is measured;
    a distributed attack would come from many addresses and only the lockout
    would stop it.
    """
    from skincaresync.auth import routes

    monkeypatch.setattr(routes._login_limiter, "limit", 10_000)
    register_and_verify(api_client, "target@example.com")

    for _ in range(service.MAX_FAILED_LOGINS):
        api_client.post(
            "/api/auth/login", json={"email": "target@example.com", "password": "wrong password!"}
        )

    user = db_session.scalar(select(User).where(User.email_normalized == "target@example.com"))
    assert user.is_locked()
    # Even the correct password is refused while locked, with the same message.
    blocked = api_client.post(
        "/api/auth/login", json={"email": "target@example.com", "password": PASSWORD}
    )
    assert blocked.status_code == 401


def test_a_successful_sign_in_clears_the_failure_counter(api_client, db_session):
    register_and_verify(api_client, "reset@example.com")
    for _ in range(3):
        api_client.post(
            "/api/auth/login", json={"email": "reset@example.com", "password": "wrong password!"}
        )
    api_client.post("/api/auth/login", json={"email": "reset@example.com", "password": PASSWORD})

    user = db_session.scalar(select(User).where(User.email_normalized == "reset@example.com"))
    assert user.failed_login_count == 0
    assert user.locked_until is None


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"email": "alice@example.com"},
        {"password": PASSWORD},
        {"email": None, "password": None},
        {"email": "alice@example.com", "password": "x" * 2000},
    ],
)
def test_malformed_sign_in_requests_are_rejected(api_client, body):
    assert api_client.post("/api/auth/login", json=body).status_code == 422


# ---------------------------------------------------------------------------
# Audit trail
# ---------------------------------------------------------------------------


def test_security_events_are_recorded_without_secrets(api_client, db_session):
    register_and_verify(api_client, "audited@example.com")
    api_client.post("/api/auth/login", json={"email": "audited@example.com", "password": "nope!!!!!!!!"})
    api_client.post("/api/auth/login", json={"email": "audited@example.com", "password": PASSWORD})

    events = api_client.get("/api/auth/events").json()
    types = [event["event_type"] for event in events]

    assert "register.success" in types
    assert "login.failure" in types
    assert "login.success" in types
    serialized = str(events)
    assert PASSWORD not in serialized
    assert "argon2" not in serialized
