-- Drop schema that no code has ever referenced.
--
-- `skin_profiles`, `routines` and `routine_products` were created in the base
-- schema for saved, persisted routines. That feature was never built: the API
-- takes a routine in the request body and returns an analysis, holding nothing
-- between requests. All three tables are empty and no module imports them.
--
-- `products.parsed_ingredient_ids` was meant to cache the resolved ingredient
-- ids for a stored product. Nothing ever wrote it; it is `'{}'` on every row.
-- Resolution happens in memory against the shared resolver instead.
--
-- Verified empty before writing this migration:
--   skin_profiles 0, routines 0, routine_products 0 rows,
--   parsed_ingredient_ids populated on 0 of 3,286 products.
--
-- Deliberately kept:
--   products.verified   - editorial trust flag. Unused today, but ATTRIBUTION.md
--                         treats provenance as a first-class concern, so the hook
--                         is worth more than the byte it costs.
--   *.created_at        - row provenance. Not read by application code, which is
--                         normal for audit columns.
--
-- This migration is destructive and not idempotent-safe to reverse. The exact
-- CREATE TABLE statements are recoverable from git history:
--   git show c2279f9:aidatabase.sql
--
-- Restoring the saved-routines feature means re-adding these tables, which is a
-- schema design decision to make then rather than a rollback of this migration.

BEGIN;

-- Foreign keys run routine_products -> routines -> skin_profiles, so drop in
-- that order. routine_products also referenced products.
DROP TABLE IF EXISTS routine_products;
DROP TABLE IF EXISTS routines;
DROP TABLE IF EXISTS skin_profiles;

ALTER TABLE products DROP COLUMN IF EXISTS parsed_ingredient_ids;

COMMIT;
