"""Ingredient catalog search.

All matching and ranking happens in Postgres so the browser never downloads the
catalog. Four complementary strategies are combined and then ranked:

1. Exact match on the normalized INCI name.
2. Prefix match (fast "as you type" behaviour).
3. Substring match on the canonical name, alternate names and curated synonyms.
4. Full-text search over the whole document, plus trigram similarity for typo
   tolerance.

Indexes backing this: GIN on `search_document`, GIN trigram on `inci_name` and
`normalized_name`, GIN on `alt_names`/`functions`, btree on `normalized_name`.
"""

from __future__ import annotations

import re
import threading
import time
from typing import Any

from .database import get_cursor
from .inci_names import display_inci_name
from .parser import normalize_token

# Characters that `websearch_to_tsquery` treats as operators (`-` is NOT).
_TSQUERY_NOISE = re.compile(r"[^\w\s]+", re.UNICODE)

MAX_LIMIT = 100
SUGGEST_LIMIT = 8
# Below this word similarity a fuzzy match is noise rather than a typo. This is
# compared against `word_similarity()` directly. There used to also be a
# `SET LOCAL pg_trgm.similarity_threshold` issued before every search, which did
# nothing: that GUC gates the `%` and `<%` operators, and no query here uses
# them. It cost a round trip per search and misdescribed the real threshold.
WORD_SIMILARITY_THRESHOLD = 0.55
FACET_CACHE_TTL_SECONDS = 300

_SELECT_FIELDS = """
    i.ingridient_id AS id,
    i.inci_name,
    i.alt_names,
    i.synonyms,
    i.category,
    i.functions,
    i.description,
    i.cas_number,
    i.einecs_number,
    i.inn_name,
    i.ph_eur_name,
    i.cosing_ref,
    i.wikidata_id,
    i.restriction,
    i.obf_id,
    i.ph_min,
    i.ph_max,
    i.comodogenic,
    i.source,
    i.source_updated_on,
    i.interaction_count
"""

# Alternate and curated names are unnested once per row in a lateral join rather
# than in two separate correlated subqueries.
_ALIAS_JOIN = """
    LEFT JOIN LATERAL (
        SELECT
            bool_or(lower(n) = lower(q.raw)) AS exact_hit,
            bool_or(n ILIKE q.pattern) AS partial_hit
        FROM unnest(i.alt_names || i.synonyms) AS n
    ) alias ON TRUE
"""

# Relevance model. Exact and prefix hits dominate; whole-word and alias hits
# beat substring matches inside a 200-character ferment complex; trigram
# similarity is scored on the longest query token so "tranexamic acid" does
# not surface "tartaric acid". Long multi-botanical names are penalised so
# "tomato" ranks "Hydrolyzed Tomato Skin" above a 1,900-character filtrate.
#
# The exact-match bonus is gated on normalization having preserved most of the
# query. "(tomato) fruit" normalizes to "fruit" because parentheses are stripped,
# and treating that as an authoritative exact hit would bury the tomato entries.
_RELEVANCE = """
    (
        CASE
            WHEN i.normalized_name = q.norm AND q.norm_representative
            THEN 1000 ELSE 0
        END
      + CASE WHEN q.norm <> '' AND i.normalized_name LIKE q.norm_prefix THEN 420 ELSE 0 END
      + CASE WHEN alias.exact_hit THEN 520 ELSE 0 END
      + CASE WHEN q.word_re <> '' AND i.inci_name ~* q.word_re THEN 220 ELSE 0 END
      + CASE WHEN i.inci_name ILIKE q.pattern THEN 150 ELSE 0 END
      + CASE WHEN alias.partial_hit THEN 130 ELSE 0 END
      + CASE WHEN q.longest <> '' THEN word_similarity(q.longest, i.normalized_name) * 180 ELSE 0 END
      + CASE
            WHEN q.ts IS NOT NULL AND i.search_document @@ q.ts
            THEN ts_rank_cd(i.search_document, q.ts) * 80
            ELSE 0
        END
      + CASE WHEN i.source = 'curated' THEN 60 ELSE 0 END
      + LEAST(i.interaction_count, 12) * 4
      - GREATEST(length(i.inci_name) - 36, 0) * 0.35
    )
"""

