#!/usr/bin/env python3
"""Import published ingredient lists for catalog brands.

Sources, in order:
  1. FDA DailyMed (OTC/drug labels; never overwritten later)
  2. Official storefront pages (Shopify / Demandware / CPNP)
  3. Open Beauty Facts records that already include an INCI list

We do not invent formulas. Products whose public page has no parseable INCI
are skipped.

Usage
-----
    python scripts/import_brand_catalogs.py
    python scripts/import_brand_catalogs.py --brand COSRX --brand Minimalist
    python scripts/import_brand_catalogs.py --skip-dailymed --skip-obf
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from skincaresync.brand_catalog import (  # noqa: E402
    DAILYMED_BRANDS,
    DEMANDWARE_CATALOGS,
    OBF_BRAND_QUERIES,
    SHOPIFY_STORES,
    brands_wanted,
    catalog_brands,
    iter_cpnp_pages,
    iter_demandware_products,
    iter_obf_brand,
    iter_shopify_products,
)
from skincaresync.dailymed import fetch_setid, search_spls  # noqa: E402
from skincaresync.lookup import ProductLookupResult  # noqa: E402
from skincaresync.product_catalog import find_existing, upsert_product  # noqa: E402

PROTECTED_SOURCES = {"dailymed"}


def store_product(product: ProductLookupResult, dry_run: bool) -> str:
    existing = find_existing(product)
    if existing:
        if existing.source in PROTECTED_SOURCES:
            return "protected"
        if existing.source == "manual" and existing.raw_ingredient_list.strip():
            return "exists"
    if not dry_run:
        upsert_product(product)
    return "stored"


def import_dailymed(brands: list[str], max_labels: int, dry_run: bool) -> dict:
    stats = {"stored": 0, "skipped": 0, "failed": 0}
    for brand in DAILYMED_BRANDS:
        if not brands_wanted(brand, brands):
            continue
        print(f"\nDailyMed: {brand}")
        try:
            rows = search_spls(brand, pagesize=max_labels)
        except Exception:
            stats["failed"] += 1
            print("  failed to search")
            continue
        for row in rows[:max_labels]:
            setid = row.get("setid")
            if not setid:
                continue
            try:
                products = fetch_setid(setid, listing_title=row.get("title"))
            except Exception:
                stats["failed"] += 1
                continue
            for product in products:
                status = store_product(product, dry_run)
                if status == "stored":
                    stats["stored"] += 1
                    print(
                        f"  {product.brand} | {product.name} | "
                        f"{len(product.raw_ingredient_list.split(','))} ingredients"
                    )
                else:
                    stats["skipped"] += 1
    return stats


def _wanted_store(name: str, brands: list[str]) -> bool:
    return brands_wanted(name, brands)


def import_storefronts(brands: list[str], limit: int | None, dry_run: bool) -> dict:
    stats = {"stored": 0, "skipped": 0, "no_inci": 0}
    for store in SHOPIFY_STORES:
        if not _wanted_store(store.brand, brands):
            continue
        print(f"\nStorefront: {store.brand} ({store.base_url})")
        try:
            if store.brand == "Beauty of Joseon":
                for product in iter_cpnp_pages(store, limit=limit):
                    status = store_product(product, dry_run)
                    if status == "stored":
                        stats["stored"] += 1
                        print(
                            f"  CPNP {product.name} | "
                            f"{len(product.raw_ingredient_list.split(','))} ingredients"
                        )
                    else:
                        stats["skipped"] += 1
            seen = 0
            for product in iter_shopify_products(store, limit=limit):
                seen += 1
                status = store_product(product, dry_run)
                if status == "stored":
                    stats["stored"] += 1
                    print(
                        f"  {product.name} | "
                        f"{len(product.raw_ingredient_list.split(','))} ingredients"
                    )
                else:
                    stats["skipped"] += 1
            if seen == 0:
                print("  no parseable INCI lists on indexed products")
                stats["no_inci"] += 1
        except Exception as exc:
            print(f"  failed: {type(exc).__name__}: {exc}")
    for catalog in DEMANDWARE_CATALOGS:
        if not _wanted_store(catalog.brand, brands):
            continue
        print(f"\nStorefront: {catalog.brand}")
        try:
            for product in iter_demandware_products(catalog, limit=limit):
                status = store_product(product, dry_run)
                if status == "stored":
                    stats["stored"] += 1
                    print(
                        f"  {product.name} | "
                        f"{len(product.raw_ingredient_list.split(','))} ingredients"
                    )
                else:
                    stats["skipped"] += 1
        except Exception as exc:
            print(f"  failed: {type(exc).__name__}: {exc}")
    return stats


def import_obf(brands: list[str], dry_run: bool) -> dict:
    stats = {"stored": 0, "skipped": 0}
    for brand, query in OBF_BRAND_QUERIES:
        if not brands_wanted(brand, brands):
            continue
        print(f"\nOpen Beauty Facts: {brand}")
        products = iter_obf_brand(brand, query)
        print(f"  candidates with INCI: {len(products)}")
        for product in products:
            status = store_product(product, dry_run)
            if status == "stored":
                stats["stored"] += 1
            else:
                stats["skipped"] += 1
        print(f"  stored={stats['stored']} skipped={stats['skipped']} (running totals)")
    return stats


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--brand",
        action="append",
        dest="brands",
        help="Limit to these brand names (repeatable). Defaults to the core catalog brand list.",
    )
    parser.add_argument("--skip-dailymed", action="store_true")
    parser.add_argument("--skip-storefronts", action="store_true")
    parser.add_argument("--skip-obf", action="store_true")
    parser.add_argument("--max-dailymed-labels", type=int, default=60)
    parser.add_argument("--limit", type=int, default=None, help="Max storefront products per brand.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    brands = args.brands or list(catalog_brands())
    print("Brands:", ", ".join(brands))

    totals = {"stored": 0, "skipped": 0}
    if not args.skip_dailymed:
        stats = import_dailymed(brands, args.max_dailymed_labels, args.dry_run)
        totals["stored"] += stats["stored"]
        totals["skipped"] += stats["skipped"]
    if not args.skip_storefronts:
        stats = import_storefronts(brands, args.limit, args.dry_run)
        totals["stored"] += stats["stored"]
        totals["skipped"] += stats["skipped"]
    if not args.skip_obf:
        stats = import_obf(brands, args.dry_run)
        totals["stored"] += stats["stored"]
        totals["skipped"] += stats["skipped"]

    print(
        f"\n{'Would store' if args.dry_run else 'Stored'} {totals['stored']} "
        f"new lists; skipped {totals['skipped']} existing/protected rows"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
