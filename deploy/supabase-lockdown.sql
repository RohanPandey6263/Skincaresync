-- Close Supabase's Data API over this app's tables.
--
-- Supabase serves every table in `public` over an HTTP API (PostgREST) to two
-- roles, `anon` and `authenticated`, and grants them full access to new tables
-- by default. The anon key that authorises `anon` is public by design -- it is
-- meant to ship inside client apps. Tables created by plain SQL, which is how
-- this schema and its data arrive, get no row-level security. Left alone, anyone
-- holding that key could read `users` (password hashes included), the session
-- and token tables, and rewrite the ingredient catalog.
--
-- SkincareSync never uses that API: the API service connects to Postgres
-- directly, as the tables' owner, which row-level security does not apply to.
-- So everything is closed to both roles, in two independent layers:
--
--   1. Row-level security on, with no policies: the API roles see no rows.
--   2. Their privileges revoked outright, now and for anything created later.
--
-- Idempotent, and a no-op on Postgres without those roles, so it is safe to run
-- anywhere and to re-run after every migration:
--
--     psql '<connection URL>' -f deploy/supabase-lockdown.sql

\set ON_ERROR_STOP on

DO $$
DECLARE
    t record;
    api_roles text;
BEGIN
    FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t.tablename);
    END LOOP;

    SELECT string_agg(quote_ident(rolname), ', ')
      INTO api_roles
      FROM pg_roles
     WHERE rolname IN ('anon', 'authenticated');

    IF api_roles IS NULL THEN
        RAISE NOTICE 'No Supabase API roles here; row-level security enabled, nothing to revoke.';
        RETURN;
    END IF;

    EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %s', api_roles);
    EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM %s', api_roles);
    EXECUTE format('REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM %s', api_roles);
    -- Default privileges belong to the role creating objects: this one, the
    -- same role the migrations run as.
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM %s', api_roles);
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM %s', api_roles);
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM %s', api_roles);

    RAISE NOTICE 'Locked down: % table(s) under row-level security; access revoked from %.',
        (SELECT count(*) FROM pg_tables WHERE schemaname = 'public'), api_roles;
END
$$;
