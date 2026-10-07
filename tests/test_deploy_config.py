"""Configuration that only ever runs in a deployed environment.

None of this was covered: the app read `PG*` directly and took the leftmost
`X-Forwarded-For` entry unconditionally, both of which are wrong on a managed
platform and neither of which fails locally.
"""

from __future__ import annotations

import pytest

from skincaresync.clientip import forwarded_for, trust_proxy, trusted_hops
from skincaresync.dbconfig import DatabaseConfigError, database_settings


# --- DATABASE_URL ------------------------------------------------------------

@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    for name in ("DATABASE_URL", "PGHOST", "PGPORT", "PGDATABASE", "PGUSER",
                 "PGPASSWORD", "PGSSLMODE", "TRUST_PROXY", "TRUST_PROXY_HOPS"):
        monkeypatch.delenv(name, raising=False)


def test_database_url_wins_over_pg_vars(monkeypatch):
    monkeypatch.setenv("PGHOST", "localhost")
    monkeypatch.setenv("PGDATABASE", "ignored")
    monkeypatch.setenv("DATABASE_URL", "postgresql://u:p@db.internal:5433/railway")
    s = database_settings()
    assert (s["host"], s["port"], s["dbname"], s["user"]) == ("db.internal", "5433", "railway", "u")


def test_pg_vars_still_work_when_no_url(monkeypatch):
    monkeypatch.setenv("PGHOST", "db.example")
    monkeypatch.setenv("PGDATABASE", "skincaresync")
    monkeypatch.setenv("PGUSER", "svc")
    s = database_settings()
    assert (s["host"], s["dbname"], s["user"]) == ("db.example", "skincaresync", "svc")


def test_url_encoded_password_is_decoded(monkeypatch):
    # A password with reserved characters round-trips, which naive splitting breaks.
    monkeypatch.setenv("DATABASE_URL", "postgresql://u:p%40ss%3Aword@h:5432/d")
    assert database_settings()["password"] == "p@ss:word"


def test_sslmode_travels_from_the_url(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://u:p@h:5432/d?sslmode=require")
    assert database_settings()["sslmode"] == "require"


def test_postgres_scheme_is_accepted(monkeypatch):
    # Heroku-style URLs use postgres://, which SQLAlchemy alone rejects.
    monkeypatch.setenv("DATABASE_URL", "postgres://u:p@h:5432/d")
    assert database_settings()["host"] == "h"


@pytest.mark.parametrize("bad", ["mysql://u:p@h/d", "postgresql:///onlypath"])
def test_unusable_url_fails_loudly(monkeypatch, bad):
    monkeypatch.setenv("DATABASE_URL", bad)
    with pytest.raises(DatabaseConfigError):
        database_settings()


def test_both_connection_paths_agree(monkeypatch):
    from skincaresync.auth.db import database_url
    from skincaresync.database import connection_kwargs

    monkeypatch.setenv("DATABASE_URL", "postgresql://u:p@h:5432/d")
    kwargs, url = connection_kwargs(), database_url()
    assert (kwargs["host"], kwargs["dbname"]) == (url.host, url.database)


# --- X-Forwarded-For ---------------------------------------------------------

SPOOFED = "1.2.3.4, 203.0.113.9"   # client forged the first entry; the edge appended the second


def test_zero_hops_takes_the_leftmost_entry():
    # Correct only behind deploy/nginx.conf, which overwrites the header.
    assert forwarded_for(SPOOFED, 0) == "1.2.3.4"


def test_one_hop_ignores_the_forged_entry():
    # The Railway case: the platform edge appends, so the client is on the right.
    assert forwarded_for(SPOOFED, 1) == "203.0.113.9"


def test_two_hops_counts_further_from_the_right():
    assert forwarded_for("1.2.3.4, 10.0.0.1, 203.0.113.9", 2) == "10.0.0.1"


def test_short_header_cannot_underflow_into_the_forged_end():
    # Fewer proxies ran than configured; never wrap around to a spoofable index.
    assert forwarded_for("203.0.113.9", 3) == "203.0.113.9"


@pytest.mark.parametrize("header", ["", "   ", ",", " , "])
def test_empty_header_yields_nothing(header):
    assert forwarded_for(header, 1) is None


def test_whitespace_is_stripped():
    assert forwarded_for("  1.2.3.4 ,  203.0.113.9  ", 1) == "203.0.113.9"


def test_trust_is_off_unless_asked(monkeypatch):
    assert trust_proxy() is False
    monkeypatch.setenv("TRUST_PROXY", "true")
    assert trust_proxy() is True


def test_hops_defaults_to_zero_and_ignores_nonsense(monkeypatch):
    assert trusted_hops() == 0
    monkeypatch.setenv("TRUST_PROXY_HOPS", "not-a-number")
    assert trusted_hops() == 0
    monkeypatch.setenv("TRUST_PROXY_HOPS", "-4")
    assert trusted_hops() == 0


# --- statement cap without startup options -----------------------------------

def test_statement_cap_is_not_a_startup_option(monkeypatch):
    # Poolers in front of managed Postgres do not reliably forward startup
    # options; the cap must travel as SQL on the connection instead.
    from skincaresync.database import TimeoutConnection, connection_kwargs

    monkeypatch.setenv("DATABASE_URL", "postgresql://u:p@h:5432/d")
    kwargs = connection_kwargs()
    assert "options" not in kwargs
    assert kwargs["connection_factory"] is TimeoutConnection
