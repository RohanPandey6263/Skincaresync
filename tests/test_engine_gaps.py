"""Gap recording: batching, conflict safety, and per-routine scoping."""

from __future__ import annotations

import contextlib

import psycopg2
import pytest
from psycopg2.extras import RealDictCursor

from skincaresync import engine
from skincaresync.database import get_conn
from skincaresync.engine import ProductInput, SkinProfileInput, analyze_routines
from skincaresync.parser import Ingredient, IngredientResolver

# Bound at import, before conftest's autouse fixture replaces the module
# attribute. Tests that exercise the writer itself must call the real thing.
real_log_interaction_gaps = engine.log_interaction_gaps


def _catalog(*names: str) -> list[Ingredient]:
    return [
        Ingredient(
            id=index + 1,
            inci_name=name,
            synonyms=[],
            category=None,
            ph_min=None,
            ph_max=None,
            comodogenic=None,
        )
        for index, name in enumerate(names)
    ]


@pytest.fixture
def offline_catalog(monkeypatch):
    """A small in-memory catalog with no interaction rules, so every pair is a gap."""
    resolver = IngredientResolver(_catalog("Retinol", "Niacinamide", "Caffeine", "Aqua"))
    monkeypatch.setattr(engine, "get_shared_resolver", lambda: resolver)
    monkeypatch.setattr(engine, "fetch_interactions", lambda ids: {})
    return resolver


# --- C1: one statement per analysis, not one per pair ----------------------

def test_gaps_are_written_in_a_single_batch(offline_catalog, recorded_writes):
    """Previously one SELECT plus one INSERT or UPDATE per pair, each on its own
    pooled connection. A 16.8 KB body cost 89,700 round trips."""
    label = "Retinol, Niacinamide, Caffeine, Aqua"
    analyze_routines(
        [ProductInput(name="A", raw_ingredient_list=label),
         ProductInput(name="B", raw_ingredient_list=label)],
        [],
        SkinProfileInput("normal", []),
    )

    assert recorded_writes.gap_calls == 1
    assert len(recorded_writes.gap_pairs) > 1


def test_gap_pairs_are_deduplicated_and_ordered(offline_catalog, recorded_writes):
    """Postgres rejects an ON CONFLICT statement that hits one key twice, so the
    batch must contain each unordered pair exactly once."""
    label = "Retinol, Niacinamide, Caffeine"
    analyze_routines(
        [ProductInput(name="A", raw_ingredient_list=label),
         ProductInput(name="B", raw_ingredient_list=label)],
        [ProductInput(name="C", raw_ingredient_list=label)],
        SkinProfileInput("normal", []),
    )

    pairs = recorded_writes.gap_pairs
    assert len(pairs) == len(set(pairs))
    assert all(a < b for a, b in pairs)


def test_gap_batch_is_capped(monkeypatch):
    """A pathological routine must not be able to write unbounded backlog rows."""
    monkeypatch.setattr(engine, "MAX_GAP_ROWS", 2)
    captured = []
    monkeypatch.setattr(engine, "execute_values",
                        lambda cur, sql, rows, **kw: captured.extend(rows))
    monkeypatch.setattr(engine, "get_cursor",
                        lambda *a, **k: contextlib.nullcontext(object()))

    written = real_log_interaction_gaps(
        {(1, 2), (1, 3), (2, 3), (1, 4)}, SkinProfileInput("normal", [])
    )

    assert written == 2
    assert len(captured) == 2


# --- M7: AM and PM both used the scope key "direct" -------------------------

def test_an_unknown_pair_is_reported_for_each_routine_it_appears_in(offline_catalog, recorded_writes):
    """The same pair in the morning and evening routines is two findings. Keying
    deduplication on scope alone meant the evening one was silently dropped."""
    result = analyze_routines(
        [ProductInput(name="AM-1", raw_ingredient_list="Retinol"),
         ProductInput(name="AM-2", raw_ingredient_list="Niacinamide")],
        [ProductInput(name="PM-1", raw_ingredient_list="Retinol"),
         ProductInput(name="PM-2", raw_ingredient_list="Niacinamide")],
        SkinProfileInput("normal", []),
    )

    # One per routine at direct scope, plus one across AM and PM at cumulative.
    assert result["unknown_pair_count"] == 3


def test_a_pair_is_not_reported_twice_within_one_routine(offline_catalog, recorded_writes):
    result = analyze_routines(
        [ProductInput(name="A", raw_ingredient_list="Retinol"),
         ProductInput(name="B", raw_ingredient_list="Niacinamide"),
         ProductInput(name="C", raw_ingredient_list="Retinol")],
        [],
        SkinProfileInput("normal", []),
    )
    assert result["unknown_pair_count"] == 1


# --- H2: concurrent analyses raced the unique index and 500ed ---------------

@contextlib.contextmanager
def _rollback_only_cursor():
    """Run real SQL against a real transaction that is always rolled back."""
    with get_conn() as conn:
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            CREATE TEMP TABLE interaction_gaps (
                LIKE public.interaction_gaps INCLUDING DEFAULTS INCLUDING IDENTITY
            ) ON COMMIT DROP;
            CREATE UNIQUE INDEX ON interaction_gaps (
                LEAST(ingredient_a_id, ingredient_b_id),
                GREATEST(ingredient_a_id, ingredient_b_id),
                COALESCE(user_skin_type, '')
            );
            """
        )
        try:
            yield cursor
        finally:
            conn.rollback()


def test_replaying_the_same_gaps_increments_instead_of_raising(monkeypatch):
    """Two requests analysing the same new pair both saw no row and both
    inserted; one hit `idx_interaction_gaps_unique_pair` and failed the whole
    analysis. `ON CONFLICT` makes the second write an increment."""
    try:
        with _rollback_only_cursor() as cursor:
            monkeypatch.setattr(
                engine, "get_cursor", lambda *a, **k: contextlib.nullcontext(cursor)
            )
            profile = SkinProfileInput("normal", ["acne"])
            pairs = {(1, 2), (3, 4)}

            real_log_interaction_gaps(pairs, profile)
            real_log_interaction_gaps(pairs, profile)
            real_log_interaction_gaps({(2, 1)}, profile)  # reversed order

            cursor.execute(
                "SELECT ingredient_a_id, ingredient_b_id, query_count"
                " FROM interaction_gaps ORDER BY ingredient_a_id"
            )
            rows = cursor.fetchall()
    except psycopg2.OperationalError as exc:
        pytest.skip(f"Postgres is not available: {exc}")

    assert len(rows) == 2, "the reversed pair must collapse onto the existing row"
    assert rows[0]["query_count"] == 3
    assert rows[1]["query_count"] == 2


def test_a_failed_gap_write_does_not_fail_the_analysis(offline_catalog, monkeypatch):
    """Recording a gap is telemetry. It must never cost the user their result."""
    def exploding_cursor(*args, **kwargs):
        raise psycopg2.OperationalError("simulated outage")

    # Restore the real writer so the simulated outage actually reaches it.
    monkeypatch.setattr(engine, "log_interaction_gaps", real_log_interaction_gaps)
    monkeypatch.setattr(engine, "get_cursor", exploding_cursor)

    result = analyze_routines(
        [ProductInput(name="A", raw_ingredient_list="Retinol"),
         ProductInput(name="B", raw_ingredient_list="Niacinamide")],
        [],
        SkinProfileInput("normal", []),
    )
    assert result["overall_score"]["status"] == "clean"
