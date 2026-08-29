-- Authentication and authorization schema.
--
-- Four tables:
--   users              accounts, with a normalized email and an Argon2id hash
--   user_sessions      server-side, revocable sessions (one row per sign-in)
--   auth_tokens        single-use email verification and password reset tokens
--   auth_events        security audit log
--
-- Nothing here stores a plaintext secret. Passwords are Argon2id hashes;
-- session and email tokens are stored as SHA-256 digests of a 256-bit random
-- value, so a database disclosure cannot be replayed against the application.
-- SHA-256 rather than a KDF is correct here precisely because these are
-- high-entropy random tokens, not user-chosen passwords.
--
-- Email addresses are lowercased and trimmed by the API before they are stored,
-- and `email_normalized` recomputes that in the database so uniqueness is
-- enforced on the normalized form no matter how a row is inserted. The two
-- columns therefore agree today; the generated column exists so a direct SQL
-- insert cannot slip a duplicate past the unique index by varying case.
--
-- Reversible: see 007_auth.down.sql. Idempotent: safe to re-run.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    user_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email              TEXT NOT NULL,
    email_normalized   TEXT GENERATED ALWAYS AS (lower(btrim(email))) STORED,
    password_hash      TEXT NOT NULL,
    display_name       TEXT,
    role               TEXT NOT NULL DEFAULT 'user'
                       CHECK (role IN ('user', 'admin')),
    status             TEXT NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active', 'deactivated', 'deleted')),
    email_verified_at  TIMESTAMPTZ,

    -- Bumped on password change, reset, and "sign out everywhere". Any session
    -- or token issued before this instant is refused, which revokes them
    -- without needing to enumerate and delete rows first.
    credentials_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Throttles password attempts per account, independent of source address.
    failed_login_count INTEGER NOT NULL DEFAULT 0,
    locked_until       TIMESTAMPTZ,

    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at         TIMESTAMPTZ,

    CONSTRAINT users_email_not_blank CHECK (btrim(email) <> ''),
    -- A deleted account keeps its row so audit history and foreign keys stay
    -- intact, but must carry a timestamp saying so.
    CONSTRAINT users_deleted_consistent
        CHECK ((status = 'deleted') = (deleted_at IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS users_email_normalized_key
    ON users (email_normalized);

CREATE INDEX IF NOT EXISTS users_role_idx ON users (role) WHERE role <> 'user';
CREATE INDEX IF NOT EXISTS users_status_idx ON users (status) WHERE status <> 'active';

-- ---------------------------------------------------------------------------
-- user_sessions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_sessions (
    session_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,

    -- SHA-256 of the opaque token held in the cookie. The token itself is
    -- never stored, so this column cannot be replayed.
    token_hash       BYTEA NOT NULL,

    -- Coarse client description for the "your sessions" screen. Truncated and
    -- never used for authorization.
    user_agent       TEXT,
    ip_address       INET,

    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Absolute expiry. Idle expiry is derived from last_seen_at in the query.
    expires_at       TIMESTAMPTZ NOT NULL,
    revoked_at       TIMESTAMPTZ,
    revoked_reason   TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS user_sessions_token_hash_key
    ON user_sessions (token_hash);

-- Serves both session lookup by user and the "sign out all devices" sweep.
CREATE INDEX IF NOT EXISTS user_sessions_active_idx
    ON user_sessions (user_id, expires_at)
    WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS user_sessions_expires_idx ON user_sessions (expires_at);

-- ---------------------------------------------------------------------------
-- auth_tokens
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_tokens (
    auth_token_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    purpose       TEXT NOT NULL CHECK (purpose IN ('email_verification', 'password_reset')),

    token_hash    BYTEA NOT NULL,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ NOT NULL,
    -- Set the moment a token is redeemed, which is what makes it single-use.
    consumed_at   TIMESTAMPTZ,

    CONSTRAINT auth_tokens_expires_after_creation CHECK (expires_at > created_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS auth_tokens_token_hash_key
    ON auth_tokens (token_hash);

-- Issuing a new token invalidates outstanding ones for the same purpose; this
-- index serves that sweep and the redemption lookup.
CREATE INDEX IF NOT EXISTS auth_tokens_pending_idx
    ON auth_tokens (user_id, purpose)
    WHERE consumed_at IS NULL;

CREATE INDEX IF NOT EXISTS auth_tokens_expires_idx ON auth_tokens (expires_at);

-- ---------------------------------------------------------------------------
-- auth_events
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_events (
    auth_event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Nullable and ON DELETE SET NULL: a failed sign-in for an address that was
    -- never registered has no user, and purging a user must not erase the
    -- security history of the account.
    user_id       BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
    event_type    TEXT NOT NULL,
    -- Free-form, but the application never writes a token, hash or password here.
    detail        JSONB NOT NULL DEFAULT '{}'::jsonb,
    ip_address    INET,
    user_agent    TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS auth_events_user_idx ON auth_events (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS auth_events_type_idx ON auth_events (event_type, created_at DESC);

-- ---------------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION users_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS users_touch_updated_at_trg ON users;
CREATE TRIGGER users_touch_updated_at_trg
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION users_touch_updated_at();

-- No seed administrator is created here. Promoting the first real account is a
-- deliberate operator action; see scripts/grant_admin.py.

COMMIT;
