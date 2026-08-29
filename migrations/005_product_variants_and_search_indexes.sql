-- Follow-up to 004.
--
-- 1. One SPL document can describe several distinct marketed products (different
--    strengths or pack forms, each with its own ingredient list). The unique
--    index on `setid` alone forced all of them onto a single row, so every
--    variant after the first silently overwrote the previous one and users could
--    be shown the ingredient list of a product they did not search for.
--    The replacement key keeps one row per (label, variant), identified by NDC
--    where the label provides one and by product name otherwise.
--
-- 2. Product lookup stripped every non-ASCII character from the query before
--    matching, so "Bioré" became the token "bior" and never matched a stored
--    "Biore", while "L'Oréal" became "or" + "al" and matched almost everything.
--    A folded search column fixes both ends of the comparison and, unlike the
--    three OR'd LIKE conditions it replaces, can be trigram-indexed.
--
--    `unaccent()` is STABLE, not IMMUTABLE, so it cannot appear in a generated
--    column or an index expression. The column is maintained by a trigger for
--    the same reason `search_document` on `ingredients` is.
--
-- 3. The catalog browse view (no query, no filters) sorts 22k rows by
--    curated-first, then interaction count. Without a matching index that is a
--    full scan plus sort on every page load.
--
-- Idempotent. The new product key is strictly more permissive than the one it
-- replaces, so no existing row can violate it.

BEGIN;

CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 1. Product variant identity ------------------------------------------------
DROP INDEX IF EXISTS products_setid_key;

CREATE UNIQUE INDEX IF NOT EXISTS products_setid_variant_key
    ON products (setid, COALESCE(NULLIF(ndc, ''), lower(name)))
    WHERE setid IS NOT NULL;

-- 2. Accent-folded product search -------------------------------------------
ALTER TABLE products ADD COLUMN IF NOT EXISTS search_text TEXT;

CREATE OR REPLACE FUNCTION products_search_text_refresh()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.search_text := unaccent(lower(
        coalesce(NEW.brand, '') || ' ' ||
        coalesce(NEW.name, '') || ' ' ||
        coalesce(array_to_string(NEW.search_aliases, ' '), '')
    ));
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS products_search_text_trg ON products;
CREATE TRIGGER products_search_text_trg
    BEFORE INSERT OR UPDATE OF brand, name, search_aliases
    ON products
    FOR EACH ROW
    EXECUTE FUNCTION products_search_text_refresh();

-- Backfill existing rows (no-op on re-run beyond recomputing the same value).
UPDATE products SET name = name WHERE search_text IS NULL;

CREATE INDEX IF NOT EXISTS products_search_text_trgm_idx
    ON products USING GIN (search_text gin_trgm_ops);

-- Only rows with an ingredient list are ever returned by search_local.
CREATE INDEX IF NOT EXISTS products_has_ingredients_idx
    ON products (product_id)
    WHERE raw_ingredient_list <> '';

-- 3. Catalog browse ordering -------------------------------------------------
CREATE INDEX IF NOT EXISTS ingredients_browse_idx
    ON ingredients (((source = 'curated')) DESC, interaction_count DESC, inci_name);

COMMIT;
