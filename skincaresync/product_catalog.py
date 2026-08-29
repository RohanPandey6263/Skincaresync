"""Local product catalog: stored ingredient lists for lookup.

Remote fetches (DailyMed, Open Beauty Facts) are written here after a successful
read so the next search does not depend on the upstream record still being
complete.
"""

from __future__ import annotations

from .database import get_cursor
from .lookup import ProductLookupResult, normalize_search_text


def escape_like_pattern(value: str) -> str:
    return (value or "").replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


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
            """
            SELECT brand, name, barcode, ndc, setid, raw_ingredient_list,
                   source, image_url, product_url, search_aliases
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
    combined = " ".join(part for part in [(brand or "").strip(), (name or "").strip()] if part)
    tokens = [token for token in normalize_search_text(combined).split() if len(token) >= 2]
    if not tokens:
        return []

    token_sql = []
    params: dict = {"limit": max(limit, 20)}
    for index, token in enumerate(tokens):
        key = f"tok{index}"
        params[key] = f"%{escape_like_pattern(token)}%"
        token_sql.append(
            f"""(
                LOWER(COALESCE(brand, '')) LIKE %({key})s
                OR LOWER(name) LIKE %({key})s
                OR EXISTS (
                    SELECT 1 FROM unnest(search_aliases) AS alias
                    WHERE LOWER(alias) LIKE %({key})s
                )
            )"""
        )

    with get_cursor() as cur:
        cur.execute(
            f"""
            SELECT brand, name, barcode, ndc, setid, raw_ingredient_list,
                   source, image_url, product_url, search_aliases
            FROM products
            WHERE raw_ingredient_list <> ''
              AND {' AND '.join(token_sql)}
            LIMIT %(limit)s
            """,
            params,
        )
        rows = cur.fetchall()
    return [_row_to_product(row) for row in rows]


def find_existing(product: ProductLookupResult) -> ProductLookupResult | None:
    """Return a stored row that would collide with this product, if any."""
    with get_cursor() as cur:
        if product.setid:
            cur.execute(
                """
                SELECT brand, name, barcode, ndc, setid, raw_ingredient_list,
                       source, image_url, product_url, search_aliases
                FROM products WHERE setid = %s
                """,
                (product.setid,),
            )
            row = cur.fetchone()
            if row:
                return _row_to_product(row)
        if product.code:
            cur.execute(
                """
                SELECT brand, name, barcode, ndc, setid, raw_ingredient_list,
                       source, image_url, product_url, search_aliases
                FROM products WHERE barcode = %s
                """,
                (product.code,),
            )
            row = cur.fetchone()
            if row:
                return _row_to_product(row)
        if product.ndc:
            cur.execute(
                """
                SELECT brand, name, barcode, ndc, setid, raw_ingredient_list,
                       source, image_url, product_url, search_aliases
                FROM products WHERE ndc = %s
                """,
                (product.ndc,),
            )
            row = cur.fetchone()
            if row:
                return _row_to_product(row)
        if product.brand and product.name:
            cur.execute(
                """
                SELECT brand, name, barcode, ndc, setid, raw_ingredient_list,
                       source, image_url, product_url, search_aliases
                FROM products
                WHERE LOWER(COALESCE(brand, '')) = LOWER(%s)
                  AND LOWER(name) = LOWER(%s)
                """,
                (product.brand, product.name),
            )
            row = cur.fetchone()
            if row:
                return _row_to_product(row)
    return None


def upsert_product(product: ProductLookupResult) -> None:
    if not product.raw_ingredient_list.strip():
        return
    aliases = list(product.search_aliases or [])
    with get_cursor() as cur:
        if product.setid:
            cur.execute("SELECT product_id FROM products WHERE setid = %s", (product.setid,))
        elif product.code:
            cur.execute("SELECT product_id FROM products WHERE barcode = %s", (product.code,))
        elif product.ndc:
            cur.execute("SELECT product_id FROM products WHERE ndc = %s", (product.ndc,))
        else:
            cur.execute(
                """
                SELECT product_id FROM products
                WHERE LOWER(COALESCE(brand, '')) = LOWER(%s)
                  AND LOWER(name) = LOWER(%s)
                """,
                (product.brand, product.name),
            )
        existing = cur.fetchone()
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
