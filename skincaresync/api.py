from typing import Literal

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .database import get_cursor
from .engine import (
    ProductInput,
    SkinProfileInput,
    analyze_routines,
    fetch_gap_backlog,
)
from .ingredients import (
    get_catalog_facets,
    get_ingredient,
    search_ingredients,
    suggest_ingredients,
)
from .lookup import lookup_by_code, search_by_brand_and_name


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
def ingredient_search(
    q: str = Query(default="", max_length=120),
    functions: list[str] = Query(default=[]),
    source: str | None = Query(default=None, pattern="^(curated|open-beauty-facts)$"),
    letter: str | None = Query(default=None, max_length=1),
    only_with_interactions: bool = False,
    only_restricted: bool = False,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> dict:
    return search_ingredients(
        query=q,
        functions=functions or None,
        source=source,
        letter=letter,
        only_with_interactions=only_with_interactions,
        only_restricted=only_restricted,
        limit=limit,
        offset=offset,
    )


@app.get("/api/ingredients/suggest")
def ingredient_suggest(
    q: str = Query(min_length=1, max_length=80),
    limit: int = Query(default=8, ge=1, le=20),
) -> list[dict]:
    return suggest_ingredients(q, limit=limit)


@app.get("/api/ingredients/facets")
def ingredient_facets() -> dict:
    return get_catalog_facets()


@app.get("/api/ingredients/{ingredient_id}")
def ingredient_detail(ingredient_id: int) -> dict:
    ingredient = get_ingredient(ingredient_id)
    if not ingredient:
        raise HTTPException(status_code=404, detail="Ingredient not found")
    return ingredient


@app.get("/api/products/code")
def product_by_code(value: str = Query(max_length=500)) -> dict:
    try:
        product = lookup_by_code(value)
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Product lookup service is unavailable") from exc

    if not product:
        raise HTTPException(status_code=404, detail="No ingredient list found for this product code")
    return product


@app.get("/api/products/search")
def product_search(
    brand: str = Query(default="", max_length=100),
    name: str = Query(default="", max_length=150),
) -> list[dict]:
    try:
        return search_by_brand_and_name(brand=brand, name=name)
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Product lookup service is unavailable") from exc


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

