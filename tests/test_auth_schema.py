"""The ORM models and the migrated schema must agree.

`create_all()` is never called -- automatic schema synchronisation would let a
deploy silently reshape production -- so `migrations/007_auth.sql` is the source
of truth and `models.py` only mirrors it. Nothing enforces that by construction,
so it is enforced here: if someone adds a column to one and not the other, this
fails.
"""

from __future__ import annotations

import subprocess

from sqlalchemy import inspect, text

from skincaresync.auth.models import AuthEvent, AuthToken, User, UserSession

AUTH_TABLES = [User, UserSession, AuthToken, AuthEvent]


def test_every_model_table_exists_in_the_migrated_database(auth_engine):
    present = set(inspect(auth_engine).get_table_names())
    for model in AUTH_TABLES:
        assert model.__tablename__ in present


def test_model_columns_match_the_migrated_columns(auth_engine):
    inspector = inspect(auth_engine)
    for model in AUTH_TABLES:
        table = model.__tablename__
        actual = {column["name"] for column in inspector.get_columns(table)}
        declared = {column.name for column in model.__table__.columns}

        missing_in_db = declared - actual
        missing_in_model = actual - declared
        assert not missing_in_db, f"{table}: model declares {missing_in_db}, database lacks them"
        assert not missing_in_model, f"{table}: database has {missing_in_model}, model lacks them"


def test_unique_constraints_that_the_security_model_depends_on(auth_engine):
    """Each of these is load-bearing, not incidental."""
    inspector = inspect(auth_engine)

    user_indexes = {i["name"]: i for i in inspector.get_indexes("users")}
    # Without this, two accounts could exist for the same address in different case.
    assert user_indexes["users_email_normalized_key"]["unique"]
    assert user_indexes["users_email_normalized_key"]["column_names"] == ["email_normalized"]

    session_indexes = {i["name"]: i for i in inspector.get_indexes("user_sessions")}
    assert session_indexes["user_sessions_token_hash_key"]["unique"]

    token_indexes = {i["name"]: i for i in inspector.get_indexes("auth_tokens")}
    assert token_indexes["auth_tokens_token_hash_key"]["unique"]


def test_foreign_keys_cascade_and_preserve_the_audit_trail(auth_engine):
    inspector = inspect(auth_engine)

    for table in ("user_sessions", "auth_tokens"):
        fks = inspector.get_foreign_keys(table)
        assert fks, f"{table} should reference users"
        assert fks[0]["referred_table"] == "users"
        # Sessions and tokens are worthless without their user.
        assert fks[0]["options"].get("ondelete") == "CASCADE"

    # Audit events outlive the account they describe.
    event_fks = inspector.get_foreign_keys("auth_events")
    assert event_fks[0]["options"].get("ondelete") == "SET NULL"


def test_token_and_password_columns_are_not_plaintext_shaped(auth_engine):
    """Token columns are binary digests; the password column holds an encoding."""
    inspector = inspect(auth_engine)

    for table in ("user_sessions", "auth_tokens"):
        columns = {c["name"]: c for c in inspector.get_columns(table)}
        assert "BYTEA" in str(columns["token_hash"]["type"]).upper()
        # There is no column that could hold the token itself.
        assert "token" not in {n for n in columns if n != "token_hash"}

    user_columns = {c["name"] for c in inspector.get_columns("users")}
    assert "password" not in user_columns
    assert "password_hash" in user_columns


def test_expiry_columns_exist_on_everything_that_must_expire(auth_engine):
    inspector = inspect(auth_engine)
    for table in ("user_sessions", "auth_tokens"):
        columns = {c["name"] for c in inspector.get_columns(table)}
        assert "expires_at" in columns
    assert "consumed_at" in {c["name"] for c in inspector.get_columns("auth_tokens")}
    assert "revoked_at" in {c["name"] for c in inspector.get_columns("user_sessions")}


def test_the_email_normalized_column_is_generated_by_the_database(auth_engine):
    """A direct SQL insert must not be able to bypass normalisation."""
    with auth_engine.connect() as connection:
        generated = connection.execute(
            text(
                "SELECT is_generated, generation_expression FROM information_schema.columns "
                "WHERE table_name = 'users' AND column_name = 'email_normalized'"
            )
        ).one()
    assert generated.is_generated == "ALWAYS"
    assert "lower" in generated.generation_expression.lower()


def test_role_and_status_are_constrained_to_known_values(auth_engine):
    with auth_engine.connect() as connection:
        checks = connection.execute(
            text(
                "SELECT pg_get_constraintdef(oid) AS definition FROM pg_constraint "
                "WHERE conrelid = 'users'::regclass AND contype = 'c'"
            )
        ).scalars().all()
    joined = " ".join(checks)
    assert "role" in joined and "admin" in joined
    assert "status" in joined and "deactivated" in joined


def test_the_migration_is_idempotent(auth_engine):
    """Re-running it must not fail; deploys replay migrations."""
    from tests.conftest_auth import AUTH_MIGRATION, TEST_DB_NAME

    result = subprocess.run(
        ["psql", "-q", "-d", TEST_DB_NAME, "-v", "ON_ERROR_STOP=1", "-f", str(AUTH_MIGRATION)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr


def test_a_rollback_script_exists_and_drops_every_table():
    from tests.conftest_auth import AUTH_MIGRATION

    down = AUTH_MIGRATION.with_name("007_auth.down.sql")
    assert down.exists(), "007_auth.sql must ship a reversible companion"
    body = down.read_text()
    for model in AUTH_TABLES:
        assert f"DROP TABLE IF EXISTS {model.__tablename__}" in body
    # Children before parents, or the drop fails on the foreign keys.
    assert body.index("auth_tokens") < body.index("DROP TABLE IF EXISTS users")
    assert body.index("user_sessions") < body.index("DROP TABLE IF EXISTS users")


def test_models_are_never_used_to_create_the_schema():
    """Guards against someone adding `Base.metadata.create_all()` later.

    Parsed rather than grepped, so prose about create_all in a docstring does not
    trip it -- only a real call does.
    """
    import ast
    from pathlib import Path

    package = Path(__file__).resolve().parents[1] / "skincaresync"
    offenders = []
    for path in package.rglob("*.py"):
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if (
                isinstance(node, ast.Call)
                and isinstance(node.func, ast.Attribute)
                and node.func.attr in {"create_all", "drop_all"}
            ):
                offenders.append(f"{path.relative_to(package.parent)}:{node.lineno}")

    assert not offenders, f"schema must come from migrations, not create_all: {offenders}"
