-- SkincareSync migration 002: large-scale ingredient catalog + search infrastructure.
--
-- Base schema lives in aidatabase.sql (migration 001). This migration extends the
-- existing `ingredients` table in place so that every foreign key in
-- `interactions`, `parser_unknowns` and `interaction_gaps` keeps pointing at the
-- same `ingridient_id` values. No curated row is deleted or renumbered.
--
-- Data source: Open Beauty Facts cosmetic ingredient taxonomy (derived from the
-- European Commission CosIng database). Licensed under the Open Database License
-- (ODbL) v1.0. See ATTRIBUTION.md.
--
-- Idempotent: safe to re-run.

BEGIN;

-- Trigram matching powers typo tolerance and partial matching; unaccent lets
-- accented international names match their unaccented spelling.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- ---------------------------------------------------------------------------
-- INCI normalization, mirrored from skincaresync.parser.normalize_token so that
-- SQL-side lookups and the Python resolver agree on what "the same ingredient"
-- means. Must stay IMMUTABLE to be usable in a generated column and an index.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION inci_normalize(value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT lower(
        btrim(
            regexp_replace(
                regexp_replace(
                    regexp_replace(
                        regexp_replace(coalesce(value, ''), '\d+(\.\d+)?\s*%', '', 'g'),
                        '\([^)]*\)', '', 'g'
                    ),
                    '[\s.;:]+$', '', 'g'
                ),
                '\s+', ' ', 'g'
            )
        )
    );
$$;

-- ---------------------------------------------------------------------------
-- Catalog columns
-- ---------------------------------------------------------------------------

-- Real INCI names for multi-botanical ferment complexes run to ~1,900
-- characters, well past the original varchar(500). Widen rather than truncate,
-- so imported regulatory names stay intact. The generated normalized_name
-- column depends on inci_name, so it is dropped here and recreated below.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'ingredients'
          AND column_name = 'inci_name'
          AND data_type = 'character varying'
    ) THEN
        -- Both the generated column and the search trigger reference inci_name;
        -- each is recreated further down this migration.
        DROP TRIGGER IF EXISTS ingredients_search_document_trg ON ingredients;
        ALTER TABLE ingredients DROP COLUMN IF EXISTS normalized_name;
        ALTER TABLE ingredients
            ALTER COLUMN inci_name TYPE TEXT,
            ALTER COLUMN category TYPE TEXT;
    END IF;
END
$$;

ALTER TABLE ingredients
    ADD COLUMN IF NOT EXISTS alt_names TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS functions TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS cas_number TEXT,
    ADD COLUMN IF NOT EXISTS einecs_number TEXT,
    ADD COLUMN IF NOT EXISTS inn_name TEXT,
    ADD COLUMN IF NOT EXISTS ph_eur_name TEXT,
    ADD COLUMN IF NOT EXISTS cosing_ref TEXT,
    ADD COLUMN IF NOT EXISTS obf_id TEXT,
    ADD COLUMN IF NOT EXISTS wikidata_id TEXT,
    ADD COLUMN IF NOT EXISTS restriction TEXT,
    ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'curated',
    ADD COLUMN IF NOT EXISTS source_updated_on DATE,
    -- Denormalized count of interaction rules referencing this ingredient.
    -- Used to rank ingredients the compatibility engine actually knows about.
    ADD COLUMN IF NOT EXISTS interaction_count INTEGER NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'ingredients' AND column_name = 'normalized_name'
    ) THEN
        ALTER TABLE ingredients
            ADD COLUMN normalized_name TEXT
            GENERATED ALWAYS AS (inci_normalize(inci_name)) STORED;
    END IF;

END
$$;

-- One tsvector covering canonical name, every alternate/international name,
-- curated synonyms, chemical identifiers and the description.
--
-- Maintained by trigger rather than as a GENERATED column because
-- array_to_string() is only STABLE, so Postgres rejects it in a generation
-- expression. Marking a wrapper IMMUTABLE would be a lie about volatility.
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS search_document tsvector;

-- Flattened alternate + curated names. Searching these via
-- `EXISTS (SELECT ... FROM unnest(alt_names))` cannot use an index and forces a
-- sequential scan on every query; a single text column can be trigram-indexed.
ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS alias_text TEXT;

