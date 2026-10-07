# Deploying SkincareSync

Three things ship: a FastAPI service, a static React bundle, and a PostgreSQL
database. `docker-compose.yml` runs all three behind one nginx, which is the
configuration the rest of this document assumes.

Everything here has been exercised against a clean database and a clean set of
containers. If a step fails, it fails loudly — `skincaresync/config.py`
validates the environment at import, so a misconfigured API exits at boot with
a named problem instead of starting and misbehaving quietly.

## One origin, on purpose

The SPA and the API are served from the same host, with nginx proxying `/api/`
to the API container.

This is not just tidiness. The session cookie is `SameSite=Lax`, and browsers
do not send a Lax cookie on cross-site XHR. Split the frontend and the API
across two registrable domains and sign-in appears to succeed, sets a cookie
the browser then refuses to send, and every authenticated request comes back
401. Same origin makes the cookie first-party and takes CORS out of the picture
entirely.

If you must split them, set `SESSION_COOKIE_SAMESITE=none` (which requires
`SESSION_COOKIE_SECURE=true`, already the production default), set
`VITE_API_URL` to the API origin at **build** time, and list the frontend
origin in `CORS_ORIGINS`. Sharing a parent domain — `app.example.com` and
`api.example.com` with `SESSION_COOKIE_DOMAIN=.example.com` — also works and
keeps `lax`.

## Deploy

```bash
cp deploy/env.production.example .env.deploy
$EDITOR .env.deploy                      # every value marked required
docker compose --env-file .env.deploy up -d --build
```

On first boot the database container runs `migrations/install.sql` from
`/docker-entrypoint-initdb.d`, which creates the schema and seeds 141 curated
ingredients and 156 interaction rules. Confirm it:

```bash
curl -s http://localhost:8080/api/health
# {"ok":true,"database":"ok","ingredient_count":141,...,"interaction_count":156}
```

Then load the catalogs, which are fetched from the network and cannot come from
SQL. Expect several minutes, most of it in the brand catalogs:

```bash
docker compose --env-file .env.deploy run --rm seed
```

`ingredient_count` goes to roughly 22,000. Every importer is idempotent, so a
failed run is re-runnable.

Finally, make yourself an administrator. There is no seed admin and no default
credentials by design:

```bash
# register through the UI first, then:
docker compose --env-file .env.deploy exec api python scripts/grant_admin.py you@example.com
```

## TLS is not optional, and not included

`docker compose` publishes plain http on `WEB_PORT` (8080 by default). Put a
proxy holding your certificate in front of it — Caddy, Traefik, a cloud load
balancer, nginx on the host.

The session cookie is issued `Secure`. A browser will not store a `Secure`
cookie delivered over plain http, so **without TLS in front, nobody can sign
in** — the cookie is set, silently dropped, and the user bounces back to the
sign-in page. `APP_BASE_URL` and `API_BASE_URL` must both be `https` or the API
refuses to start, which is the same rule enforced one layer earlier.

## Do not expose the API container directly

`api` is `expose`d to the compose network, never `ports`-published, and that
matters for more than tidiness.

`TRUST_PROXY=true` is set on the API, because behind a proxy the socket address
is always the proxy's. With it on, the app takes the client identity from the
**first** entry of `X-Forwarded-For` (`skincaresync/ratelimit.py`,
`skincaresync/auth/dependencies.py`). `deploy/nginx.conf` therefore sets that
header with `$remote_addr`, which **overwrites** whatever the client sent:

```nginx
proxy_set_header X-Forwarded-For $remote_addr;     # not $proxy_add_x_forwarded_for
```

The usual `$proxy_add_x_forwarded_for` idiom *appends* the peer to the client's
own header, leaving an attacker-supplied value in first place — enough to
rotate past every rate limit at will and to write forged addresses into the
auth audit log. Verified both ways: 26 requests through nginx carrying 26
different forged `X-Forwarded-For` values hit `429` after 20, while the same 26
sent straight to the API container all returned `200`.

So: if you ever deploy the API without this nginx in front of it, set
`TRUST_PROXY=` empty. It is only safe under a proxy that rewrites the header.

## Operational notes

**Workers.** Rate-limit counters live in process memory, so each worker carries
its own budget and `WEB_CONCURRENCY=2` doubles every configured limit. Leave it
at 1 until those counters move to Redis; the interface in
`skincaresync/ratelimit.py` would not change.

**Managed Postgres.** Neither connection path passes `sslmode` explicitly, so
libpq's own `PGSSLMODE=require` is the lever. Set it in the env file. The
compose default is `prefer`, which is libpq's default — note that an empty
value is *not* the same as unset and libpq rejects `sslmode=""` outright.

**Backups.** The volume holds the curated catalog plus ~22,000 imported
ingredients and every cached product list. The curated layer is in migration
000 and the imports are re-runnable, but user accounts are not. Back up
`pgdata` on a schedule.

**Schema changes.** Add the migration to `migrations/`, then regenerate the
bundle — nothing notices if you forget:

```bash
./scripts/build_install_sql.sh
docker compose --env-file .env.deploy run --rm migrate
```

**Rotating credentials.** `.env.deploy` is gitignored and `.dockerignore` keeps
`.env` out of image layers. Nothing bakes a secret into an image; a rotation is
an env-file edit plus `docker compose up -d`.

## Deploying somewhere other than compose

The pieces are independent and the constraints travel with them.

- **API** — the root `Dockerfile` is a plain image; any container platform runs
  it. Give it the environment from `deploy/env.production.example`, put it
  behind a proxy that rewrites `X-Forwarded-For`, and keep `WEB_CONCURRENCY=1`.
- **Frontend** — `cd frontend && VITE_API_URL=... npm run build` produces
  `dist/`, servable by any static host. **It needs a history fallback**: the
  router in `frontend/src/lib/router.jsx` owns `/signin`, `/verify-email`,
  `/reset-password` and the rest, and no file exists at any of those paths.
  Users arrive at them directly from email links. Netlify: `/* /index.html
  200` in `_redirects`. Vercel: a rewrite of `/(.*)` to `/index.html`.
  Cloudflare Pages: on by default. Without it, every verification link 404s.
- **Database** — any PostgreSQL 15+. Run `migrations/install.sql`, then the
  importers. `pg_trgm` and `unaccent` are created by migration 002, so the role
  running it needs rights to create extensions.

## iOS

`ios/Config/Release.xcconfig` ships `API_BASE_URL` empty and the app refuses to
start on an empty or non-HTTPS value rather than guessing a host. Point it at
the deployed origin before building for release:

```
API_BASE_URL = https:/$()/skincaresync.example.com
```

The `$()` splits the double slash so xcconfig does not read the rest of the
line as a comment. It can also be passed on the `xcodebuild` command line,
which is the better answer for CI.