# Fuzzy matches must share the longest query token (typo-tolerant). Full-text
# search is gated the same way so a common stemmed word like "acid" cannot
# drag in every acid in the catalog.
_MATCH_CLAUSE = """
    (
        i.normalized_name = q.norm
        OR (q.norm <> '' AND i.normalized_name LIKE q.norm_prefix)
        OR i.inci_name ILIKE q.pattern
        OR alias.partial_hit
        OR (
            q.ts IS NOT NULL
            AND i.search_document @@ q.ts
            AND (
                q.longest_len < 5
                OR i.normalized_name ILIKE q.longest_pattern
                OR i.alias_text ILIKE q.longest_pattern
            )
        )
        OR (
            q.longest_len >= 4
            AND word_similarity(q.longest, i.normalized_name) >= {threshold}
        )
        OR (
            q.longest_len >= 4
            AND word_similarity(q.longest, coalesce(i.alias_text, '')) >= {threshold}
        )
    )
""".format(threshold=WORD_SIMILARITY_THRESHOLD)


def escape_like(value: str) -> str:
    """Neutralise LIKE wildcards so user punctuation is matched literally."""
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def longest_token(normalized: str) -> str:
    """The distinctive word in a query — used to gate fuzzy/full-text matches."""
    tokens = [token for token in normalized.split() if token]
    return max(tokens, key=len) if tokens else ""


def fts_query_text(raw: str) -> str:
    """Strip websearch operators so 'C12-15' is not parsed as 'C12 NOT 15'."""
    cleaned = _TSQUERY_NOISE.sub(" ", raw or "")
    return re.sub(r"\s+", " ", cleaned).strip()


def word_boundary_regex(raw: str) -> str:
    """Case-insensitive whole-word pattern, or empty if the query is too noisy."""
    cleaned = (raw or "").strip()
    if not cleaned or len(cleaned) > 80:
        return ""
    return r"\y" + re.escape(cleaned) + r"\y"


def _serialize(row: dict) -> dict:
    data = dict(row)
    data.pop("relevance", None)
    data.pop("total_count", None)
    data["display_name"] = display_inci_name(data["inci_name"])
    data["alt_names"] = data.get("alt_names") or []
    data["synonyms"] = data.get("synonyms") or []
    data["functions"] = data.get("functions") or []
    updated = data.get("source_updated_on")
    data["source_updated_on"] = updated.isoformat() if updated else None
    return data


def _query_params(query: str) -> dict[str, Any]:
    """Build the bound parameters every search variant needs.

    The normalized prefix is escaped here because it is used as a LIKE pattern;
    without this, a query like "100%_%" normalizes to "_%" and would match the
    entire catalog as wildcards.
    """
    cleaned = (query or "").strip()
    normalized = normalize_token(cleaned)
    longest = longest_token(normalized)
    fts_text = fts_query_text(cleaned)
    return {
        "raw": cleaned,
        "pattern": f"%{escape_like(cleaned)}%" if cleaned else "%",
        "norm_prefix": f"{escape_like(normalized)}%" if normalized else "%",
        "longest": longest,
        "longest_len": len(longest),
        "longest_pattern": f"%{escape_like(longest)}%" if longest else "%",
        "word_re": word_boundary_regex(cleaned),
        "fts_text": fts_text,
        # Did normalization keep enough of the query for an exact hit to mean
        # something? Guards against parenthetical/percentage-only queries.
        "norm_representative": bool(normalized)
        and len(normalized) >= max(1, int(len(cleaned) * 0.6)),
    }


