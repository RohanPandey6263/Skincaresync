#!/usr/bin/env python3
"""Import the Open Beauty Facts cosmetic ingredient taxonomy into `ingredients`.

Source
------
Open Beauty Facts ingredient taxonomy, which is derived from the European
Commission's CosIng database (each entry carries its CosIng reference number).

    https://static.openbeautyfacts.org/data/taxonomies/ingredients.json

Licence
-------
Open Database License (ODbL) v1.0 — reuse for any purpose is permitted provided
the source is attributed and derived databases are shared alike. No API key, no
authentication and no rate limit applies to this static export. See ATTRIBUTION.md.

Safety guarantees
-----------------
* Existing curated rows keep their `ingridient_id`, so every foreign key in
  `interactions`, `parser_unknowns` and `interaction_gaps` stays valid.
* Curated values (`ph_min`, `ph_max`, `comodogenic`, `synonyms`, `category`) are
  never overwritten — imported data only fills gaps.
* Idempotent: re-running enriches rather than duplicating.

Usage
-----
    python scripts/import_ingredient_catalog.py            # download + import
    python scripts/import_ingredient_catalog.py --file X    # import a local copy
    python scripts/import_ingredient_catalog.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from psycopg2.extras import execute_values  # noqa: E402

from skincaresync.database import get_conn  # noqa: E402
from skincaresync.ingredients import clear_facet_cache  # noqa: E402
from skincaresync.parser import clear_shared_resolver, normalize_token  # noqa: E402

SOURCE_NAME = "open-beauty-facts"
SOURCE_URL = "https://static.openbeautyfacts.org/data/taxonomies/ingredients.json"
SOURCE_LICENSE = "ODbL-1.0"
UPSTREAM_ORIGIN = "European Commission CosIng"
USER_AGENT = "SkincareSync ingredient catalog importer (+local development)"
CACHE_PATH = Path(__file__).resolve().parents[1] / "data" / "obf_ingredients.json"

# Fields whose upstream values are treated as alternate names for search.
ALT_NAME_FIELDS = ("inn-name", "ph-eur-name", "inci", "iupac")


def download(url: str, destination: Path) -> str:
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        last_modified = response.headers.get("Last-Modified", "")
        destination.write_bytes(response.read())
    return last_modified


def _en(value: dict | None) -> str:
    if not isinstance(value, dict):
        return ""
    return (value.get("en") or "").strip()


def _parse_functions(raw: str) -> list[str]:
    """'en:skin-conditioning, en:emollient' -> ['skin-conditioning', 'emollient']"""
    functions = []
    for part in (raw or "").split(","):
        slug = part.strip()
        if not slug:
            continue
        functions.append(slug.split(":", 1)[1] if ":" in slug else slug)
    return sorted(set(functions))


def _parse_update_date(raw: str) -> date | None:
    raw = (raw or "").strip()
    if not raw:
        return None
    try:
        day, month, year = raw.split("/")
        return date(int(year), int(month), int(day))
    except (ValueError, TypeError):
        return None


def build_records(taxonomy: dict) -> tuple[list[dict], int]:
    """Normalize taxonomy entries and collapse normalized-name duplicates."""
    by_key: dict[str, dict] = {}
    duplicates = 0

    for obf_id, entry in taxonomy.items():
        names = entry.get("name") or {}
        canonical = (names.get("en") or "").strip()
        if not canonical:
            continue

        normalized = normalize_token(canonical)
        if not normalized:
            continue

        alt: list[str] = []
        for language, value in names.items():
            if language == "en":
                continue
            text = (value or "").strip()
            if text:
                alt.append(text)
        for field in ALT_NAME_FIELDS:
            text = _en(entry.get(field))
            if text:
                alt.append(text)

        seen: set[str] = {canonical.casefold()}
        alt_names: list[str] = []
        for text in alt:
            folded = text.casefold()
            if folded not in seen:
                seen.add(folded)
                alt_names.append(text)

        functions = _parse_functions(_en(entry.get("inci_functions")))
        record = {
            "obf_id": obf_id,
            "inci_name": canonical,
            "normalized": normalized,
            "alt_names": alt_names,
            "description": _en(entry.get("inci_description")) or None,
            "functions": functions,
            "category": functions[0] if functions else None,
            "cas_number": _en(entry.get("cas")) or None,
            "einecs_number": _en(entry.get("einecs")) or None,
            "inn_name": _en(entry.get("inn-name")) or None,
            "ph_eur_name": _en(entry.get("ph-eur-name")) or None,
            "cosing_ref": _en(entry.get("cosing")) or None,
            "wikidata_id": _en(entry.get("wikidata")) or None,
            "restriction": _en(entry.get("inci_restriction")) or None,
            "source_updated_on": _parse_update_date(_en(entry.get("inci_update_date"))),
        }

        existing = by_key.get(normalized)
        if existing is None:
            by_key[normalized] = record
            continue

        duplicates += 1
        by_key[normalized] = _merge(existing, record)

    return list(by_key.values()), duplicates


def _completeness(record: dict) -> int:
    return sum(1 for value in record.values() if value)


def _merge(keep: dict, other: dict) -> dict:
    """Keep the richer of two colliding records, absorbing the other's aliases."""
    primary, secondary = (
        (keep, other) if _completeness(keep) >= _completeness(other) else (other, keep)
    )
    merged = dict(primary)

    seen = {merged["inci_name"].casefold(), *(n.casefold() for n in merged["alt_names"])}
    extra = [secondary["inci_name"], *secondary["alt_names"]]
    for name in extra:
        folded = name.casefold()
        if folded not in seen:
            seen.add(folded)
            merged["alt_names"] = [*merged["alt_names"], name]

    for field, value in secondary.items():
        if field in {"inci_name", "normalized", "alt_names"}:
            continue
        if not merged.get(field) and value:
            merged[field] = value

    return merged


