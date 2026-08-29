"""Product identity: unique-key collisions and SPL variants.

These run the real SQL against a temporary `products` table carrying the same
constraints as the real one, inside a transaction that is always rolled back.
"""

from __future__ import annotations

import contextlib

import psycopg2
import pytest
from psycopg2.extras import RealDictCursor

from skincaresync import product_catalog
from skincaresync.database import get_conn
from skincaresync.lookup import ProductLookupResult

real_upsert_products = product_catalog.upsert_products


def _product(**overrides) -> ProductLookupResult:
    fields = {
        "code": None,
        "brand": "PanOxyl",
        "name": "Acne Foaming Wash",
        "raw_ingredient_list": "Benzoyl Peroxide, Aqua, Glycerin",
        "source": "dailymed",
    }
    return ProductLookupResult(**{**fields, **overrides})


@contextlib.contextmanager
def _temp_products():
    """A shadow `products` table with the real unique keys. Always rolled back."""
    with get_conn() as conn:
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            """
            CREATE TEMP TABLE products (
                LIKE public.products INCLUDING DEFAULTS INCLUDING IDENTITY
            ) ON COMMIT DROP;
            CREATE UNIQUE INDEX ON products (barcode) WHERE barcode IS NOT NULL;
            CREATE UNIQUE INDEX ON products (setid, COALESCE(NULLIF(ndc, ''), lower(name)))
                WHERE setid IS NOT NULL;
            """
        )
        try:
            yield cursor
        finally:
            conn.rollback()


@pytest.fixture
def catalog(monkeypatch):
    try:
        with _temp_products() as cursor:
            monkeypatch.setattr(
                product_catalog, "get_cursor",
                lambda *a, **k: contextlib.nullcontext(cursor),
            )
            yield cursor
    except psycopg2.OperationalError as exc:
        pytest.skip(f"Postgres is not available: {exc}")


def _rows(cursor) -> list[dict]:
    cursor.execute("SELECT product_id, brand, name, barcode, ndc, setid, source FROM products ORDER BY product_id")
    return cursor.fetchall()


def test_a_new_product_is_inserted(catalog):
    assert real_upsert_products([_product(setid="abc", ndc="0316-0100", code="0316-0100")]) == 1
    assert len(_rows(catalog)) == 1


def test_the_same_product_updates_rather_than_duplicating(catalog):
    product = _product(setid="abc", ndc="0316-0100", code="0316-0100")
    real_upsert_products([product])
    real_upsert_products([product])
    assert len(_rows(catalog)) == 1


# --- H3: 583 stored rows had an NDC that was also another row's barcode -----

def test_a_new_label_whose_ndc_is_an_existing_barcode_updates_that_row(catalog):
    """Matching on `setid` alone meant the insert hit `products.barcode UNIQUE`
    and the whole lookup failed with a 502, losing the fetched ingredient list."""
    real_upsert_products([
        _product(setid=None, code="0316-0100", ndc=None, source="open_beauty_facts")
    ])

    written = real_upsert_products([
        _product(setid="brand-new-setid", ndc="0316-0100", code="0316-0100",
                 name="Acne Foaming Wash 10%")
    ])

    rows = _rows(catalog)
    assert written == 1, "the cache write must succeed, not collide"
    assert len(rows) == 1, "it must update the row holding that barcode"
    assert rows[0]["setid"] == "brand-new-setid"


# --- H6: one SPL can describe several marketed products ---------------------

def test_two_variants_of_one_label_are_stored_separately(catalog):
    """`setid` alone as a key meant the second variant overwrote the first, so a
    user could be shown the ingredient list of a different strength."""
    real_upsert_products([
        _product(setid="shared-setid", ndc="0316-0100", code="0316-0100",
                 name="Acne Foaming Wash 4%",
                 raw_ingredient_list="Benzoyl Peroxide, Aqua"),
        _product(setid="shared-setid", ndc="0316-0200", code="0316-0200",
                 name="Acne Foaming Wash 10%",
                 raw_ingredient_list="Benzoyl Peroxide, Aqua, Glycerin"),
    ])

    rows = _rows(catalog)
    assert len(rows) == 2
    assert {row["ndc"] for row in rows} == {"0316-0100", "0316-0200"}


def test_one_bad_product_does_not_discard_the_rest_of_the_batch(catalog):
    """A cache write is best-effort; a collision on one row is isolated by a
    savepoint so the other products in the page are still stored."""
    real_upsert_products([_product(setid=None, code="1111111111111", ndc=None)])

    written = real_upsert_products([
        _product(setid=None, code="2222222222222", ndc=None, name="Good One"),
        # Same barcode as an existing row but no other key to match it on, and a
        # conflicting name -- forced through the INSERT path.
        _product(setid="x", ndc="", code="1111111111111", name="Collides"),
        _product(setid=None, code="3333333333333", ndc=None, name="Also Good"),
    ])

    names = {row["name"] for row in _rows(catalog)}
    assert "Good One" in names and "Also Good" in names
    assert written >= 2


def test_a_product_without_an_ingredient_list_is_never_stored(catalog):
    assert real_upsert_products([_product(raw_ingredient_list="   ")]) == 0
    assert _rows(catalog) == []
