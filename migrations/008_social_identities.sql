-- Social sign-in (Google, Apple).
--
-- Two tables and one column change:
--
--   user_identities   one row per (provider, provider account) linked to a user
--   oauth_flows       short-lived server-side state for an in-progress sign-in
--   users.password_hash becomes nullable
--
-- The nullable password is the substantive change. An account created through
-- Google has no password and never will unless the user sets one, so a NOT NULL
-- column would force a placeholder -- and a placeholder in a password column is
-- exactly the kind of value that eventually gets compared against. NULL states
-- plainly that password sign-in is unavailable for this account.
--
-- `oauth_flows` exists so the OAuth state, PKCE verifier and nonce live on the
-- server rather than in a signed cookie. Signing a cookie would mean choosing
-- and implementing a construction; a random opaque key in an HttpOnly cookie
-- pointing at a row needs no cryptography of our own, and gets single-use and
-- expiry for free -- the same shape as auth_tokens.
--
-- Reversible: see 008_social_identities.down.sql. Idempotent.

BEGIN;

-- ---------------------------------------------------------------------------
-- users.password_hash becomes optional
-- ---------------------------------------------------------------------------
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

-- An account must remain reachable by *some* means. This cannot be expressed as
-- a row constraint because the alternative lives in another table, so it is
-- enforced in the service layer (unlinking the last identity is refused when no
-- password is set). Recorded here so the intent is visible next to the schema.
COMMENT ON COLUMN users.password_hash IS
    'Argon2id hash, or NULL when the account signs in only through a linked '
    'provider. Never a placeholder value.';

-- ---------------------------------------------------------------------------
-- user_identities
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_identities (
    identity_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    provider       TEXT NOT NULL CHECK (provider IN ('google', 'apple')),

    -- The provider's stable identifier for the account ("sub"). This, not the
    -- email address, is the identity: an email can be reassigned by its domain
    -- owner, and matching on it alone would let a new owner inherit an account.
    subject        TEXT NOT NULL,

    -- What the provider asserted at link time. Informational only; the
    -- authoritative address stays on `users`.
    email          TEXT,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,

    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at  TIMESTAMPTZ,

    CONSTRAINT user_identities_subject_not_blank CHECK (btrim(subject) <> '')
);

-- One provider account maps to exactly one user. Without this, two local
-- accounts could both claim the same Google account.
CREATE UNIQUE INDEX IF NOT EXISTS user_identities_provider_subject_key
    ON user_identities (provider, subject);

-- A user links a given provider at most once.
CREATE UNIQUE INDEX IF NOT EXISTS user_identities_user_provider_key
    ON user_identities (user_id, provider);

CREATE INDEX IF NOT EXISTS user_identities_user_idx ON user_identities (user_id);

-- ---------------------------------------------------------------------------
-- oauth_flows
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS oauth_flows (
    oauth_flow_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    -- SHA-256 of the opaque key held in a short-lived HttpOnly cookie. As with
    -- sessions, the key itself is never stored.
    flow_key_hash BYTEA NOT NULL,

    provider      TEXT NOT NULL CHECK (provider IN ('google', 'apple')),

    -- Compared against the `state` the provider echoes back, which is what ties
    -- the response to the browser that started the flow.
    state         TEXT NOT NULL,
    -- PKCE. Short-lived and single-use; the provider never sees it until the
    -- token exchange.
    code_verifier TEXT NOT NULL,
    -- Bound into the ID token so a captured token cannot be replayed.
    nonce         TEXT NOT NULL,

    -- Already reduced to a site-relative path before it is stored.
    redirect_to   TEXT NOT NULL DEFAULT '/',
    -- Set when an already-signed-in user is linking a provider rather than
    -- signing in, so the callback links instead of creating an account.
    link_user_id  BIGINT REFERENCES users(user_id) ON DELETE CASCADE,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ NOT NULL,
    consumed_at   TIMESTAMPTZ,

    CONSTRAINT oauth_flows_expires_after_creation CHECK (expires_at > created_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS oauth_flows_key_hash_key
    ON oauth_flows (flow_key_hash);

CREATE INDEX IF NOT EXISTS oauth_flows_expires_idx ON oauth_flows (expires_at);

COMMIT;
