#!/usr/bin/env python3
"""Import OTC / drug product labels from FDA DailyMed into `products`.

This fills the gap Open Beauty Facts leaves for medicated skincare — products
like PanOxyl, where the community record exists but has no ingredient list.

Usage
-----
    python scripts/import_product_catalog.py
    python scripts/import_product_catalog.py --drug-name panoxyl --drug-name differin
    python scripts/import_product_catalog.py --family vitamin-c
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from skincaresync.dailymed import fetch_setid, search_spls  # noqa: E402
from skincaresync.lookup import Deadline  # noqa: E402
from skincaresync.product_catalog import upsert_products  # noqa: E402
from scripts.import_published_products import import_family  # noqa: E402

# An offline import is not a user request, so it does not share the API's short
# per-request budget. Each HTTP call gets its own generous allowance.
IMPORT_TIMEOUT_SECONDS = 30

DEFAULT_SEED = (
    "panoxyl",
    "differin",
    "proactiv",
    "clearasil",
    "neutrogena stubborn acne",
)


def import_drug_name(drug_name: str, max_labels: int, dry_run: bool) -> dict:
    rows = search_spls(drug_name, Deadline(IMPORT_TIMEOUT_SECONDS), pagesize=max_labels)
    stats = {"labels": 0, "products": 0, "failed": 0}
    # Collected and written once per drug name rather than one connection,
    # transaction and commit per product.
    pending = []
    for row in rows[:max_labels]:
        setid = row.get("setid")
        if not setid:
            continue
        try:
            products = fetch_setid(
                setid, Deadline(IMPORT_TIMEOUT_SECONDS), listing_title=row.get("title")
            )
        except Exception:
            stats["failed"] += 1
            continue
        stats["labels"] += 1
        for product in products:
            stats["products"] += 1
            print(f"  {product.brand} | {product.name} | {len(product.raw_ingredient_list.split(','))} ingredients")
            pending.append(product)

    if pending and not dry_run:
        stats["stored"] = upsert_products(pending)
    return stats


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--drug-name",
        action="append",
        dest="drug_names",
        help="DailyMed drug_name query (repeatable). Defaults to a high-conflict OTC seed.",
    )
    parser.add_argument("--max-labels", type=int, default=12)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--family",
        action="append",
        dest="families",
        choices=("vitamin-c",),
        help="Also import brand-published cosmetic lists Open Beauty Facts lacks.",
    )
    args = parser.parse_args()

    total_products = 0
    if args.families:
        for family in args.families:
            print(f"\nPublished labels: {family}")
            stats = import_family(family, dry_run=args.dry_run)
            total_products += stats["stored"]
            print(f"  stored={stats['stored']} skipped={stats['skipped']}")

    if args.drug_names or not args.families:
        names = args.drug_names or list(DEFAULT_SEED)
        for name in names:
            print(f"\nDailyMed: {name}")
            stats = import_drug_name(name, max_labels=args.max_labels, dry_run=args.dry_run)
            total_products += stats["products"]
            print(
                f"  labels={stats['labels']} products={stats['products']} failed={stats['failed']}"
            )
    print(f"\n{'Would store' if args.dry_run else 'Stored'} {total_products} product ingredient lists")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
