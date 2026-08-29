import atexit
import os
import threading
from contextlib import contextmanager

import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor


def connection_kwargs() -> dict:
    return {
        "host": os.getenv("PGHOST", "localhost"),
        "dbname": os.getenv("PGDATABASE", "postgres"),
        "user": os.getenv("PGUSER", "rohanpandey"),
        "password": os.getenv("PGPASSWORD") or None,
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


@contextmanager
def get_conn():
    """Check a connection out of the pool for the duration of the block."""
    connection_pool = _get_pool()
    conn = connection_pool.getconn()
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
