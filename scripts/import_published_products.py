#!/usr/bin/env python3
"""Store brand-published INCI lists for products Open Beauty Facts does not have.

Usage
-----
    python scripts/import_published_products.py
    python scripts/import_published_products.py --family vitamin-c
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from skincaresync.lookup import ProductLookupResult  # noqa: E402
from skincaresync.product_catalog import upsert_product  # noqa: E402
from skincaresync.published_labels import (  # noqa: E402
    FAMILY_ALIASES,
    aliases_for,
    contains_vitamin_c,
    normalize_published_inci,
    products_for_family,
)


def import_family(family: str, dry_run: bool) -> dict:
    stats = {"stored": 0, "skipped": 0}
    for item in products_for_family(family):
        inci = normalize_published_inci(item.raw_ingredient_list)
        if len(inci.split(",")) < 2 or (
            family == "vitamin-c" and not contains_vitamin_c(inci)
        ):
            stats["skipped"] += 1
            print(f"  SKIP {item.brand} | {item.name} (incomplete or missing active)")
            continue
        product = ProductLookupResult(
            code=None,
            brand=item.brand,
            name=item.name,
            raw_ingredient_list=inci,
            source="manual",
            product_url=item.product_url,
            search_aliases=aliases_for(item),
        )
        print(
            f"  {product.brand} | {product.name} | "
            f"{len(product.raw_ingredient_list.split(','))} ingredients"
        )
        if not dry_run:
            upsert_product(product)
        stats["stored"] += 1
    return stats


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--family",
        action="append",
        dest="families",
        choices=sorted(FAMILY_ALIASES),
        help="Ingredient family to import (repeatable). Defaults to vitamin-c.",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    families = args.families or ["vitamin-c"]
    total = 0
    for family in families:
        print(f"\nPublished labels: {family}")
        stats = import_family(family, dry_run=args.dry_run)
        total += stats["stored"]
        print(f"  stored={stats['stored']} skipped={stats['skipped']}")
    print(f"\n{'Would store' if args.dry_run else 'Stored'} {total} product ingredient lists")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
