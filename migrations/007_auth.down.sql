-- Rollback for 007_auth.sql.
--
-- DESTRUCTIVE: this drops every account, session and audit record. It exists so
-- the migration is genuinely reversible in development and staging. Take a dump
-- before running it anywhere with real accounts:
--
--   pg_dump -t users -t user_sessions -t auth_tokens -t auth_events \
--     -d "$PGDATABASE" > auth_backup.sql
--
-- Child tables first: auth_tokens, user_sessions and auth_events all reference
-- users.

BEGIN;

DROP TRIGGER IF EXISTS users_touch_updated_at_trg ON users;
DROP FUNCTION IF EXISTS users_touch_updated_at();

DROP TABLE IF EXISTS auth_events;
DROP TABLE IF EXISTS auth_tokens;
DROP TABLE IF EXISTS user_sessions;
DROP TABLE IF EXISTS users;

-- pgcrypto is left installed: other schema may rely on it, and dropping an
-- extension is not something a table migration should decide.

COMMIT;
