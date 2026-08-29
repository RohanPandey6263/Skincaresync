"""HTTP API.

Every endpoint is unauthenticated, so the request body is the only thing an
attacker controls and the only thing that needs bounding. The size limits below
are what stop `/api/analyze` -- whose cost is quadratic in the number of distinct
ingredients -- from being turned into a denial-of-service amplifier.
"""

import logging
import os
from typing import Literal

import psycopg2
from fastapi import Depends, FastAPI, HTTPException, Path, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator

from .database import PoolTimeout, get_cursor
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
from .logging_config import configure_logging
from .lookup import lookup_by_code, search_by_brand_and_name
from .ratelimit import RateLimiter, limiter_dependency

logger = logging.getLogger(__name__)
configure_logging()

IS_PRODUCTION = os.getenv("SKINCARESYNC_ENV", "development").lower() == "production"
TRUST_PROXY = os.getenv("TRUST_PROXY", "").lower() in {"1", "true", "yes"}
CORS_ORIGINS = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173"
    ).split(",")
    if origin.strip()
]

# Analysis compares every ingredient of every product against every other, so
# cost grows with the square of the distinct ingredient count. A real routine is
# ten products of forty ingredients; these bounds sit well above that and well
# below the point where a request becomes expensive.
MAX_PRODUCTS_PER_ROUTINE = 20
MAX_INGREDIENT_LIST_CHARS = 10_000
MAX_CONCERNS = 12

# Analysis and product lookup are the costly endpoints -- one is quadratic, the
# other fans out to DailyMed and Open Beauty Facts. Catalog search is cheap and
# fires per keystroke, so it gets room to breathe.
analyze_limiter = RateLimiter(limit=int(os.getenv("RATE_LIMIT_ANALYZE", "20")))
lookup_limiter = RateLimiter(limit=int(os.getenv("RATE_LIMIT_LOOKUP", "30")))
catalog_limiter = RateLimiter(limit=int(os.getenv("RATE_LIMIT_CATALOG", "300")))

rate_limit_analyze = Depends(limiter_dependency(analyze_limiter, TRUST_PROXY))
rate_limit_lookup = Depends(limiter_dependency(lookup_limiter, TRUST_PROXY))
rate_limit_catalog = Depends(limiter_dependency(catalog_limiter, TRUST_PROXY))


class ProductRequest(BaseModel):
    brand: str = Field(default="", max_length=200)
    name: str = Field(min_length=1, max_length=300)
    raw_ingredient_list: str = Field(min_length=1, max_length=MAX_INGREDIENT_LIST_CHARS)

    @field_validator("raw_ingredient_list")
    @classmethod
    def must_not_be_blank(cls, value: str) -> str:
        # `min_length=1` accepts a single space, which the engine then silently
        # drops from the analysis -- the product simply vanished from the report.
        if not value.strip():
            raise ValueError("must contain at least one ingredient")
        return value


class SkinProfileRequest(BaseModel):
    skin_type: Literal["oily", "dry", "combination", "sensitive", "normal"]
    concerns: list[str] = Field(default_factory=list, max_length=MAX_CONCERNS)

    @field_validator("concerns")
    @classmethod
    def bound_concern_length(cls, value: list[str]) -> list[str]:
        if any(len(concern) > 60 for concern in value):
            raise ValueError("concern names must be 60 characters or fewer")
        return value


class AnalyzeRequest(BaseModel):
    skin_profile: SkinProfileRequest
    am_products: list[ProductRequest] = Field(
        default_factory=list, max_length=MAX_PRODUCTS_PER_ROUTINE
    )
    pm_products: list[ProductRequest] = Field(
        default_factory=list, max_length=MAX_PRODUCTS_PER_ROUTINE
    )


