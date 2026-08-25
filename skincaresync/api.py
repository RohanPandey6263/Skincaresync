from typing import Literal

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .database import get_cursor
from .engine import (
    ProductInput,
    SkinProfileInput,
    analyze_routines,
    fetch_gap_backlog,
)


class ProductRequest(BaseModel):
    brand: str = ""
    name: str
    raw_ingredient_list: str = Field(min_length=1)


class SkinProfileRequest(BaseModel):
    skin_type: Literal["oily", "dry", "combination", "sensitive", "normal"]
    concerns: list[str] = Field(default_factory=list)


class AnalyzeRequest(BaseModel):
    skin_profile: SkinProfileRequest
    am_products: list[ProductRequest] = Field(default_factory=list)
    pm_products: list[ProductRequest] = Field(default_factory=list)


app = FastAPI(title="SkincareSync API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health() -> dict:
    with get_cursor() as cur:
        cur.execute("SELECT COUNT(*) AS ingredient_count FROM ingredients")
        row = cur.fetchone()
    return {"ok": True, "ingredient_count": row["ingredient_count"]}


@app.get("/api/ingredients")
def search_ingredients(q: str = Query(default="", max_length=100), limit: int = Query(default=20, le=50)) -> list[dict]:
    search = f"%{q.strip()}%"
    with get_cursor() as cur:
        cur.execute(
            """
            SELECT
                ingridient_id AS id,
                inci_name,
                synonyms,
                category,
                ph_min,
                ph_max,
                comodogenic
            FROM ingredients
            WHERE %s = '%%'
               OR inci_name ILIKE %s
               OR EXISTS (
                    SELECT 1
                    FROM unnest(COALESCE(synonyms, ARRAY[]::text[])) synonym
                    WHERE synonym ILIKE %s
               )
            ORDER BY inci_name
            LIMIT %s
            """,
            (search, search, search, limit),
        )
        return [dict(row) for row in cur.fetchall()]


@app.post("/api/analyze")
def analyze(request: AnalyzeRequest) -> dict:
    return analyze_routines(
        am_products=[
            ProductInput(
                brand=product.brand,
                name=product.name,
                raw_ingredient_list=product.raw_ingredient_list,
            )
            for product in request.am_products
        ],
        pm_products=[
            ProductInput(
                brand=product.brand,
                name=product.name,
                raw_ingredient_list=product.raw_ingredient_list,
            )
            for product in request.pm_products
        ],
        skin_profile=SkinProfileInput(
            skin_type=request.skin_profile.skin_type,
            concerns=request.skin_profile.concerns,
        ),
    )


@app.get("/api/gaps")
def gaps(limit: int = Query(default=50, le=100)) -> list[dict]:
    return fetch_gap_backlog(limit=limit)

