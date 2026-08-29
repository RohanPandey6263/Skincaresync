"""PostgreSQL connection pooling.

Every request path checks a connection out of a process-wide pool. Three
properties matter under load, and none of them is psycopg2's default:

* `getconn()` raises `PoolError` the instant the pool is empty rather than
  waiting, which turns a brief traffic spike into a wall of 500s. We wait for a
  slot up to `PGPOOL_WAIT_SECONDS` and raise a typed `PoolTimeout` after that,
  so the API can answer 503 with a Retry-After instead.
* Without `statement_timeout` a single pathological query pins a pool slot
  indefinitely. It is set server-side at connect time so it survives reconnects.
* Without `connect_timeout` an unreachable host blocks the worker for the OS TCP
  timeout (~2 minutes on Linux).
"""

import atexit
import getpass
import logging
import os
import threading
import time
from contextlib import contextmanager

import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor

logger = logging.getLogger(__name__)

STATEMENT_TIMEOUT_MS = int(os.getenv("PGSTATEMENT_TIMEOUT_MS", "15000"))
CONNECT_TIMEOUT_SECONDS = int(os.getenv("PGCONNECT_TIMEOUT", "5"))
POOL_WAIT_SECONDS = float(os.getenv("PGPOOL_WAIT_SECONDS", "3"))
_POOL_POLL_SECONDS = 0.01


class PoolTimeout(RuntimeError):
    """No pooled connection became free within `POOL_WAIT_SECONDS`."""


def connection_kwargs() -> dict:
    """Connection settings, all overridable by the standard libpq env vars.

    `PGUSER` falls back to the OS account rather than a hardcoded name so the
    same code runs unchanged on a developer laptop and in a container.
    """
    return {
        "host": os.getenv("PGHOST", "localhost"),
        "port": os.getenv("PGPORT"),
        "dbname": os.getenv("PGDATABASE", "postgres"),
        "user": os.getenv("PGUSER") or getpass.getuser(),
        "password": os.getenv("PGPASSWORD") or None,
        "connect_timeout": CONNECT_TIMEOUT_SECONDS,
        "options": f"-c statement_timeout={STATEMENT_TIMEOUT_MS}",
    }


_pool: pool.ThreadedConnectionPool | None = None
_pool_lock = threading.Lock()


def _get_pool() -> pool.ThreadedConnectionPool:
    """Lazily create the process-wide connection pool.

    Ingredient autocomplete issues a query per keystroke, so paying TCP and
    authentication setup per request is the dominant cost at that latency. The
    pool is created on first use rather than at import so that tests and CLI
    scripts that never touch the database do not open connections.
    """
    global _pool
    if _pool is not None:
        return _pool

    with _pool_lock:
        if _pool is None:
            kwargs = {k: v for k, v in connection_kwargs().items() if v}
            _pool = pool.ThreadedConnectionPool(
                minconn=int(os.getenv("PGPOOL_MIN", "1")),
                maxconn=int(os.getenv("PGPOOL_MAX", "10")),
                **kwargs,
            )
    return _pool


def close_pool() -> None:
    global _pool
    with _pool_lock:
        if _pool is not None:
            _pool.closeall()
            _pool = None


atexit.register(close_pool)


def _checkout(connection_pool: pool.ThreadedConnectionPool):
    """Wait for a free connection instead of failing the moment the pool is full."""
    deadline = time.monotonic() + POOL_WAIT_SECONDS
    while True:
        try:
            return connection_pool.getconn()
        except pool.PoolError:
            if connection_pool.closed:
                raise
            if time.monotonic() >= deadline:
                logger.error(
                    "connection pool exhausted; no slot free after %.1fs", POOL_WAIT_SECONDS
                )
                raise PoolTimeout(
                    "No database connection became available. The service is overloaded."
                ) from None
            time.sleep(_POOL_POLL_SECONDS)


@contextmanager
def get_conn():
    """Check a connection out of the pool for the duration of the block."""
    connection_pool = _get_pool()
    conn = _checkout(connection_pool)
    try:
        yield conn
        conn.commit()
    except Exception:
        # A broken connection must not be reused; drop it from the pool.
        try:
            conn.rollback()
        except psycopg2.Error:
            connection_pool.putconn(conn, close=True)
            conn = None
        raise
    finally:
        if conn is not None:
            connection_pool.putconn(conn)


@contextmanager
def get_cursor(cursor_factory=RealDictCursor):
    with get_conn() as conn:
        with conn.cursor(cursor_factory=cursor_factory) as cur:
            yield cur
