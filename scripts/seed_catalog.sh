#!/usr/bin/env sh
# Populate the catalogs a fresh database cannot build from SQL alone.
#
# The migration chain seeds the 141 curated ingredients and the interaction
# rules. Everything below is fetched from the network -- the Open Beauty Facts
# taxonomy (~22,000 INCI names), FDA DailyMed OTC labels, and brand-published
# INCI lists -- so it is a separate, re-runnable step rather than part of the
# migration.
#
# Every importer is idempotent: re-running enriches rather than duplicating.
# Expect this to take several minutes, most of it in the brand catalogs.
#
#     ./scripts/seed_catalog.sh              # against PG* in the environment
#     docker compose run --rm seed           # against the compose database
set -eu

cd "$(dirname "$0")/.."

# Use the venv's interpreter when there is one, so this works both on a
# developer machine and inside the container, where python is already on PATH.
if [ -x venv/bin/python ]; then
    python=venv/bin/python
elif [ -x .venv/bin/python ]; then
    python=.venv/bin/python
else
    python=python3
fi

echo "==> Ingredient catalog (Open Beauty Facts / CosIng taxonomy)"
"$python" scripts/import_ingredient_catalog.py

echo "==> OTC product labels (FDA DailyMed)"
"$python" scripts/import_product_catalog.py

echo "==> Brand-published vitamin C lists"
"$python" scripts/import_published_products.py --family vitamin-c

echo "==> Remaining brand catalogs"
"$python" scripts/import_brand_catalogs.py

echo "==> Done."
