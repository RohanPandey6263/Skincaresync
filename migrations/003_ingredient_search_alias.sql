-- Follow-up to 002: alias_text was added to the migration file after an earlier
-- run, so some databases have the catalog without the flattened alias column
-- the trigram index needs. Idempotent.

BEGIN;

ALTER TABLE ingredients ADD COLUMN IF NOT EXISTS alias_text TEXT;

-- Recreate the trigger in case this database was migrated from an older 002.
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

UPDATE ingredients SET inci_name = inci_name
WHERE alias_text IS NULL;

CREATE INDEX IF NOT EXISTS ingredients_alias_text_trgm_idx
    ON ingredients USING GIN (alias_text gin_trgm_ops);

CREATE INDEX IF NOT EXISTS ingredients_restriction_idx
    ON ingredients (ingridient_id)
    WHERE restriction IS NOT NULL AND restriction <> '';

COMMIT;
