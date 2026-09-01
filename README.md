# SkincareSync MVP

SkincareSync is a routine-level skincare compatibility MVP. The backend uses FastAPI and PostgreSQL, reusing the existing `ingredients` table. The frontend is a Vite React app.

SkincareSync helps users check whether the products in their skincare routine work well together. It scans or finds ingredient lists, compares active ingredients, flags conflicts or cautions, and explains safer AM/PM routine choices using a sourced compatibility database.

## Run The Database Migration

Run these in order against your database. Each one is idempotent.

```bash
psql -d "$PGDATABASE" -f aidatabase.sql
psql -d "$PGDATABASE" -f migrations/002_ingredient_catalog.sql
psql -d "$PGDATABASE" -f migrations/003_ingredient_search_alias.sql
psql -d "$PGDATABASE" -f migrations/004_product_catalog.sql
psql -d "$PGDATABASE" -f migrations/005_product_variants_and_search_indexes.sql
psql -d "$PGDATABASE" -f migrations/006_drop_unused_schema.sql
psql -d "$PGDATABASE" -f migrations/007_auth.sql
psql -d "$PGDATABASE" -f migrations/008_social_identities.sql
psql -d "$PGDATABASE" -f migrations/009_catalog_interactions.sql
psql -d "$PGDATABASE" -f migrations/010_tretinoin_interactions.sql
```

Migration 007 adds authentication. It is additive and touches no existing table,
so accounts can be introduced to a populated database without migrating data.
To roll it back, `migrations/007_auth.down.sql` drops the four tables it creates
— destructive, so take a dump first.

Migration 005 is required: product lookup queries the accent-folded
`products.search_text` column that it adds. Migration 006 is destructive — it
drops three empty tables and one unpopulated column that no code has ever
referenced (see the header comment in that file).

## Import OTC Product Labels

Open Beauty Facts often lists a product with no ingredient text. For medicated
OTC products (PanOxyl, Differin, and similar) we store FDA DailyMed labels in
the local `products` table. Lookups check that table first, then DailyMed, then
Open Beauty Facts, and cache any successful remote list.

```bash
source venv/bin/activate
python scripts/import_product_catalog.py
```

## Import Brand-Published Cosmetic Lists

Open Beauty Facts often has the product with no INCI text. For widely used
cosmetics that are not FDA drugs (vitamin C serums, and later other families)
we store the brand-published ingredient list in `products`. These lists are
transcribed from official pages; packaging is still the source of truth.

```bash
source venv/bin/activate
python scripts/import_published_products.py --family vitamin-c
python scripts/import_brand_catalogs.py
```

`import_brand_catalogs.py` stores every other published list it can find for
those same brands: official Shopify/Demandware product pages, Beauty of Joseon
CPNP pages, Open Beauty Facts records that already include INCI, and FDA
DailyMed labels for OTC lines (CeraVe, Neutrogena, La Roche-Posay, Garnier,
Vichy, SkinCeuticals). Products whose public page has no parseable INCI are
skipped. Packaging remains the source of truth.

## Import The Ingredient Catalog

The finder uses the Open Beauty Facts CosIng-derived taxonomy (~22,000 INCI names,
multilingual synonyms, functions, CAS numbers). See `ATTRIBUTION.md` for licence terms.

```bash
source venv/bin/activate
python scripts/import_ingredient_catalog.py
```

## Configuration

Every setting has a working default for local development, so you can skip this
on a fresh checkout. `.env.example` documents all of them: database connection
and pool sizing, CORS origins, rate limits, the upstream lookup budget, and the
log level.

```bash
cp .env.example .env
```

Two are worth knowing before deploying:

- `SKINCARESYNC_ENV=production` disables `/docs`, `/redoc` and `/openapi.json`.
- `CORS_ORIGINS` must list the origins the frontend is actually served from; the
  default only covers the local Vite dev server.

## Run Both

From the repo root, one command starts the API and the frontend. Ctrl-C stops both.

```bash
./scripts/dev.sh
```

Then open http://localhost:5173. PostgreSQL must already be running.

## Run The Backend

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
uvicorn skincaresync.api:app --reload
```

The API runs at `http://localhost:8000`.

Requests are rate limited per client address: 20 analyses, 30 product lookups
and 300 catalog queries per minute by default. Counts live in process memory, so
with more than one worker the effective limit is multiplied by the worker count.

## Authentication

Accounts are optional for the analyser and required for saved work, the account
pages, and anything administrative.

**Approach.** FastAPI has no official batteries-included auth. The established
library, FastAPI Users, is built on SQLAlchemy/Tortoise/Beanie *and* brings its
own user model and routers, which would have to be dismantled to meet the audit
events, session revocation and enumeration-resistance this needed. So it uses
FastAPI's own `fastapi.security` primitives directly:

