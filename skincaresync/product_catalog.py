"""Local product catalog: stored ingredient lists for lookup.

Remote fetches (DailyMed, Open Beauty Facts) are written here after a successful
read so the next search does not depend on the upstream record still being
complete.

Writing to this table is a cache fill, never the point of a request. Every write
here is therefore best-effort: it logs and returns rather than propagating, so a
storage problem can never turn a successful lookup into an error for the user.
"""

from __future__ import annotations

import logging

import psycopg2

from .database import get_cursor
from .lookup import ProductLookupResult, normalize_search_text

logger = logging.getLogger(__name__)

# One place to change when the row shape changes; this list was previously
# repeated verbatim in six queries and had already drifted in one of them.
_PRODUCT_COLUMNS = """
    product_id, brand, name, barcode, ndc, setid, raw_ingredient_list,
    source, image_url, product_url, search_aliases
"""

# A single SPL document can describe several marketed products. `setid` alone is
# therefore not an identity: the variant is the NDC when the label carries one,
# and the product name otherwise. This mirrors `products_setid_variant_key`.
_VARIANT_SQL = "COALESCE(NULLIF(ndc, ''), lower(name))"


def escape_like_pattern(value: str) -> str:
    return (value or "").replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _variant_key(product: ProductLookupResult) -> str:
    return (product.ndc or "").strip() or (product.name or "").lower()


def _row_to_product(row: dict) -> ProductLookupResult:
    return ProductLookupResult(
        code=row.get("barcode") or row.get("ndc"),
        brand=row.get("brand") or "",
        name=row["name"],
        raw_ingredient_list=row["raw_ingredient_list"],
        source=row.get("source") or "manual",
        image_url=row.get("image_url"),
        product_url=row.get("product_url"),
        ndc=row.get("ndc"),
        setid=row.get("setid"),
        search_aliases=tuple(row.get("search_aliases") or []),
    )


def get_by_code(code: str) -> ProductLookupResult | None:
    digits = "".join(ch for ch in (code or "") if ch.isdigit())
    if not digits:
        return None
    with get_cursor() as cur:
        cur.execute(
            f"""
            SELECT {_PRODUCT_COLUMNS}
            FROM products
            WHERE barcode = %(code)s
               OR regexp_replace(COALESCE(ndc, ''), '[^0-9]', '', 'g') = %(digits)s
               OR regexp_replace(COALESCE(barcode, ''), '[^0-9]', '', 'g') = %(digits)s
            LIMIT 1
            """,
            {"code": code, "digits": digits},
        )
        row = cur.fetchone()
    return _row_to_product(row) if row else None


def search_local(brand: str, name: str, limit: int = 20) -> list[ProductLookupResult]:
    """Products whose brand, name or aliases contain every query token.

    Each token is matched against the single accent-folded `search_text` column
    rather than against brand, name and an unnested alias array separately. That
    is one trigram-indexable condition per token instead of three unindexable
    ones plus a correlated subquery, and it matches "Biore" to a stored "Bioré".
    """
    combined = " ".join(part for part in [(brand or "").strip(), (name or "").strip()] if part)
    tokens = [token for token in normalize_search_text(combined).split() if len(token) >= 2]
    if not tokens:
        return []

    token_sql = []
    params: dict = {"limit": max(limit, 20)}
    for index, token in enumerate(tokens):
        key = f"tok{index}"
        params[key] = f"%{escape_like_pattern(token)}%"
        token_sql.append(f"search_text LIKE %({key})s")

    with get_cursor() as cur:
        cur.execute(
            f"""
            SELECT {_PRODUCT_COLUMNS}
            FROM products
            WHERE raw_ingredient_list <> ''
              AND {' AND '.join(token_sql)}
            LIMIT %(limit)s
            """,
            params,
        )
        rows = cur.fetchall()
    return [_row_to_product(row) for row in rows]


