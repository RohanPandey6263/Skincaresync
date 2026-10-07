"""The per-query cap, observed on real connections.

It used to be a libpq startup option, which connection poolers (Supabase's
Supavisor, PgBouncer) do not reliably pass through. It is now the first
statement of every session; these tests check it actually takes effect on both
connection paths, and survives the rollback that would undo an uncommitted SET.
"""

from __future__ import annotations

import psycopg2
import pytest
from sqlalchemy import text

from skincaresync.database import STATEMENT_TIMEOUT_MS, connection_kwargs


def _connect():
    return psycopg2.connect(**{k: v for k, v in connection_kwargs().items() if v})


def _reachable() -> bool:
    try:
        _connect().close()
        return True
    except Exception:
        return False


pytestmark = pytest.mark.skipif(not _reachable(), reason="No database to connect to")

_SETTING = "SELECT setting FROM pg_settings WHERE name = 'statement_timeout'"


def test_pool_connections_carry_the_cap():
    conn = _connect()
    try:
        with conn.cursor() as cur:
            cur.execute(_SETTING)
            assert cur.fetchone()[0] == str(STATEMENT_TIMEOUT_MS)
    finally:
        conn.close()


def test_cap_survives_a_rolled_back_transaction():
    conn = _connect()
    try:
        conn.rollback()
        with conn.cursor() as cur:
            cur.execute(_SETTING)
            assert cur.fetchone()[0] == str(STATEMENT_TIMEOUT_MS)
    finally:
        conn.close()


def test_auth_engine_carries_the_cap():
    from skincaresync.auth.db import get_engine

    with get_engine().connect() as conn:
        assert conn.execute(text(_SETTING)).scalar() == str(STATEMENT_TIMEOUT_MS)