| Concern | Choice | Why |
|---|---|---|
| Password hashing | Argon2id via `argon2-cffi` | Reference binding; tracks its own cost defaults. `passlib` is unmaintained since 2020. |
| Sessions | Opaque 256-bit tokens, SHA-256 at rest, HttpOnly cookie | Revocable. A JWT cannot implement "sign out all devices". |
| Token storage | SHA-256, never plaintext | These are CSPRNG values, not passwords, so a KDF buys nothing; what matters is that a database dump cannot be replayed. |
| CSRF | Double-submit cookie + `SameSite=Lax` | The session cookie is unreadable by script; the CSRF cookie is readable and must be echoed in `X-CSRF-Token`. |
| Social sign-in | OIDC (Google, Apple) with PKCE, state and nonce | ID tokens verified against provider JWKS with PyJWT. Nothing is trusted from a decoded-but-unverified token. |
| Data access | SQLAlchemy 2.0 ORM, auth tables only | Auth is small relational CRUD. The ingredient search stays raw psycopg2 — its trigram and full-text ranking would only be obscured by an ORM. |

The schema is owned by `migrations/007_auth.sql`. `create_all()` is never called,
and `tests/test_auth_schema.py` fails if the models and the migrated database
drift apart.

### Social sign-in

Google and Apple are supported. Each appears only when its credentials are
configured, so an unconfigured provider cannot be rendered or started.

**Google.** In the Google Cloud console create an OAuth client ID of type *Web
application*, then register this redirect URI on it:

```
$API_BASE_URL/api/auth/oauth/google/callback
```

Set `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.

**Apple.** Needs a paid Developer account. Create a Services ID (not an App ID),
enable Sign in with Apple on it, register the same callback path, then download a
`.p8` key. Set `APPLE_CLIENT_ID` (the Services ID), `APPLE_TEAM_ID`,
`APPLE_KEY_ID` and `APPLE_PRIVATE_KEY_PATH`.

Two Apple-specific constraints are worth knowing before you start:

- Apple returns the user's **name only once**, in the body of the first
  callback. It is captured then or not at all.
- Apple's callback is a **cross-site form POST**, and browsers do not send a
  `SameSite=Lax` cookie on one. The flow cookie is therefore set
  `SameSite=None`, which requires `Secure`, which means **Apple cannot be
  exercised over plain http**. Use an https tunnel locally.

**Account linking.** A provider account is identified by its `sub`, never by
email — an email can be reassigned by whoever controls the domain. An existing
password account is linked automatically only when the provider asserts
`email_verified`. When it does not, the sign-in is refused rather than linking or
creating a duplicate, because linking on an unverified address would hand the
account to whoever can set it at the provider.

An account created through a provider has **no password** (`password_hash` is
NULL, never a placeholder). Such a user can set one from account settings, and
disconnecting the last sign-in method is refused.

### Making the first administrator

No seed administrator and no default credentials are created — a hardcoded
account is a backdoor that survives into production. Register normally, then:

```bash
python scripts/grant_admin.py you@example.com
python scripts/grant_admin.py --list
```

Changing a role signs that account out everywhere, so no session keeps running
under the old permissions.

### Email

`EMAIL_PROVIDER=console` (the default) logs each message and, with
`EMAIL_OUTBOX_DIR` set, writes it as an `.eml` file. It sends nothing, so local
work needs no mail account. `AUTH_DEV_ECHO_TOKENS=1` additionally returns
verification and reset tokens in API responses; both are refused in production.

`EMAIL_PROVIDER=smtp` delivers through any SMTP relay — a local capture tool
such as Mailpit, a self-hosted relay, or a commercial provider's SMTP endpoint.
No paid service is assumed. To add a vendor's HTTP API later, implement
`EmailSender` in `skincaresync/emailing/sender.py` and register it in
`build_sender`; nothing else changes.

### Production requirements

`skincaresync/config.py` validates these at import, so a misconfigured
deployment fails at startup rather than leaking quietly:

- `SKINCARESYNC_ENV=production`
- `APP_BASE_URL` must be **https** and is the only source of email links
- `SESSION_COOKIE_SECURE=true` (the default in production)
- `EMAIL_PROVIDER=smtp` with `SMTP_HOST` set — `console` is refused
- `AUTH_DEV_ECHO_TOKENS` is forced off regardless of what is set
- `CORS_ORIGINS` must list the real frontend origin
- `API_BASE_URL` must be **https** and must match the redirect URI registered
  with every OAuth provider, byte for byte
- Set `TRUST_PROXY=true` **only** behind a proxy that rewrites
  `X-Forwarded-For`; otherwise any client can forge its rate-limit identity
- Terminate TLS in front of the app; cookies are `Secure` and will not be
  stored over plain http

## Run The Tests

```bash
source venv/bin/activate
pytest
```

The suite reads from the development database but never writes to it: a fixture
in `tests/conftest.py` stubs every write path. A test that genuinely needs to
write marks itself `@pytest.mark.allow_db_writes`.

Authentication tests need to write, so they run against a dedicated database,
`skincaresync_test`, which the fixtures create and migrate automatically (they
skip if `createdb` is unavailable). It is truncated at the start of each run and
each test executes inside a transaction that is rolled back.

```bash
pytest tests/test_auth_accounts.py     # registration, verification, sign-in
pytest tests/test_auth_password.py     # reset and change
pytest tests/test_auth_sessions.py     # sessions, revocation, sign-out
pytest tests/test_auth_security.py     # roles, CSRF, redirects, rate limits, config
pytest tests/test_auth_schema.py       # models match the migrated schema
pytest tests/test_auth_social.py       # Google/Apple: token verification, linking
```

The social tests reach no network. A throwaway RSA keypair stands in for a
provider's signing key, so ID tokens are genuinely signed and go through the same
verification path production uses — signature, issuer, audience, expiry and
nonce all really checked. Only the token endpoint and JWKS fetch are substituted.

Lint and type checks:

```bash
ruff check skincaresync/ scripts/ tests/
mypy skincaresync/auth skincaresync/config.py skincaresync/emailing --ignore-missing-imports
```

## Run The Frontend

```bash
cd frontend
npm install
npm run dev
```

The frontend runs at `http://localhost:5173`.

