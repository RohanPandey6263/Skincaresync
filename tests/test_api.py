"""Endpoint-level tests.

Nothing exercised `api.py` before, so the request-size limits, the confidence
floor and the shape of the gap backlog were all unverified at the HTTP boundary
where they actually matter.
"""

from __future__ import annotations

import pytest

pytest.importorskip("httpx2", reason="fastapi.testclient needs an HTTP client")

from fastapi.testclient import TestClient  # noqa: E402

from skincaresync import api  # noqa: E402
from skincaresync.api import (  # noqa: E402
    MAX_INGREDIENT_LIST_CHARS,
    MAX_PRODUCTS_PER_ROUTINE,
    app,
)


@pytest.fixture
def client(monkeypatch):
    for limiter in (api.analyze_limiter, api.lookup_limiter, api.catalog_limiter):
        limiter.reset()
    with TestClient(app) as test_client:
        yield test_client


def _product(**overrides) -> dict:
    return {
        "brand": "CeraVe",
        "name": "Hydrating Cleanser",
        "raw_ingredient_list": "Aqua, Glycerin, Niacinamide",
        **overrides,
    }


def _body(**overrides) -> dict:
    return {
        "skin_profile": {"skin_type": "normal", "concerns": []},
        "am_products": [],
        "pm_products": [],
        **overrides,
    }


# --- C1: the request body is what bounds the quadratic pair analysis ---------

def test_analyze_accepts_a_realistic_routine(client, recorded_writes):
    response = client.post(
        "/api/analyze",
        json=_body(am_products=[_product(), _product(name="Vitamin C Serum")]),
    )
    assert response.status_code == 200
    assert "overall_score" in response.json()


def test_analyze_rejects_an_oversized_ingredient_list(client, recorded_writes):
    """The audit's 16.8 KB body produced 89,700 database round trips."""
    response = client.post(
        "/api/analyze",
        json=_body(
            am_products=[
                _product(raw_ingredient_list="Ingredient Name, " * 990),
                _product(),
            ]
        ),
    )
    assert response.status_code == 422
    assert recorded_writes.gap_calls == 0


def test_analyze_rejects_too_many_products(client, recorded_writes):
    response = client.post(
        "/api/analyze",
        json=_body(am_products=[_product()] * (MAX_PRODUCTS_PER_ROUTINE + 1)),
    )
    assert response.status_code == 422


def test_ingredient_list_at_the_limit_is_still_accepted(client, recorded_writes):
    at_limit = ("Aqua, " * 2000)[:MAX_INGREDIENT_LIST_CHARS]
    response = client.post(
        "/api/analyze",
        json=_body(am_products=[_product(raw_ingredient_list=at_limit), _product()]),
    )
    assert response.status_code == 200


# --- M8: a blank list used to be accepted, then silently dropped ------------

def test_analyze_rejects_a_whitespace_only_ingredient_list(client, recorded_writes):
    response = client.post(
        "/api/analyze",
        json=_body(am_products=[_product(raw_ingredient_list="   ")]),
    )
    assert response.status_code == 422
    assert "ingredient" in response.text.lower()


def test_every_submitted_product_appears_in_the_response(client, recorded_writes):
    response = client.post(
        "/api/analyze",
        json=_body(
            am_products=[_product(name="First"), _product(name="Second")],
            pm_products=[_product(name="Third")],
        ),
    )
    assert response.status_code == 200
    names = {entry["product"]["name"] for entry in response.json()["parsed_products"]}
    assert names == {"First", "Second", "Third"}


# --- M2: limit had no lower bound, so LIMIT -1 reached Postgres -------------

@pytest.mark.parametrize("limit", [-1, 0, 101])
def test_gaps_rejects_out_of_range_limits(client, limit):
    assert client.get(f"/api/gaps?limit={limit}").status_code == 422


def test_gaps_accepts_a_valid_limit(client):
    assert client.get("/api/gaps?limit=5").status_code == 200


# --- H5: the backlog must not attribute a skin condition to a request -------

def test_gap_backlog_exposes_no_user_profile_data(client):
    rows = client.get("/api/gaps?limit=25").json()
    assert isinstance(rows, list)
    for row in rows:
        assert "user_concerns" not in row
        assert "user_skin_type" not in row
    if rows:
        assert {"ingredient_a", "ingredient_b", "query_count"} <= set(rows[0])


# --- Rate limiting ----------------------------------------------------------

def test_analyze_is_rate_limited(client, recorded_writes, monkeypatch):
    monkeypatch.setattr(api.analyze_limiter, "limit", 3)
    api.analyze_limiter.reset()
    body = _body(am_products=[_product(), _product(name="Serum")])

    statuses = [client.post("/api/analyze", json=body).status_code for _ in range(5)]

    assert statuses[:3] == [200, 200, 200]
    assert statuses[3:] == [429, 429]


def test_rate_limited_response_tells_the_client_when_to_retry(client, monkeypatch):
    monkeypatch.setattr(api.catalog_limiter, "limit", 1)
    api.catalog_limiter.reset()

    client.get("/api/ingredients?q=retinol")
    response = client.get("/api/ingredients?q=retinol")

    assert response.status_code == 429
    assert int(response.headers["retry-after"]) >= 1


# --- Query validation -------------------------------------------------------

@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1", "letter=ab", "source=bogus"])
def test_ingredient_search_rejects_invalid_parameters(client, query):
    assert client.get(f"/api/ingredients?{query}").status_code == 422


def test_ingredient_detail_404s_for_an_unknown_id(client):
    assert client.get("/api/ingredients/999999999").status_code == 404


def test_product_search_requires_a_term(client):
    """An empty search used to fan out to two third-party services for nothing."""
    assert client.get("/api/products/search").status_code == 422
    assert client.get("/api/products/search?brand=%20&name=%20").status_code == 422


def test_health_reports_database_state(client):
    payload = client.get("/api/health").json()
    assert payload["ok"] is True
    assert payload["database"] == "ok"
    assert payload["ingredient_count"] > 0