CREATE OR REPLACE FUNCTION ingredients_search_document_refresh()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.alias_text := array_to_string(
        NEW.alt_names || NEW.synonyms
            || ARRAY[coalesce(NEW.inn_name, ''), coalesce(NEW.ph_eur_name, '')],
        ' | '
    );
    NEW.search_document := to_tsvector(
        'english'::regconfig,
        coalesce(NEW.inci_name, '') || ' ' ||
        coalesce(array_to_string(NEW.alt_names, ' '), '') || ' ' ||
        coalesce(array_to_string(NEW.synonyms, ' '), '') || ' ' ||
        coalesce(NEW.inn_name, '') || ' ' ||
        coalesce(NEW.ph_eur_name, '') || ' ' ||
        coalesce(NEW.cas_number, '') || ' ' ||
        coalesce(NEW.einecs_number, '') || ' ' ||
        coalesce(NEW.category, '') || ' ' ||
        coalesce(array_to_string(NEW.functions, ' '), '') || ' ' ||
        coalesce(NEW.description, '')
    );
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS ingredients_search_document_trg ON ingredients;
CREATE TRIGGER ingredients_search_document_trg
    BEFORE INSERT OR UPDATE OF
        inci_name, alt_names, synonyms, inn_name, ph_eur_name,
        cas_number, einecs_number, category, functions, description
    ON ingredients
    FOR EACH ROW
    EXECUTE FUNCTION ingredients_search_document_refresh();

-- Backfill existing rows (no-op on re-run beyond recomputing the same value).
UPDATE ingredients SET inci_name = inci_name
WHERE search_document IS NULL OR alias_text IS NULL;

ALTER TABLE ingredients
    DROP CONSTRAINT IF EXISTS ingredients_source_check;
ALTER TABLE ingredients
    ADD CONSTRAINT ingredients_source_check
    CHECK (source IN ('curated', 'open-beauty-facts'));

-- ---------------------------------------------------------------------------
-- Search indexes
-- ---------------------------------------------------------------------------

-- Full-text search across the whole document.
CREATE INDEX IF NOT EXISTS ingredients_search_document_idx
    ON ingredients USING GIN (search_document);

-- Trigram indexes: partial matching ("cetyl alc") and typo tolerance ("niacinimide").
CREATE INDEX IF NOT EXISTS ingredients_inci_name_trgm_idx
    ON ingredients USING GIN (inci_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ingredients_normalized_name_trgm_idx
    ON ingredients USING GIN (normalized_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS ingredients_alias_text_trgm_idx
    ON ingredients USING GIN (alias_text gin_trgm_ops);

-- Exact/prefix lookups used by the resolver and by exact-match ranking.
CREATE INDEX IF NOT EXISTS ingredients_normalized_name_idx
    ON ingredients (normalized_name);

-- Array containment for alternate-name and category filtering.
CREATE INDEX IF NOT EXISTS ingredients_alt_names_idx
    ON ingredients USING GIN (alt_names);
CREATE INDEX IF NOT EXISTS ingredients_functions_idx
    ON ingredients USING GIN (functions);

-- Alphabetical browsing.
CREATE INDEX IF NOT EXISTS ingredients_initial_idx
    ON ingredients (upper(left(inci_name, 1)));

-- Import identity: one row per upstream taxonomy entry, enabling idempotent upserts.
CREATE UNIQUE INDEX IF NOT EXISTS ingredients_obf_id_key
    ON ingredients (obf_id) WHERE obf_id IS NOT NULL;

-- Note: normalized_name is deliberately NOT unique. The curated catalog contains
-- intentional near-duplicates such as 'Hydroquinone' and 'Hydroquinone 4%', which
-- both normalize to 'hydroquinone' and are both referenced by interaction rules.
-- Import-time deduplication is handled in scripts/import_ingredient_catalog.py.

CREATE INDEX IF NOT EXISTS ingredients_source_idx ON ingredients (source);
CREATE INDEX IF NOT EXISTS ingredients_interaction_count_idx
    ON ingredients (interaction_count DESC);

-- ---------------------------------------------------------------------------
-- Provenance of each bulk import run.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ingredient_import_runs (
    import_run_id SERIAL PRIMARY KEY,
    source TEXT NOT NULL,
    source_url TEXT,
    source_license TEXT,
    source_last_modified TEXT,
    entries_read INTEGER NOT NULL DEFAULT 0,
    inserted INTEGER NOT NULL DEFAULT 0,
    enriched INTEGER NOT NULL DEFAULT 0,
    skipped_duplicates INTEGER NOT NULL DEFAULT 0,
    finished_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

COMMIT;
