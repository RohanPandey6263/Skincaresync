"""Where the database connection settings come from.

Two call sites need the same answer: the psycopg2 pool in `database.py` and the
SQLAlchemy engine in `auth/db.py`. They used to read the `PG*` variables
separately, which worked on a laptop and under compose -- both set those
variables explicitly -- and nowhere else.

Managed platforms (Railway, Render, Heroku, Fly) hand out a single
`DATABASE_URL` instead and do not set `PG*` at all. Without this module the app
silently falls back to `localhost`, then fails its first query with a
connection-refused that looks nothing like the actual problem.

`DATABASE_URL` wins when it is set; otherwise the `PG*` variables are used
exactly as before, so existing deployments are unaffected.
"""

from __future__ import annotations

import getpass
import os
from urllib.parse import parse_qsl, unquote, urlsplit

# libpq accepts both spellings; SQLAlchemy only understands the first.
_URL_SCHEMES = {"postgres", "postgresql"}

# Connection-level query parameters worth carrying across. `sslmode` is the one
# that matters in practice: most managed providers pin it in the URL, and
# dropping it turns a working URL into a rejected connection.
_PASSTHROUGH_PARAMS = {"sslmode", "sslrootcert", "sslcert", "sslkey", "target_session_attrs"}


class DatabaseConfigError(RuntimeError):
    """`DATABASE_URL` is set but unusable."""


def _from_url(raw: str) -> dict:
    parts = urlsplit(raw)
    if parts.scheme not in _URL_SCHEMES:
        raise DatabaseConfigError(
            f"DATABASE_URL must start with postgres:// or postgresql://, got {parts.scheme!r}://"
        )
    if not parts.hostname:
        raise DatabaseConfigError("DATABASE_URL has no host")

    settings = {
        "host": parts.hostname,
        "port": str(parts.port) if parts.port else None,
        # The path is "/dbname"; an empty path means the provider expects the
        # user's own default database.
        "dbname": unquote(parts.path.lstrip("/")) or None,
        "user": unquote(parts.username) if parts.username else None,
        "password": unquote(parts.password) if parts.password else None,
    }
    settings.update(
        {k: v for k, v in parse_qsl(parts.query) if k in _PASSTHROUGH_PARAMS}
    )
    return settings


def _from_pg_vars() -> dict:
    return {
        "host": os.getenv("PGHOST", "localhost"),
        "port": os.getenv("PGPORT"),
        "dbname": os.getenv("PGDATABASE", "postgres"),
        # Falls back to the OS account rather than a hardcoded name, so the same
        # code runs unchanged on a developer laptop and in a container.
        "user": os.getenv("PGUSER") or None,
        "password": os.getenv("PGPASSWORD") or None,
    }


def database_settings() -> dict:
    """Host, port, dbname, user, password (+ any ssl params), from one source.

    Keys are always present; a value of `None` means "let libpq decide".
    """
    raw = os.getenv("DATABASE_URL", "").strip()
    settings = _from_url(raw) if raw else _from_pg_vars()

    # A URL may omit the database or the user; fill those the same way the
    # PG* path does rather than letting libpq guess differently per call site.
    if not settings.get("dbname"):
        settings["dbname"] = os.getenv("PGDATABASE", "postgres")
    if not settings.get("user"):
        settings["user"] = os.getenv("PGUSER") or getpass.getuser()
    # PGSSLMODE stays available as an override for URLs that carry no sslmode.
    if not settings.get("sslmode") and os.getenv("PGSSLMODE"):
        settings["sslmode"] = os.getenv("PGSSLMODE")
    return settings


def using_database_url() -> bool:
    """True when the settings came from `DATABASE_URL`, for log lines."""
    return bool(os.getenv("DATABASE_URL", "").strip())