app = FastAPI(
    title="SkincareSync API",
    # The interactive docs expose the full schema and a live request console.
    # Useful locally, not something to publish by default.
    docs_url=None if IS_PRODUCTION else "/docs",
    redoc_url=None if IS_PRODUCTION else "/redoc",
    openapi_url=None if IS_PRODUCTION else "/openapi.json",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


@app.exception_handler(PoolTimeout)
def handle_pool_timeout(request: Request, exc: PoolTimeout) -> JSONResponse:
    """Shed load with a retryable status instead of a bare 500."""
    logger.error("pool timeout serving %s", request.url.path)
    return JSONResponse(
        status_code=503,
        content={"detail": "The service is busy. Please try again in a moment."},
        headers={"Retry-After": "5"},
    )


@app.exception_handler(psycopg2.Error)
def handle_database_error(request: Request, exc: psycopg2.Error) -> JSONResponse:
    logger.exception("database error serving %s", request.url.path)
    return JSONResponse(
        status_code=503,
        content={"detail": "The database is unavailable. Please try again shortly."},
    )


@app.get("/api/health")
def health() -> dict:
    """Liveness plus a catalog sanity check.

    Reported separately so a database problem shows up as a degraded body rather
    than an error the caller has to interpret.
    """
    try:
        with get_cursor() as cur:
            cur.execute("SELECT COUNT(*) AS ingredient_count FROM ingredients")
            row = cur.fetchone()
    except Exception:
        logger.exception("health check could not reach the database")
        return JSONResponse(
            status_code=503,
            content={"ok": False, "database": "unavailable", "ingredient_count": None},
        )
    return {"ok": True, "database": "ok", "ingredient_count": row["ingredient_count"]}


@app.get("/api/ingredients", dependencies=[rate_limit_catalog])
def ingredient_search(
    q: str = Query(default="", max_length=120),
    functions: list[str] = Query(default=[], max_length=20),
    source: str | None = Query(default=None, pattern="^(curated|open-beauty-facts)$"),
    letter: str | None = Query(default=None, pattern="^([A-Za-z]|#)$"),
    only_with_interactions: bool = False,
    only_restricted: bool = False,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0, le=10_000),
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


@app.get("/api/ingredients/suggest", dependencies=[rate_limit_catalog])
def ingredient_suggest(
    q: str = Query(min_length=1, max_length=80),
    limit: int = Query(default=8, ge=1, le=20),
) -> list[dict]:
    return suggest_ingredients(q, limit=limit)


@app.get("/api/ingredients/facets", dependencies=[rate_limit_catalog])
def ingredient_facets() -> dict:
    return get_catalog_facets()


@app.get("/api/ingredients/{ingredient_id}", dependencies=[rate_limit_catalog])
def ingredient_detail(ingredient_id: int = Path(ge=1)) -> dict:
    ingredient = get_ingredient(ingredient_id)
    if not ingredient:
        raise HTTPException(status_code=404, detail="Ingredient not found")
    return ingredient


@app.get("/api/products/code", dependencies=[rate_limit_lookup])
def product_by_code(value: str = Query(min_length=1, max_length=500)) -> dict:
    try:
        product = lookup_by_code(value)
    except Exception as exc:
        logger.exception("product code lookup failed for %r", value)
        raise HTTPException(
            status_code=502, detail="Product lookup service is unavailable"
        ) from exc

    if not product:
        raise HTTPException(
            status_code=404, detail="No ingredient list found for this product code"
        )
    return product


@app.get("/api/products/search", dependencies=[rate_limit_lookup])
def product_search(
    brand: str = Query(default="", max_length=100),
    name: str = Query(default="", max_length=150),
) -> list[dict]:
    if not brand.strip() and not name.strip():
        raise HTTPException(
            status_code=422, detail="Provide a brand or a product name to search"
        )
    try:
        return search_by_brand_and_name(brand=brand, name=name)
    except Exception as exc:
        logger.exception("product search failed for brand=%r name=%r", brand, name)
        raise HTTPException(
            status_code=502, detail="Product lookup service is unavailable"
        ) from exc


@app.post("/api/analyze", dependencies=[rate_limit_analyze])
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


@app.get("/api/gaps", dependencies=[rate_limit_catalog])
def gaps(limit: int = Query(default=50, ge=1, le=100)) -> list[dict]:
    return fetch_gap_backlog(limit=limit)