def import_records(conn, records: list[dict], dry_run: bool) -> dict:
    cur = conn.cursor()

    # Map every existing row by normalized name. Curated rows win ties so that
    # imported data enriches the hand-authored entry rather than a near-duplicate.
    cur.execute(
        """
        SELECT ingridient_id, normalized_name, source
        FROM ingredients
        ORDER BY (source = 'curated') DESC, ingridient_id
        """
    )
    existing: dict[str, int] = {}
    for ingredient_id, normalized, _source in cur.fetchall():
        if normalized:
            existing.setdefault(normalized, ingredient_id)

    to_insert = [r for r in records if r["normalized"] not in existing]
    to_enrich = [
        (existing[r["normalized"]], r) for r in records if r["normalized"] in existing
    ]

    stats = {
        "entries_read": len(records),
        "inserted": len(to_insert),
        "enriched": len(to_enrich),
    }
    if dry_run:
        return stats

    if to_insert:
        execute_values(
            cur,
            """
            INSERT INTO ingredients (
                inci_name, synonyms, category, alt_names, description, functions,
                cas_number, einecs_number, inn_name, ph_eur_name, cosing_ref,
                obf_id, wikidata_id, restriction, source, source_updated_on
            ) VALUES %s
            ON CONFLICT (obf_id) WHERE obf_id IS NOT NULL DO NOTHING
            """,
            [
                (
                    r["inci_name"],
                    [],
                    r["category"],
                    r["alt_names"],
                    r["description"],
                    r["functions"],
                    r["cas_number"],
                    r["einecs_number"],
                    r["inn_name"],
                    r["ph_eur_name"],
                    r["cosing_ref"],
                    r["obf_id"],
                    r["wikidata_id"],
                    r["restriction"],
                    SOURCE_NAME,
                    r["source_updated_on"],
                )
                for r in to_insert
            ],
            page_size=1000,
        )

    if to_enrich:
        # COALESCE keeps curated values authoritative; alt_names are unioned so
        # translations add to, rather than replace, curated synonyms.
        execute_values(
            cur,
            """
            UPDATE ingredients AS i SET
                alt_names = ARRAY(
                    SELECT DISTINCT unnest(i.alt_names || v.alt_names)
                ),
                description = COALESCE(i.description, v.description),
                functions = CASE
                    WHEN cardinality(i.functions) = 0 THEN v.functions
                    ELSE i.functions
                END,
                category = COALESCE(i.category, v.category),
                cas_number = COALESCE(i.cas_number, v.cas_number),
                einecs_number = COALESCE(i.einecs_number, v.einecs_number),
                inn_name = COALESCE(i.inn_name, v.inn_name),
                ph_eur_name = COALESCE(i.ph_eur_name, v.ph_eur_name),
                cosing_ref = COALESCE(i.cosing_ref, v.cosing_ref),
                obf_id = COALESCE(i.obf_id, v.obf_id),
                wikidata_id = COALESCE(i.wikidata_id, v.wikidata_id),
                restriction = COALESCE(i.restriction, v.restriction),
                source_updated_on = COALESCE(i.source_updated_on, v.source_updated_on)
            FROM (VALUES %s) AS v (
                ingridient_id, alt_names, description, functions, category,
                cas_number, einecs_number, inn_name, ph_eur_name, cosing_ref,
                obf_id, wikidata_id, restriction, source_updated_on
            )
            WHERE i.ingridient_id = v.ingridient_id
            """,
            [
                (
                    ingredient_id,
                    r["alt_names"],
                    r["description"],
                    r["functions"],
                    r["category"],
                    r["cas_number"],
                    r["einecs_number"],
                    r["inn_name"],
                    r["ph_eur_name"],
                    r["cosing_ref"],
                    r["obf_id"],
                    r["wikidata_id"],
                    r["restriction"],
                    r["source_updated_on"],
                )
                for ingredient_id, r in to_enrich
            ],
            template=(
                "(%s, %s::text[], %s, %s::text[], %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::date)"
            ),
            page_size=500,
        )

    # Data-driven popularity: how many interaction rules mention this ingredient.
    cur.execute(
        """
        UPDATE ingredients i
        SET interaction_count = COALESCE(counts.total, 0)
        FROM (
            SELECT id, COUNT(*) AS total
            FROM (
                SELECT ingredient_a_id AS id FROM interactions
                UNION ALL
                SELECT ingredient_b_id AS id FROM interactions
            ) refs
            GROUP BY id
        ) counts
        WHERE i.ingridient_id = counts.id
          AND i.interaction_count <> counts.total
        """
    )
    return stats


