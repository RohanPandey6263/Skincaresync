# SkincareSync MVP

SkincareSync is a routine-level skincare compatibility MVP. The backend uses FastAPI and PostgreSQL, reusing the existing `ingredients` table. The frontend is a Vite React app.

SkincareSync helps users check whether the products in their skincare routine work well together. It scans or finds ingredient lists, compares active ingredients, flags conflicts or cautions, and explains safer AM/PM routine choices using a sourced compatibility database.

## Run The Database Migration

```bash
psql -d postgres -U rohanpandey -f aidatabase.sql
psql -d postgres -U rohanpandey -f migrations/002_ingredient_catalog.sql
psql -d postgres -U rohanpandey -f migrations/003_ingredient_search_alias.sql
psql -d postgres -U rohanpandey -f migrations/004_product_catalog.sql
```

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

## Run The Backend

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn skincaresync.api:app --reload
```

The API runs at `http://localhost:8000`.

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
- Silent unknown interaction pair logging for developers
- Research backlog view (internal)
- Evidence links: every cited interaction links to its PubMed record
- Skin-type severity escalation shown explicitly on each result
- Accessible UI: keyboard navigation, visible focus states, semantic landmarks,
  live-region status updates, and severity conveyed by icon and label rather than colour alone
