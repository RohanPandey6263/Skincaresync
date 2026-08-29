"""Shared test fixtures.

The suite runs against the developer's real database. Reads are fine; writes are
not. `test_interactions_dataset` alone used to call `analyze_routines` 150+
times, and every one of those recorded rows in `interaction_gaps` and
`parser_unknowns` under the brand "Dataset Test" -- so running the tests
polluted the research backlog the application then displays.

Writes are therefore stubbed for every test by default and recorded in memory so
assertions can inspect them. A test that genuinely needs to write marks itself
with `@pytest.mark.allow_db_writes`.
"""

from __future__ import annotations

import re

import pytest

from skincaresync import engine, parser, product_catalog

# Auth fixtures live in their own module because they need a writable database.
pytest_plugins = ["tests.conftest_auth"]


class RecordedWrites:
    """What the code under test would have persisted."""

    def __init__(self) -> None:
        self.gap_pairs: list[tuple[int, int]] = []
        self.gap_calls = 0
        self.unknown_tokens: list[tuple[str, str]] = []
        self.unknown_calls = 0
        self.upserted: list = []
        self.upsert_calls = 0


@pytest.fixture
def recorded_writes(monkeypatch) -> RecordedWrites:
    """Capture attempted writes instead of performing them."""
    recorded = RecordedWrites()

    def fake_gaps(pairs, skin_profile):
        pairs = list(pairs)
        recorded.gap_pairs.extend(pairs)
        recorded.gap_calls += 1
        return len(pairs)

    def fake_unknowns(unknowns, source_product=None):
        recorded.unknown_tokens.extend(unknowns)
        recorded.unknown_calls += 1

    def fake_upserts(products):
        products = list(products)
        recorded.upserted.extend(products)
        recorded.upsert_calls += 1
        return len(products)

    monkeypatch.setattr(engine, "log_interaction_gaps", fake_gaps)
    monkeypatch.setattr(parser, "log_parser_unknowns", fake_unknowns)
    monkeypatch.setattr(product_catalog, "upsert_products", fake_upserts)
    return recorded


@pytest.fixture(autouse=True)
def block_db_writes(request, monkeypatch):
    """Neutralise every write path unless the test opts in."""
    if request.node.get_closest_marker("allow_db_writes"):
        return
    if "recorded_writes" in request.fixturenames:
        return  # that fixture already installed its own stubs
    monkeypatch.setattr(engine, "log_interaction_gaps", lambda pairs, skin_profile: 0)
    monkeypatch.setattr(parser, "log_parser_unknowns", lambda unknowns, source_product=None: None)
    monkeypatch.setattr(product_catalog, "upsert_products", lambda products: 0)


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "allow_db_writes: test may write to the database"
    )


# ---------------------------------------------------------------------------
# Authentication fixtures
# ---------------------------------------------------------------------------


class CapturingEmailSender:
    """Collects messages instead of sending them, and extracts their links."""

    def __init__(self) -> None:
        self.messages: list = []

    def send(self, message) -> None:
        self.messages.append(message)

    @property
    def last(self):
        assert self.messages, "no email was sent"
        return self.messages[-1]

    def last_token(self) -> str:
        """The token from the most recent message's link."""
        match = re.search(r"[?&]token=([A-Za-z0-9_\-]+)", self.last.text_body)
        assert match, f"no token link in email: {self.last.text_body[:200]}"
        return match.group(1)

    def clear(self) -> None:
        self.messages.clear()


@pytest.fixture
def mailbox(monkeypatch):
    """Capture outbound authentication email. Nothing is delivered."""
    from skincaresync import emailing

    sender = CapturingEmailSender()
    emailing.set_sender(sender)
    yield sender
    emailing.set_sender(None)


@pytest.fixture
def auth_env(monkeypatch):
    """Deterministic auth configuration for tests."""
    from skincaresync import config

    monkeypatch.setenv("SKINCARESYNC_ENV", "development")
    monkeypatch.setenv("APP_BASE_URL", "http://localhost:5173")
    monkeypatch.setenv("API_BASE_URL", "http://localhost:8000")
    monkeypatch.setenv("EMAIL_PROVIDER", "console")
    # Lets tests complete verification and reset flows without a mailbox. The
    # production configuration check refuses this flag outright.
    monkeypatch.setenv("AUTH_DEV_ECHO_TOKENS", "1")
    monkeypatch.setenv("SESSION_COOKIE_SECURE", "false")
    monkeypatch.setenv("SESSION_COOKIE_SAMESITE", "lax")
    config.reset_settings_cache()
    yield config.get_settings()
    config.reset_settings_cache()


@pytest.fixture
def api_client(auth_env, db_session, mailbox):
    """TestClient wired to the rolled-back test session."""
    pytest.importorskip("httpx2", reason="fastapi.testclient needs an HTTP client")
    from fastapi.testclient import TestClient

    from skincaresync.api import app
    from skincaresync.auth.db import get_db
    from skincaresync.auth.routes import reset_rate_limiters

    app.dependency_overrides[get_db] = lambda: db_session
    reset_rate_limiters()
    with TestClient(app, base_url="http://testserver") as client:
        yield client
    app.dependency_overrides.pop(get_db, None)
    reset_rate_limiters()


@pytest.fixture
def admin_client(api_client, db_session):
    """An `api_client` signed in as an administrator.

    The role is set directly rather than through the API because there is no
    self-service path to admin -- deliberately, since a hardcoded or
    self-assignable administrator is a backdoor.
    """
    from sqlalchemy import select

    from skincaresync.auth.models import User, UserRole

    email = "admin-fixture@example.com"
    password = "correct horse battery staple"
    api_client.post("/api/auth/register", json={"email": email, "password": password})
    user = db_session.scalar(select(User).where(User.email_normalized == email))
    user.role = UserRole.ADMIN.value
    db_session.flush()

    response = api_client.post("/api/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    api_client.headers["X-CSRF-Token"] = response.json()["csrf_token"]
    return api_client