def record_run(conn, stats: dict, last_modified: str, duplicates: int) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO ingredient_import_runs (
                source, source_url, source_license, source_last_modified,
                entries_read, inserted, enriched, skipped_duplicates
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                f"{SOURCE_NAME} (derived from {UPSTREAM_ORIGIN})",
                SOURCE_URL,
                SOURCE_LICENSE,
                last_modified,
                stats["entries_read"],
                stats["inserted"],
                stats["enriched"],
                duplicates,
            ),
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, help="Use a local taxonomy JSON file")
    parser.add_argument("--dry-run", action="store_true", help="Report without writing")
    parser.add_argument(
        "--refresh", action="store_true", help="Re-download even if cached"
    )
    args = parser.parse_args()

    source_path = args.file or CACHE_PATH
    last_modified = ""
    if args.file is None and (args.refresh or not CACHE_PATH.exists()):
        print(f"Downloading {SOURCE_URL}")
        last_modified = download(SOURCE_URL, CACHE_PATH)

    if not source_path.exists():
        print(f"Taxonomy file not found: {source_path}", file=sys.stderr)
        return 1

    print(f"Reading {source_path}")
    taxonomy = json.loads(source_path.read_text())
    records, duplicates = build_records(taxonomy)
    print(
        f"Parsed {len(taxonomy)} entries -> {len(records)} unique ingredients "
        f"({duplicates} normalized duplicates merged)"
    )

    with get_conn() as conn:
        stats = import_records(conn, records, args.dry_run)
        if not args.dry_run:
            record_run(conn, stats, last_modified, duplicates)

    print(
        f"{'DRY RUN: would insert' if args.dry_run else 'Inserted'} {stats['inserted']}, "
        f"{'would enrich' if args.dry_run else 'enriched'} {stats['enriched']}"
    )
    if not args.dry_run:
        clear_facet_cache()
        clear_shared_resolver()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
