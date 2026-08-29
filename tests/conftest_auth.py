"""Fixtures for the authentication suite.

Auth tests need to write, which the main `conftest.py` forbids against the
development database. They therefore run against a dedicated database,
`skincaresync_test`, created and migrated once per session. Each test then runs
inside a transaction that is rolled back, so tests cannot see each other's rows
and the file can be run in any order.

Create the database once with:

    createdb skincaresync_test
    psql -d skincaresync_test -f migrations/007_auth.sql

The fixtures below do this automatically when `createdb` is on PATH.
"""

from __future__ import annotations

import os
import subprocess
from collections.abc import Iterator
from pathlib import Path

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL
from sqlalchemy.orm import Session, sessionmaker

TEST_DB_NAME = os.getenv("AUTH_TEST_DATABASE", "skincaresync_test")
REPO_ROOT = Path(__file__).resolve().parents[1]
AUTH_MIGRATION = REPO_ROOT / "migrations" / "007_auth.sql"


def _test_database_url() -> URL:
    import getpass

    return URL.create(
        drivername="postgresql+psycopg2",
        username=os.getenv("PGUSER") or getpass.getuser(),
        password=os.getenv("PGPASSWORD") or None,
        host=os.getenv("PGHOST", "localhost"),
        port=int(os.getenv("PGPORT")) if os.getenv("PGPORT") else None,
        database=TEST_DB_NAME,
    )


def _ensure_test_database() -> None:
    """Create and migrate the test database if it is not there yet."""
    subprocess.run(["createdb", TEST_DB_NAME], capture_output=True, check=False)
    result = subprocess.run(
        ["psql", "-q", "-d", TEST_DB_NAME, "-v", "ON_ERROR_STOP=1", "-f", str(AUTH_MIGRATION)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        pytest.skip(f"could not prepare {TEST_DB_NAME}: {result.stderr.strip()[:200]}")


@pytest.fixture(scope="session")
def auth_engine():
    _ensure_test_database()
    engine = create_engine(_test_database_url(), future=True)
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except Exception as exc:  # pragma: no cover - environment dependent
        engine.dispose()
        pytest.skip(f"Postgres test database unavailable: {exc}")

    # Start from empty. Per-test rollback isolates writes made during a test but
    # cannot hide rows committed before the run -- by a live server session or an
    # operator script -- and those would make row-count assertions flap.
    with engine.begin() as connection:
        connection.execute(
            text("TRUNCATE users, user_sessions, auth_tokens, auth_events RESTART IDENTITY CASCADE")
        )

    yield engine
    engine.dispose()


@pytest.fixture
def db_session(auth_engine) -> Iterator[Session]:
    """A session inside a transaction that is rolled back when the test ends.

    The outer transaction is never committed, so anything the code under test
    commits is contained in a SAVEPOINT and discarded with it.
    """
    connection = auth_engine.connect()
    transaction = connection.begin()
    session = sessionmaker(bind=connection, expire_on_commit=False, future=True)()
    # Keep a SAVEPOINT alive across the inner commits the service layer performs.
    nested = connection.begin_nested()

    from sqlalchemy import event

    @event.listens_for(session, "after_transaction_end")
    def _restart_savepoint(sess, trans):  # pragma: no cover - event plumbing
        nonlocal nested
        if not nested.is_active:
            nested = connection.begin_nested()

    try:
        yield session
    finally:
        session.close()
        transaction.rollback()
        connection.close()
