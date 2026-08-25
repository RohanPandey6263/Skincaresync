# SkincareSync MVP

SkincareSync is a routine-level skincare compatibility MVP. The backend uses FastAPI and PostgreSQL, reusing the existing `ingredients` table. The frontend is a Vite React app.

## Run The Database Migration

```bash
psql -d postgres -U rohanpandey -f aidatabase.sql
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

## What Works In This MVP

- Manual AM and PM product entry
- Skin type and concern selection
- INCI tokenization and synonym resolution against the local ingredient catalog
- Deterministic interaction lookup
- Skin profile severity modifiers
- Unknown ingredient token logging
- Unknown interaction pair logging
- Research backlog view

