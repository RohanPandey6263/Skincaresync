This application includes the Open Beauty Facts cosmetic ingredient taxonomy.

Source
------
https://static.openbeautyfacts.org/data/taxonomies/ingredients.json

The taxonomy is derived from the European Commission's CosIng database
(Cosmetic Ingredient Database), which is the official EU inventory of INCI
names, functions, CAS/EC numbers and annex restrictions.

Licences
--------
* Open Beauty Facts data: Open Database License (ODbL) v1.0
  https://opendatacommons.org/licenses/odbl/1.0/
* Individual contents of that database: Database Contents License (DbCL) v1.0
* CosIng: European Commission reuse policy (CC BY 4.0 / Commission reuse notice)
* FDA DailyMed Structured Product Labels: US government work, public domain
  https://dailymed.nlm.nih.gov/

The importers in `scripts/` identify themselves as `SkincareSyncBot`. Set
`CATALOG_USER_AGENT` only if a brand has given you permission to crawl and
requires a particular string.

Brand-published cosmetic INCI lists stored in `products` (source `manual`) are
transcribed from the brand or authorized retailer page linked on each row.
Those lists are facts printed on packaging; they can change when a product is
reformulated. Re-check the linked page or the bottle before relying on an
older cache.

ODbL obligations
----------------
You may copy, distribute, and adapt the catalog, including for commercial use,
provided that:

1. Attribution — credit Open Beauty Facts contributors and CosIng as above.
2. Share-alike — if you publicly redistribute an adapted version of this
   database, offer that adapted database under ODbL.
3. Keep open — do not use technical measures that prevent others from obtaining
   an ODbL-licensed copy of the database.

The original 141-row curated ingredient catalog and the compatibility
`interactions` table are original SkincareSync work and are not derived from
Open Beauty Facts.

Re-import
---------
    psql -d "$PGDATABASE" -f migrations/002_ingredient_catalog.sql
    psql -d "$PGDATABASE" -f migrations/003_ingredient_search_alias.sql
    python scripts/import_ingredient_catalog.py --refresh
    psql -d "$PGDATABASE" -f migrations/004_product_catalog.sql
    psql -d "$PGDATABASE" -f migrations/005_product_variants_and_search_indexes.sql
    python scripts/import_product_catalog.py
    python scripts/import_published_products.py --family vitamin-c
    python scripts/import_brand_catalogs.py
