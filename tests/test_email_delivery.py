"""Email delivery: the Resend provider, and mail failures that must not break auth.

On Railway below the Pro plan outbound SMTP is blocked, so every send failed --
and because sign-up sent its confirmation email inside the request, the failure
rolled the new account back and answered 500. Forgot-password failed the same
way, but only for addresses that have an account, which told a caller who is
registered.
"""

from __future__ import annotations

import json
import logging

import httpx
import pytest
from sqlalchemy import select

from skincaresync import emailing
from skincaresync.auth.models import User
from skincaresync.auth.routes import GENERIC_EMAIL_SENT
from skincaresync.emailing import (
    EmailDeliveryError,
    OutboundEmail,
    ResendEmailSender,
    build_sender,
    deliver,
)
from tests.test_auth_accounts import PASSWORD, register

TOKEN = "SECRETTOKEN0123456789abcdef"
MESSAGE = OutboundEmail(
    to="alice@example.com",
    subject="Confirm your email",
    text_body=f"Open https://app.example.com/verify-email?token={TOKEN}",
    html_body=f'<a href="https://app.example.com/verify-email?token={TOKEN}">Confirm</a>',
)


class FailingSender:
    """Stands in for a provider that is unreachable or rejects everything."""

    def __init__(self) -> None:
        self.attempts = 0

    def send(self, message) -> None:
        self.attempts += 1
        raise OSError("[Errno 101] Network is unreachable")


@pytest.fixture
def failing_mail(api_client):
    sender = FailingSender()
    emailing.set_sender(sender)
    yield sender
    emailing.set_sender(None)


def _settings(**overrides):
    from skincaresync.config import Settings

    base = dict(
        environment="development",
        app_base_url="https://app.example.com",
        api_base_url="https://app.example.com",
        session_cookie_name="s",
        csrf_cookie_name="c",
        cookie_secure=True,
        cookie_samesite="lax",
        cookie_domain=None,
        session_idle_max_age_seconds=1,
        session_absolute_max_age_seconds=1,
        email_verification_ttl_seconds=3600,
        password_reset_ttl_seconds=3600,
        email_provider="resend",
        email_from="SkincareSync <no-reply@skincaresync.com>",
        smtp_host=None,
        smtp_port=587,
        smtp_username=None,
        resend_api_key="re_test_key",
    )
    base.update(overrides)
    return Settings(**base)


# --- the Resend provider ------------------------------------------------------


def test_resend_sends_the_message_to_the_api():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["auth"] = request.headers["authorization"]
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json={"id": "abc"})

    ResendEmailSender(_settings(), transport=httpx.MockTransport(handler)).send(MESSAGE)

    assert seen["url"] == "https://api.resend.com/emails"
    assert seen["auth"] == "Bearer re_test_key"
    assert seen["body"]["from"] == "SkincareSync <no-reply@skincaresync.com>"
    assert seen["body"]["to"] == ["alice@example.com"]
    assert seen["body"]["subject"] == MESSAGE.subject
    assert seen["body"]["text"] == MESSAGE.text_body
    assert seen["body"]["html"] == MESSAGE.html_body


def test_resend_rejection_carries_the_reason_but_not_the_key():
    def handler(request):
        return httpx.Response(403, json={"message": "The skincaresync.com domain is not verified."})

    sender = ResendEmailSender(_settings(), transport=httpx.MockTransport(handler))
    with pytest.raises(EmailDeliveryError) as excinfo:
        sender.send(MESSAGE)

    assert "403" in str(excinfo.value)
    assert "not verified" in str(excinfo.value)
    assert "re_test_key" not in str(excinfo.value)


def test_resend_settings_hide_the_key_from_repr():
    assert "re_test_key" not in repr(_settings())


def test_build_sender_selects_resend():
    assert isinstance(build_sender(_settings()), ResendEmailSender)


# --- configuration --------------------------------------------------------------


def _production_env(monkeypatch, **env):
    from skincaresync import config

    for key, value in {
        "SKINCARESYNC_ENV": "production",
        "APP_BASE_URL": "https://skincaresync.com",
        "API_BASE_URL": "https://skincaresync.com",
        "EMAIL_PROVIDER": "resend",
        **env,
    }.items():
        monkeypatch.setenv(key, value)
    monkeypatch.delenv("AUTH_DEV_ECHO_TOKENS", raising=False)
    monkeypatch.delenv("SESSION_COOKIE_SECURE", raising=False)
    config.reset_settings_cache()
    return config


def test_production_resend_requires_an_api_key(monkeypatch):
    config = _production_env(monkeypatch)
    monkeypatch.delenv("RESEND_API_KEY", raising=False)
    try:
        with pytest.raises(config.ConfigError, match="RESEND_API_KEY"):
            config.get_settings()
    finally:
        config.reset_settings_cache()


def test_production_resend_with_a_key_starts(monkeypatch):
    config = _production_env(monkeypatch, RESEND_API_KEY="re_live_example")
    try:
        assert config.get_settings().email_provider == "resend"
    finally:
        config.reset_settings_cache()


def test_an_unknown_provider_is_refused_at_startup(monkeypatch):
    from skincaresync import config

    monkeypatch.setenv("SKINCARESYNC_ENV", "development")
    monkeypatch.setenv("EMAIL_PROVIDER", "sendgird")
    config.reset_settings_cache()
    try:
        with pytest.raises(config.ConfigError, match="EMAIL_PROVIDER"):
            config.get_settings()
    finally:
        config.reset_settings_cache()


# --- a failed send is logged, not raised -------------------------------------------


def test_deliver_reports_failure_without_logging_the_token(caplog):
    emailing.set_sender(FailingSender())
    try:
        with caplog.at_level(logging.ERROR, logger="skincaresync.emailing.sender"):
            assert deliver(MESSAGE) is False
    finally:
        emailing.set_sender(None)

    assert "Network is unreachable" in caplog.text
    assert "a***@example.com" in caplog.text
    assert TOKEN not in caplog.text
    assert "alice@example.com" not in caplog.text


def test_registration_survives_a_mail_outage(api_client, failing_mail, db_session):
    response = register(api_client)

    assert response.status_code == 200, response.text
    assert response.json()["message"] == GENERIC_EMAIL_SENT
    assert failing_mail.attempts == 1
    user = db_session.scalar(select(User).where(User.email_normalized == "alice@example.com"))
    assert user is not None, "the account must not be rolled back with the failed email"

    login = api_client.post(
        "/api/auth/login", json={"email": "alice@example.com", "password": PASSWORD}
    )
    assert login.status_code == 200, login.text


def test_forgot_password_answers_the_same_for_known_and_unknown_addresses_in_an_outage(
    api_client, failing_mail
):
    register(api_client)
    known = api_client.post("/api/auth/forgot-password", json={"email": "alice@example.com"})
    unknown = api_client.post("/api/auth/forgot-password", json={"email": "nobody@example.com"})

    assert known.status_code == unknown.status_code == 200
    assert known.json()["message"] == unknown.json()["message"]