## Frontend Structure

The React app is componentized around a token-driven design system. Styles are global CSS
consumed through custom properties — there is a single styling system, no per-component
competing approach.

```
frontend/src
├── main.jsx                 App bootstrap + ToastProvider
├── App.jsx                  Layout and state orchestration only
├── styles/
│   ├── tokens.css           Colour, type, space, radius, elevation, motion tokens
│   ├── base.css             Reset, typography rhythm, focus treatment
│   ├── ui.css               Primitives (buttons, fields, panels, dialogs, toasts)
│   └── app.css              Page composition and breakpoints
├── components/
│   ├── ui/                  Reusable primitives (Button, Field, Panel, Badge, Modal, …)
│   └── *.jsx                Feature components (Hero, RoutineBuilder, ResultsPanel, …)
├── hooks/useBarcodeScanner.js
└── lib/                     API client, constants, formatters, product helpers
```

Authentication adds:

```
frontend/src
├── Routes.jsx                    Flat route table
├── context/AuthContext.jsx       Session state (display only; the server decides)
├── lib/router.jsx                ~90-line history router
├── lib/authApi.js                Auth client; sends cookies + X-CSRF-Token
├── styles/auth.css               Auth screens, built from the same tokens
└── components/auth/
    ├── AuthShell.jsx             Layout, password field, form state
    ├── SignInPage.jsx  RegisterPage.jsx  VerifyEmailPage.jsx
    ├── PasswordResetPages.jsx    Forgot and reset
    ├── AccountSecurityPage.jsx   Password, devices, activity, deletion
    └── RequireAuth.jsx           Redirect guard (not a security boundary)
```

`lib/router.jsx` is deliberately hand-written: the app has exactly two runtime
dependencies, and six flat routes with no nesting or data loading did not
justify a third. Its surface is a subset of react-router's, so swapping it is
mechanical if routing grows.

All design values come from `styles/tokens.css`. Use those variables rather than literal
colours or pixel values so the system stays consistent.

## What Works In This MVP

- AM and PM routine entry by brand/product name
- Product lookup by scanned/pasted barcode or QR code
- Product lookup: local catalog first, then FDA DailyMed for OTC/drug labels,
  then Open Beauty Facts; successful lists are stored for the next search.
  Widely used cosmetics missing from Open Beauty Facts (starting with vitamin C
  serums) are stored from brand-published INCI lists.
- Skin type and concern selection
- INCI tokenization and synonym resolution against the local ingredient catalog
- Ingredient catalog search: full-text, prefix, synonym, and typo-tolerant matching
  over the CosIng/Open Beauty Facts inventory, with function and A–Z filters
- Deterministic interaction lookup
- Skin profile severity modifiers
- Unknown ingredient token logging
- Unknown interaction pair logging, batched into one write per analysis
- Research backlog view: ingredient pairs with no rule yet and how often each was
  requested. The skin type and concerns behind a request are recorded for
  prioritisation but are never served by the API, because concerns include
  inferred health conditions and the endpoint is unauthenticated.
- Evidence links: every cited interaction links to its PubMed record
- Skin-type severity escalation shown explicitly on each result
- Accessible UI: keyboard navigation, visible focus states, semantic landmarks,
  live-region status updates, and severity conveyed by icon and label rather than colour alone
- Accounts: registration, sign-in and sign-out, email verification, password
  reset and change, revocable sessions with "sign out all devices", account
  deactivation and deletion, a security activity log, and `user` / `admin` roles
- Social sign-in with Google and Apple, with verified-email account linking
