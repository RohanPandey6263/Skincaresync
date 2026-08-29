"""Upstream lookup: time budget, partial results, and input normalisation."""

from __future__ import annotations

import time

import pytest

from skincaresync import dailymed, lookup, product_catalog
from skincaresync.lookup import (
    Deadline,
    MIN_MATCH_SCORE,
    ProductLookupResult,
    extract_product_code,
    normalize_search_text,
    search_by_brand_and_name,
)


def _candidate(name: str, brand: str = "CeraVe") -> ProductLookupResult:
    return ProductLookupResult(
        code=None,
        brand=brand,
        name=name,
        raw_ingredient_list="Aqua, Glycerin",
        source="open_beauty_facts",
    )


# --- L8: a QR URL carries the barcode and tracking parameters ---------------

@pytest.mark.parametrize(
    "scanned, expected",
    [
        ("1234567890123", "1234567890123"),
        ("https://example.com/products/1234567890123", "1234567890123"),
        # The tracking id used to win because the last match was taken.
        ("https://example.com/p/1234567890123?ref=99999999", "1234567890123"),
        ("https://example.com/p/12345678?utm=87654321", "12345678"),
        ("no-digits-here", "no-digits-here"),
    ],
)
def test_extract_product_code_prefers_the_longest_run(scanned, expected):
    assert extract_product_code(scanned) == expected


# --- M4: accents were deleted rather than folded ---------------------------

@pytest.mark.parametrize(
    "raw, expected",
    [
        ("L'Oréal", ["oreal"]),      # was ["or", "al"], matching almost everything
        ("Bioré", ["biore"]),        # was ["bior"], matching nothing
        ("Nº7", ["no7"]),            # was [], so no local search ran at all
        ("CeraVe", ["cerave"]),
        ("La Roche-Posay", ["la", "roche", "posay"]),
    ],
)
def test_search_text_folds_accents(raw, expected):
    assert [t for t in normalize_search_text(raw).split() if len(t) >= 2] == expected


# --- H4: one lookup could occupy a worker for minutes ----------------------

def test_deadline_shrinks_the_per_call_timeout_as_it_is_spent():
    deadline = Deadline(0.25)
    assert deadline.timeout(cap=10) == pytest.approx(0.25, abs=0.05)
    time.sleep(0.3)
    assert deadline.expired()
    assert deadline.timeout(cap=10) == 0.0


def test_deadline_never_exceeds_the_per_call_cap():
    assert Deadline(3600).timeout(cap=4) == 4


def test_search_stops_calling_upstream_once_the_budget_is_spent(monkeypatch, recorded_writes):
    calls = []
    monkeypatch.setattr(product_catalog, "search_local", lambda *a, **k: [])
    monkeypatch.setattr(dailymed, "search_products", lambda *a, **k: [])

    def slow_search(terms, page_size, deadline):
        calls.append(terms)
        time.sleep(0.15)
        return [_candidate(f"Result for {terms}")]

    monkeypatch.setattr(lookup, "_search_products", slow_search)

    search_by_brand_and_name("CeraVe", "Hydrating Cleanser", budget_seconds=0.2)

    assert len(calls) < 3, "the remaining search terms must be abandoned"


# --- M1: a late failure discarded everything gathered so far ---------------

def test_a_failing_search_term_keeps_the_results_earlier_terms_found(monkeypatch, recorded_writes):
    monkeypatch.setattr(product_catalog, "search_local", lambda *a, **k: [])
    monkeypatch.setattr(dailymed, "search_products", lambda *a, **k: [])

    def flaky(terms, page_size, deadline):
        if terms == "CeraVe":  # the third and last term
            raise ConnectionError("upstream fell over")
        return [_candidate("Hydrating Cleanser")]

    monkeypatch.setattr(lookup, "_search_products", flaky)

    matches = search_by_brand_and_name("CeraVe", "Hydrating Cleanser")

    assert matches, "a partial success must not be reported as no results"
    assert matches[0]["name"] == "Hydrating Cleanser"


def test_upstream_results_are_cached_in_one_write(monkeypatch, recorded_writes):
    """Previously one connection, transaction and commit per product."""
    monkeypatch.setattr(product_catalog, "search_local", lambda *a, **k: [])
    monkeypatch.setattr(dailymed, "search_products", lambda *a, **k: [])
    monkeypatch.setattr(
        lookup, "_search_products",
        lambda terms, page_size, deadline: [
            _candidate("Hydrating Cleanser"), _candidate("Foaming Cleanser")
        ],
    )

    search_by_brand_and_name("CeraVe", "Hydrating Cleanser")

    assert recorded_writes.upsert_calls == 1


# --- L3: the confidence floor lives on the server ---------------------------

def test_low_confidence_matches_are_not_returned(monkeypatch, recorded_writes):
    monkeypatch.setattr(
        product_catalog, "search_local",
        lambda *a, **k: [_candidate("Totally Unrelated Sunscreen", brand="CeraVe")],
    )
    monkeypatch.setattr(dailymed, "search_products", lambda *a, **k: [])
    monkeypatch.setattr(lookup, "_search_products", lambda *a, **k: [])

    matches = search_by_brand_and_name("CeraVe", "Retinol Night Serum")

    assert all(m["similarity_score"] >= MIN_MATCH_SCORE for m in matches)


def test_a_strong_local_match_skips_upstream_entirely(monkeypatch, recorded_writes):
    monkeypatch.setattr(
        product_catalog, "search_local",
        lambda *a, **k: [_candidate("Hydrating Cleanser")],
    )

    def must_not_run(*args, **kwargs):
        raise AssertionError("upstream was called despite a confident local hit")

    monkeypatch.setattr(dailymed, "search_products", must_not_run)
    monkeypatch.setattr(lookup, "_search_products", must_not_run)

    matches = search_by_brand_and_name("CeraVe", "Hydrating Cleanser")
    assert matches[0]["similarity_score"] >= 70


# --- M10: entity expansion in upstream XML ---------------------------------

def test_an_spl_declaring_a_dtd_is_refused():
    bomb = (
        b'<?xml version="1.0"?>'
        b'<!DOCTYPE lolz [<!ENTITY lol "lol">'
        b'<!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;">]>'
        b"<document>&lol2;</document>"
    )
    with pytest.raises(ValueError, match="DTD or entity"):
        dailymed._parse_xml(bomb)


def test_an_ordinary_spl_still_parses():
    assert dailymed._parse_xml(b"<document><title>Fine</title></document>") is not None
