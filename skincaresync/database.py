import os
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor


def connection_kwargs() -> dict:
    return {
        "host": os.getenv("PGHOST", "localhost"),
        "dbname": os.getenv("PGDATABASE", "postgres"),
        "user": os.getenv("PGUSER", "rohanpandey"),
        "password": os.getenv("PGPASSWORD") or None,
    }


@contextmanager
def get_conn():
    kwargs = {key: value for key, value in connection_kwargs().items() if value}
    conn = psycopg2.connect(**kwargs)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


@contextmanager
def get_cursor(cursor_factory=RealDictCursor):
    with get_conn() as conn:
        with conn.cursor(cursor_factory=cursor_factory) as cur:
            yield cur

