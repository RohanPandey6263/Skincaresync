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
```

Migration 005 is required: product lookup queries the accent-folded
`products.search_text` column that it adds.

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

## Run The Tests

```bash
source venv/bin/activate
pytest
```

The suite reads from the development database but never writes to it: a fixture
in `tests/conftest.py` stubs every write path. A test that genuinely needs to
write marks itself `@pytest.mark.allow_db_writes`.

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