def search_ingredients(
    query: str = "",
    functions: list[str] | None = None,
    source: str | None = None,
    letter: str | None = None,
    only_with_interactions: bool = False,
    only_restricted: bool = False,
    limit: int = 20,
    offset: int = 0,
) -> dict:
    """Ranked, paginated ingredient search.

    Returns `{items, total, limit, offset, has_more, query}`.
    """
    limit = max(1, min(limit, MAX_LIMIT))
    offset = max(0, offset)
    params = _query_params(query)
    has_query = bool(params["raw"])

    filters = []
    if functions:
        filters.append("i.functions && %(functions)s::text[]")
        params["functions"] = functions
    if source:
        filters.append("i.source = %(source)s")
        params["source"] = source
    if letter:
        if letter == "#":
            filters.append("upper(left(i.inci_name, 1)) !~ '^[A-Z]$'")
        else:
            filters.append("upper(left(i.inci_name, 1)) = %(letter)s")
            params["letter"] = letter[:1].upper()
    if only_with_interactions:
        filters.append("i.interaction_count > 0")
    if only_restricted:
        filters.append("i.restriction IS NOT NULL AND i.restriction <> ''")

    where = [_MATCH_CLAUSE] if has_query else []
    where.extend(filters)
    where_sql = " AND ".join(where) if where else "TRUE"

    # Without a query this is a browse: letter strips sort alphabetically,
    # otherwise curated/engine-known ingredients lead.
    if has_query:
        order_sql = (
            f"{_RELEVANCE} DESC, i.interaction_count DESC, length(i.inci_name), i.inci_name"
        )
    elif letter:
        order_sql = "i.inci_name"
    else:
        order_sql = "(i.source = 'curated') DESC, i.interaction_count DESC, i.inci_name"

    # COUNT(*) OVER () forces a full scan of every matching row. On an unfiltered
    # browse that is the whole catalog on every page load, and it also defeats the
    # ordering index. There the total is just the catalog size, which is cached.
    counts_rows = bool(has_query or filters)
    total_select = "COUNT(*) OVER () AS total_count" if counts_rows else "NULL::bigint AS total_count"

    sql = f"""
        WITH q AS (
            SELECT
                %(raw)s::text AS raw,
                inci_normalize(%(raw)s) AS norm,
                %(pattern)s::text AS pattern,
                %(norm_prefix)s::text AS norm_prefix,
                %(norm_representative)s::boolean AS norm_representative,
                %(longest)s::text AS longest,
                %(longest_len)s::int AS longest_len,
                %(longest_pattern)s::text AS longest_pattern,
                %(word_re)s::text AS word_re,
                CASE
                    WHEN %(fts_text)s = '' THEN NULL
                    ELSE plainto_tsquery('english', %(fts_text)s)
                END AS ts
        )
        SELECT {_SELECT_FIELDS},
               {total_select}
        FROM ingredients i
        CROSS JOIN q
        {_ALIAS_JOIN}
        WHERE {where_sql}
        ORDER BY {order_sql}
        LIMIT %(limit)s OFFSET %(offset)s
    """
    params.update({"limit": limit, "offset": offset})

    with get_cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    total = (rows[0]["total_count"] if rows else 0) if counts_rows else catalog_total()
    return {
        "items": [_serialize(row) for row in rows],
        "total": total,
        "limit": limit,
        "offset": offset,
        "has_more": offset + len(rows) < total,
        "query": params["raw"],
    }


def suggest_ingredients(query: str, limit: int = SUGGEST_LIMIT) -> list[dict]:
    """Lightweight autocomplete: prefix matches first, then fuzzy."""
    params = _query_params(query)
    if not params["raw"]:
        return []

    limit = max(1, min(limit, 20))
    params["limit"] = limit

    sql = """
        WITH q AS (
            SELECT
                %(raw)s::text AS raw,
                inci_normalize(%(raw)s) AS norm,
                %(pattern)s::text AS pattern,
                %(norm_prefix)s::text AS norm_prefix,
                %(longest)s::text AS longest,
                %(longest_pattern)s::text AS longest_pattern,
                %(longest_len)s::int AS longest_len
        )
        SELECT
            i.ingridient_id AS id,
            i.inci_name,
            i.category,
            i.functions,
            i.source,
            i.interaction_count,
            CASE
                WHEN i.normalized_name = q.norm THEN 3
                WHEN i.normalized_name LIKE q.norm_prefix THEN 2
                WHEN i.inci_name ILIKE q.pattern THEN 1
                ELSE 0
            END AS tier,
            word_similarity(q.longest, i.normalized_name) AS score
        FROM ingredients i
        CROSS JOIN q
        WHERE i.normalized_name LIKE q.norm_prefix
           OR i.inci_name ILIKE q.pattern
           OR i.alias_text ILIKE q.pattern
           OR (
                q.longest_len >= 4
                AND word_similarity(q.longest, i.normalized_name) >= %(similarity)s
           )
        ORDER BY tier DESC, score DESC, i.interaction_count DESC,
                 length(i.inci_name), i.inci_name
        LIMIT %(limit)s
    """

    params["similarity"] = WORD_SIMILARITY_THRESHOLD
    with get_cursor() as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    return [
        {
            "id": row["id"],
            "inci_name": row["inci_name"],
            "display_name": display_inci_name(row["inci_name"]),
            "category": row["category"],
            "functions": row["functions"] or [],
            "source": row["source"],
            "interaction_count": row["interaction_count"],
        }
        for row in rows
    ]


