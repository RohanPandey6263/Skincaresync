-- Local product catalog: persist ingredient lists so lookups do not depend on
-- Open Beauty Facts having a complete record.
--
-- Sources:
--   dailymed           FDA Structured Product Labels (OTC/drug products)
--   open_beauty_facts  cached community records that did include an INCI list
--   manual             curated rows
--
-- Idempotent.

BEGIN;

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS ndc TEXT,
    ADD COLUMN IF NOT EXISTS setid TEXT,
    ADD COLUMN IF NOT EXISTS product_url TEXT,
    ADD COLUMN IF NOT EXISTS image_url TEXT,
    ADD COLUMN IF NOT EXISTS search_aliases TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW();

ALTER TABLE products DROP CONSTRAINT IF EXISTS products_source_check;
ALTER TABLE products
    ADD CONSTRAINT products_source_check
    CHECK (source IN (
        'manual',
        'open_beauty_facts',
        'user_submitted',
        'dailymed'
    ));

-- One stored row per DailyMed label; barcodes remain unique when present.
CREATE UNIQUE INDEX IF NOT EXISTS products_setid_key
    ON products (setid)
    WHERE setid IS NOT NULL;

CREATE INDEX IF NOT EXISTS products_ndc_idx
    ON products (ndc)
    WHERE ndc IS NOT NULL;

CREATE INDEX IF NOT EXISTS products_brand_name_idx
    ON products (LOWER(brand), LOWER(name));

CREATE INDEX IF NOT EXISTS products_aliases_idx
    ON products USING GIN (search_aliases);

COMMIT;
