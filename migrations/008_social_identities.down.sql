-- Rollback for 008_social_identities.sql.
--
-- DESTRUCTIVE: drops every linked provider account. Any user who signs in only
-- through Google or Apple, and has never set a password, becomes unreachable —
-- the NOT NULL restore below will fail for exactly those rows, which is the
-- intended safety net rather than an error to work around.
--
-- Before running this, give passwordless accounts a way back in (send them a
-- password-reset link) or accept that they will need to re-register:
--
--   SELECT user_id, email FROM users WHERE password_hash IS NULL;

BEGIN;

DROP TABLE IF EXISTS oauth_flows;
DROP TABLE IF EXISTS user_identities;

-- Deliberately not forced. If this raises, passwordless accounts still exist
-- and the rollback should stop so they are dealt with consciously.
ALTER TABLE users ALTER COLUMN password_hash SET NOT NULL;

COMMENT ON COLUMN users.password_hash IS NULL;

COMMIT;
