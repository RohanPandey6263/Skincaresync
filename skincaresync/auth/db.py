"""SQLAlchemy engine and session for the authentication domain.

The rest of the application talks to Postgres through raw psycopg2 in
`skincaresync.database`, and deliberately so: the ingredient search leans on
trigram operators, lateral joins and full-text ranking that an ORM would only
obscure. Authentication is the opposite shape -- small, highly relational CRUD
over four tables -- which is what an ORM is good at. Both use the same database
and the same libpq environment variables; only the access style differs.

The schema itself is owned by the numbered SQL migrations, not by these models.
`create_all()` is never called: automatic schema synchronisation would let a
deploy silently reshape production. `tests/test_auth_schema.py` asserts the
models and the migrated database agree, so the two cannot drift apart unnoticed.
"""

from __future__ import annotations

import getpass
import os
from collections.abc import Iterator
from contextlib import contextmanager

from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from sqlalchemy.orm import Session, sessionmaker


def database_url() -> URL:
    """Build the connection URL from the same PG* variables psycopg2 uses."""
    raw_port = os.getenv("PGPORT")
    return URL.create(
        drivername="postgresql+psycopg2",
        username=os.getenv("PGUSER") or getpass.getuser(),
        password=os.getenv("PGPASSWORD") or None,
        host=os.getenv("PGHOST", "localhost"),
        port=int(raw_port) if raw_port else None,
        database=os.getenv("PGDATABASE", "postgres"),
    )


_engine = None
_session_factory: sessionmaker[Session] | None = None


def get_engine():
    """Lazily create the engine, so importing this module opens no connections."""
    global _engine, _session_factory
    if _engine is None:
        _engine = create_engine(
            database_url(),
            pool_size=int(os.getenv("AUTH_POOL_SIZE", "5")),
            max_overflow=int(os.getenv("AUTH_POOL_MAX_OVERFLOW", "5")),
            # Recycle before Postgres or a proxy drops an idle connection, and
            # check liveness on checkout so a restarted database surfaces as a
            # retry rather than an error on the user's request.
            pool_recycle=1800,
            pool_pre_ping=True,
            connect_args={
                "connect_timeout": int(os.getenv("PGCONNECT_TIMEOUT", "5")),
                "options": f"-c statement_timeout={os.getenv('PGSTATEMENT_TIMEOUT_MS', '15000')}",
            },
            future=True,
        )
        _session_factory = sessionmaker(bind=_engine, expire_on_commit=False, future=True)
    return _engine


def get_session_factory() -> sessionmaker[Session]:
    get_engine()
    assert _session_factory is not None
    return _session_factory


def dispose_engine() -> None:
    """Close pooled connections. Used by tests and at shutdown."""
    global _engine, _session_factory
    if _engine is not None:
        _engine.dispose()
    _engine = None
    _session_factory = None


@contextmanager
def session_scope() -> Iterator[Session]:
    """A transactional scope. Commits on success, rolls back on any exception."""
    session = get_session_factory()()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def get_db() -> Iterator[Session]:
    """FastAPI dependency yielding a transactional session."""
    with session_scope() as session:
        yield session
