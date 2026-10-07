"""The migration chain must build a working database from nothing.

Every seeded interaction rule resolves its two ingredients by joining
`ingredients` -- `aidatabase.sql` through a cross join of two CTEs, 009 and 010
through inner joins. On an empty catalog those match no rows, so the INSERTs
succeed, insert nothing, and the chain reports success while producing a
database with zero compatibility rules in it. Nothing in the API surfaces that:
`/api/analyze` just answers "no conflicts" to every routine forever.

Migration 000 exists to make that impossible, and this test is what keeps it
honest. It runs the real `install.sql` against a genuinely empty database, so a
future migration that reintroduces the dependency fails here rather than in
production.

Skipped when `createdb` is unavailable, as the auth suite does.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import psycopg2
import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
INSTALL_SQL = REPO_ROOT / "migrations" / "install.sql"
BOOTSTRAP_DB = os.getenv("BOOTSTRAP_TEST_DATABASE", "skincaresync_bootstrap_test")

# Not a count of "some rules loaded" but the full curated set. A partial number
# means a rule seed stopped resolving, which is exactly the silent failure this
# file exists to catch.
EXPECTED_CURATED_INGREDIENTS = 141
EXPECTED_INTERACTIONS = 156


def _run(command: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, check=False)


@pytest.fixture(scope="module")
def bootstrapped_database():
    """Build the schema from scratch in a throwaway database."""
    if _run(["which", "createdb"]).returncode != 0:
        pytest.skip("createdb is not on PATH")

    # Dropped first so a failed previous run cannot make this one pass on
    # leftover rows.
    _run(["dropdb", "--if-exists", BOOTSTRAP_DB])
    created = _run(["createdb", BOOTSTRAP_DB])
    if created.returncode != 0:
        pytest.skip(f"could not create {BOOTSTRAP_DB}: {created.stderr.strip()[:200]}")

    result = _run(
        ["psql", "-q", "-d", BOOTSTRAP_DB, "-v", "ON_ERROR_STOP=1", "-f", str(INSTALL_SQL)]
    )
    if result.returncode != 0:
        _run(["dropdb", "--if-exists", BOOTSTRAP_DB])
        pytest.fail(f"install.sql failed on an empty database:\n{result.stderr.strip()[:2000]}")

    connection = psycopg2.connect(
        dbname=BOOTSTRAP_DB,
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT") or None,
        user=os.getenv("PGUSER") or None,
        password=os.getenv("PGPASSWORD") or None,
    )
    # Autocommit, or every SELECT below leaves this connection idle-in-
    # transaction holding an ACCESS SHARE lock -- and the idempotency test
    # re-runs install.sql, whose ALTER TABLE then waits on that lock forever.
    connection.autocommit = True
    try:
        yield connection
    finally:
        connection.close()
        _run(["dropdb", "--if-exists", BOOTSTRAP_DB])


def _scalar(connection, sql: str):
    with connection.cursor() as cur:
        cur.execute(sql)
        return cur.fetchone()[0]


def test_curated_ingredients_are_seeded(bootstrapped_database):
    count = _scalar(bootstrapped_database, "SELECT COUNT(*) FROM ingredients")
    assert count == EXPECTED_CURATED_INGREDIENTS


def test_interaction_rules_resolve_against_the_seeded_catalog(bootstrapped_database):
    """The assertion that actually matters: rules, not just tables."""
    count = _scalar(bootstrapped_database, "SELECT COUNT(*) FROM interactions")
    assert count == EXPECTED_INTERACTIONS, (
        "interaction rules did not resolve. Every rule seed joins `ingredients`, "
        "so a shortfall means a referenced ingredient is missing from migration 000 "
        "rather than that the INSERT failed -- the INSERT reports success either way."
    )


def test_every_rule_points_at_a_real_ingredient(bootstrapped_database):
    orphans = _scalar(
        bootstrapped_database,
        """
        SELECT COUNT(*) FROM interactions i
        WHERE NOT EXISTS (SELECT 1 FROM ingredients g WHERE g.ingridient_id = i.ingredient_a_id)
           OR NOT EXISTS (SELECT 1 FROM ingredients g WHERE g.ingridient_id = i.ingredient_b_id)
        """,
    )
    assert orphans == 0


def test_seeded_names_are_trimmed(bootstrapped_database):
    """Untrimmed names break the `LOWER(inci_name) = '...'` joins rule seeds use.

    Twenty sunscreen rows in the original development database carried leading
    and trailing spaces. The generated `normalized_name` column trims, so the
    runtime resolver never noticed, but a rule referencing one by name would
    have silently failed to resolve.
    """
    untrimmed = _scalar(
        bootstrapped_database,
        "SELECT COUNT(*) FROM ingredients WHERE inci_name <> btrim(inci_name)",
    )
    assert untrimmed == 0


def test_install_sql_is_idempotent(bootstrapped_database):
    """Re-running the chain must not duplicate rows or fail."""
    before = _scalar(bootstrapped_database, "SELECT COUNT(*) FROM interactions")
    result = _run(
        ["psql", "-q", "-d", BOOTSTRAP_DB, "-v", "ON_ERROR_STOP=1", "-f", str(INSTALL_SQL)]
    )
    assert result.returncode == 0, result.stderr.strip()[:2000]
    assert _scalar(bootstrapped_database, "SELECT COUNT(*) FROM interactions") == before


def test_install_sql_is_current(bootstrapped_database):
    """`install.sql` is generated; a new migration must be built into it.

    CI has no other way to notice it went stale, and a stale bundle is a deploy
    that silently skips the newest migration.
    """
    builder = REPO_ROOT / "scripts" / "build_install_sql.sh"
    checked_in = INSTALL_SQL.read_text()
    result = _run(["bash", str(builder)])
    assert result.returncode == 0, result.stderr.strip()[:500]
    regenerated = INSTALL_SQL.read_text()
    if regenerated != checked_in:
        INSTALL_SQL.write_text(checked_in)
        pytest.fail("migrations/install.sql is stale -- run scripts/build_install_sql.sh")