def _find_existing_row(cur, product: ProductLookupResult) -> dict | None:
    """The stored row this product should update, by identity precedence.

    Every unique key on the table is checked in one query. Checking only the
    first key that happens to be populated -- as the write path used to -- meant
    a DailyMed product was matched by `setid` alone, so if its NDC was already
    stored as another row's `barcode` the insert hit `products.barcode UNIQUE`
    and the cache write failed.
    """
    cur.execute(
        f"""
        SELECT {_PRODUCT_COLUMNS},
               CASE
                   WHEN %(setid)s <> '' AND setid = %(setid)s
                        AND {_VARIANT_SQL} = %(variant)s          THEN 1
                   WHEN %(code)s <> ''  AND barcode = %(code)s     THEN 2
                   WHEN %(ndc)s <> ''   AND ndc = %(ndc)s          THEN 3
                   ELSE 4
               END AS match_rank
        FROM products
        WHERE (%(setid)s <> '' AND setid = %(setid)s AND {_VARIANT_SQL} = %(variant)s)
           OR (%(code)s  <> '' AND barcode = %(code)s)
           OR (%(ndc)s   <> '' AND ndc = %(ndc)s)
           OR (
                %(brand)s <> '' AND %(name)s <> ''
                AND LOWER(COALESCE(brand, '')) = LOWER(%(brand)s)
                AND LOWER(name) = LOWER(%(name)s)
              )
        ORDER BY match_rank
        LIMIT 1
        """,
        {
            "setid": product.setid or "",
            "code": product.code or "",
            "ndc": product.ndc or "",
            "brand": product.brand or "",
            "name": product.name or "",
            "variant": _variant_key(product),
        },
    )
    return cur.fetchone()


def find_existing(product: ProductLookupResult) -> ProductLookupResult | None:
    """Return a stored row that would collide with this product, if any."""
    with get_cursor() as cur:
        row = _find_existing_row(cur, product)
    return _row_to_product(row) if row else None


def _write(cur, product: ProductLookupResult) -> None:
    aliases = list(product.search_aliases or [])
    existing = _find_existing_row(cur, product)

    if existing:
        cur.execute(
            """
            UPDATE products SET
                brand = COALESCE(NULLIF(%s, ''), brand),
                name = %s,
                barcode = COALESCE(%s, barcode),
                ndc = COALESCE(%s, ndc),
                setid = COALESCE(%s, setid),
                raw_ingredient_list = %s,
                source = %s,
                product_url = COALESCE(%s, product_url),
                image_url = COALESCE(%s, image_url),
                search_aliases = CASE
                    WHEN cardinality(%s::text[]) = 0 THEN search_aliases
                    ELSE (SELECT ARRAY(SELECT DISTINCT unnest(search_aliases || %s::text[])))
                END,
                updated_at = NOW()
            WHERE product_id = %s
            """,
            (
                product.brand,
                product.name,
                product.code,
                product.ndc,
                product.setid,
                product.raw_ingredient_list,
                product.source,
                product.product_url,
                product.image_url,
                aliases,
                aliases,
                existing["product_id"],
            ),
        )
        return

    cur.execute(
        """
        INSERT INTO products (
            brand, name, barcode, ndc, setid, raw_ingredient_list,
            source, product_url, image_url, search_aliases
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            product.brand,
            product.name,
            product.code,
            product.ndc,
            product.setid,
            product.raw_ingredient_list,
            product.source,
            product.product_url,
            product.image_url,
            aliases,
        ),
    )


def upsert_product(product: ProductLookupResult) -> bool:
    """Store one product. Returns whether the row was written."""
    return upsert_products([product]) == 1


def upsert_products(products: list[ProductLookupResult]) -> int:
    """Store several products over a single pooled connection.

    Callers cache whole result pages, which previously meant one connection
    checkout, transaction and commit per product.

    A collision on one product is isolated with a savepoint so it cannot discard
    the rest of the batch, and is never propagated: this is a cache fill.
    """
    written = 0
    candidates = [p for p in products if p.raw_ingredient_list.strip()]
    if not candidates:
        return 0

    try:
        with get_cursor() as cur:
            for product in candidates:
                cur.execute("SAVEPOINT product_upsert")
                try:
                    _write(cur, product)
                except psycopg2.IntegrityError as exc:
                    cur.execute("ROLLBACK TO SAVEPOINT product_upsert")
                    logger.warning(
                        "skipped caching %r (%s): %s",
                        product.name,
                        product.source,
                        str(exc).strip().splitlines()[0],
                    )
                else:
                    cur.execute("RELEASE SAVEPOINT product_upsert")
                    written += 1
    except Exception:
        logger.exception("product cache write failed for %d product(s)", len(candidates))
        return 0
    return written
