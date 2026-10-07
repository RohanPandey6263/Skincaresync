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

## Railway

Railway runs the same two pieces as compose — nginx serving the site, the API
behind it — as two services in one project, plus a PostgreSQL service. **Only
the website is public.** Every Railway service gets its own `*.up.railway.app`
address, and browsers treat two of those as different sites, so a public API on
its own domain breaks sign-in (see "One origin, on purpose" above). The website
service proxies `/api/` to the API over Railway's private network instead.

### Services

| Service | Builds from | Config file (Settings → Config-as-code) | Public domain |
|---|---|---|---|
| API (the existing repo service) | `Dockerfile` | `railway.json` (picked up automatically) | **none** |
| Website (add: *Create → GitHub repo*, same repo) | `deploy/web.Dockerfile` | `/deploy/railway.web.json` — **set this by hand** | yes |
| Postgres (add: *Create → Database*) | — | — | TCP proxy only while loading data |

Leave **Root Directory empty** on both app services. The website service must be
pointed at `/deploy/railway.web.json`; left alone it reads the root
`railway.json` and builds a second copy of the API.

### API service variables

| Variable | Value |
|---|---|
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` |
| `PORT` | `8000` — fixed, so the website knows where to find it |
| `BIND_HOST` | `dual` — listen on IPv4 and IPv6; the private network may use either |
| `SKINCARESYNC_ENV` | `production` |
| `APP_BASE_URL`, `API_BASE_URL` | `https://<website domain>` — the *website's*, no trailing slash |
| `CORS_ORIGINS` | the same |
| `TRUST_PROXY` | `true` |
| `TRUST_PROXY_HOPS` | `2` |
| `EMAIL_PROVIDER`, `EMAIL_FROM`, `SMTP_*` | as in `deploy/env.production.example` |

### Website service variables

| Variable | Value |
|---|---|
| `API_UPSTREAM` | `<api service name>.railway.internal:8000` — see the API's *Settings → Networking* for the exact private hostname |
| `BEHIND_EDGE_PROXY` | `true` |

**Do not set `PORT` on the website.** Railway injects it and nginx listens on it.

### Why those values

**`TRUST_PROXY_HOPS=2` with `BEHIND_EDGE_PROXY=true`.** A request passes
Railway's edge, then nginx, then the API. nginx keeps the edge's
`X-Forwarded-For` and appends the edge's own address, so the visitor is the
second entry from the right — and whatever the visitor typed into the header
sits further left, where it is never read. Verified end to end: a visitor
forging a new first entry on every request was still cut off after 20 analyses,
while 25 distinct visitors were all served. With `BEHIND_EDGE_PROXY` unset,
nginx would overwrite the header with the edge's address and every visitor
would share one rate-limit budget.

**`BIND_HOST=dual`.** asyncio treats a plain `::` socket as IPv6-only, so a
proxy that resolves the API to an IPv4 address gets refused. `dual` opens one
socket per family. It is not the default because binding IPv6 fails outright on
a host with IPv6 switched off, which some Docker setups have.

**API redeploys.** nginx resolves `API_UPSTREAM` per request (10-second cache),
so a redeployed API with a new private address is picked up without restarting
the website.

`config.py` validates the API's settings at import, so a missing or malformed
value fails its deploy with a named error rather than a running service that
misbehaves.

### Data

The API answers its health check only once the database has tables. To copy a
local database, enable the Postgres service's TCP proxy and use the
`DATABASE_PUBLIC_URL` it adds (`DATABASE_URL` is private-network only):

```bash
pg_dump -d <local db> -Fc --no-owner --no-acl \
  --exclude-table-data=users --exclude-table-data=user_sessions \
  --exclude-table-data=user_identities --exclude-table-data=auth_tokens \
  --exclude-table-data=oauth_flows --exclude-table-data=auth_events \
  --exclude-table-data=interaction_gaps --exclude-table-data=parser_unknowns \
  --exclude-table-data=llm_logs -f catalog.dump
pg_restore --no-owner --no-acl -d '<DATABASE_PUBLIC_URL>' catalog.dump
```

The excluded tables keep their structure but not their rows: local accounts,
live session tokens and test-traffic logs have no place in production. Starting
from nothing instead, run `migrations/install.sql` against the same URL and
then the importers in `scripts/`.

Use `pg_dump` and `pg_restore` from the same major version as the local server;
an older client refuses a newer server.

## Deploying somewhere other than compose

The pieces are independent and the constraints travel with them.

- **API** — the root `Dockerfile` is a plain image; any container platform runs
  it and it listens on `$PORT` when the platform sets one. Give it the
  environment from `deploy/env.production.example` (or a single `DATABASE_URL`
  in place of the `PG*` variables), keep `WEB_CONCURRENCY=1`, and set
  `TRUST_PROXY_HOPS` to the number of proxies in front if they append to
  `X-Forwarded-For` rather than rewrite it.
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