def get_ingredient(ingredient_id: int) -> dict | None:
    """Full detail for one ingredient, including its known interactions."""
    with get_cursor() as cur:
        cur.execute(
            f"SELECT {_SELECT_FIELDS} FROM ingredients i WHERE i.ingridient_id = %s",
            (ingredient_id,),
        )
        row = cur.fetchone()
        if not row:
            return None

        ingredient = _serialize(row)

        cur.execute(
            """
            SELECT
                x.interaction_id,
                x.interaction_type,
                x.severity,
                x.conflict_scope,
                x.mechanism,
                x.description,
                x.source_citation,
                partner.ingridient_id AS partner_id,
                partner.inci_name AS partner_name
            FROM interactions x
            JOIN ingredients partner
              ON partner.ingridient_id = CASE
                    WHEN x.ingredient_a_id = %(id)s THEN x.ingredient_b_id
                    ELSE x.ingredient_a_id
                 END
            WHERE x.ingredient_a_id = %(id)s OR x.ingredient_b_id = %(id)s
            ORDER BY
                CASE x.severity WHEN 'high' THEN 3 WHEN 'medium' THEN 2 ELSE 1 END DESC,
                partner.inci_name
            """,
            {"id": ingredient_id},
        )
        ingredient["interactions"] = [
            {**dict(item), "partner_display_name": display_inci_name(item["partner_name"])}
            for item in cur.fetchall()
        ]

        if ingredient["functions"]:
            cur.execute(
                """
                SELECT i.ingridient_id AS id, i.inci_name, i.category
                FROM ingredients i
                WHERE i.functions && %(functions)s::text[]
                  AND i.ingridient_id <> %(id)s
                ORDER BY (i.source = 'curated') DESC, i.interaction_count DESC,
                         length(i.inci_name), i.inci_name
                LIMIT 6
                """,
                {"functions": ingredient["functions"][:1], "id": ingredient_id},
            )
            ingredient["related"] = [
                {**dict(item), "display_name": display_inci_name(item["inci_name"])}
                for item in cur.fetchall()
            ]
        else:
            ingredient["related"] = []

    return ingredient


_facet_cache: dict[str, tuple[float, Any]] = {}
_facet_lock = threading.Lock()


def _cached(key: str, producer):
    """Serve a value for up to `FACET_CACHE_TTL_SECONDS`.

    The lock keeps concurrent misses from all running the producer at once; the
    dict was previously mutated from request threads without one.
    """
    now = time.monotonic()
    hit = _facet_cache.get(key)
    if hit and now - hit[0] < FACET_CACHE_TTL_SECONDS:
        return hit[1]

    with _facet_lock:
        hit = _facet_cache.get(key)
        if hit and time.monotonic() - hit[0] < FACET_CACHE_TTL_SECONDS:
            return hit[1]
        value = producer()
        _facet_cache[key] = (time.monotonic(), value)
        return value


def clear_facet_cache() -> None:
    with _facet_lock:
        _facet_cache.clear()


def catalog_total() -> int:
    """Row count of the whole catalog. Cached; it changes only on import."""

    def produce() -> int:
        with get_cursor() as cur:
            cur.execute("SELECT COUNT(*)::int AS total FROM ingredients")
            return cur.fetchone()["total"]

    return _cached("catalog_total", produce)


def get_catalog_facets() -> dict:
    """Filter options and catalog stats. Cached; the catalog changes rarely."""

    def produce() -> dict:
        with get_cursor() as cur:
            cur.execute(
                """
                SELECT f AS value, COUNT(*)::int AS count
                FROM ingredients i, unnest(i.functions) AS f
                GROUP BY f
                ORDER BY count DESC, value
                """
            )
            functions = [dict(row) for row in cur.fetchall()]

            cur.execute(
                """
                SELECT
                    CASE
                        WHEN upper(left(inci_name, 1)) ~ '^[A-Z]$'
                        THEN upper(left(inci_name, 1))
                        ELSE '#'
                    END AS letter,
                    COUNT(*)::int AS count
                FROM ingredients
                GROUP BY letter
                ORDER BY letter
                """
            )
            letters = [dict(row) for row in cur.fetchall()]

            cur.execute(
                """
                SELECT
                    COUNT(*)::int AS total,
                    COUNT(*) FILTER (WHERE source = 'curated')::int AS curated,
                    COUNT(*) FILTER (WHERE description IS NOT NULL)::int AS with_description,
                    COUNT(*) FILTER (WHERE cardinality(alt_names) > 0)::int AS with_alt_names,
                    COUNT(*) FILTER (WHERE interaction_count > 0)::int AS with_interactions,
                    COUNT(*) FILTER (
                        WHERE restriction IS NOT NULL AND restriction <> ''
                    )::int AS with_restriction
                FROM ingredients
                """
            )
            stats = dict(cur.fetchone())

        return {"functions": functions, "letters": letters, "stats": stats}

    return _cached("facets", produce)
