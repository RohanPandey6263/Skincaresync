"""Shared test fixtures.

The suite runs against the developer's real database. Reads are fine; writes are
not. `test_interactions_dataset` alone used to call `analyze_routines` 150+
times, and every one of those recorded rows in `interaction_gaps` and
`parser_unknowns` under the brand "Dataset Test" -- so running the tests
polluted the research backlog the application then displays.

Writes are therefore stubbed for every test by default and recorded in memory so
assertions can inspect them. A test that genuinely needs to write marks itself
with `@pytest.mark.allow_db_writes`.
"""

from __future__ import annotations

import pytest

from skincaresync import engine, parser, product_catalog


class RecordedWrites:
    """What the code under test would have persisted."""

    def __init__(self) -> None:
        self.gap_pairs: list[tuple[int, int]] = []
        self.gap_calls = 0
        self.unknown_tokens: list[tuple[str, str]] = []
        self.unknown_calls = 0
        self.upserted: list = []
        self.upsert_calls = 0


@pytest.fixture
def recorded_writes(monkeypatch) -> RecordedWrites:
    """Capture attempted writes instead of performing them."""
    recorded = RecordedWrites()

    def fake_gaps(pairs, skin_profile):
        pairs = list(pairs)
        recorded.gap_pairs.extend(pairs)
        recorded.gap_calls += 1
        return len(pairs)

    def fake_unknowns(unknowns, source_product=None):
        recorded.unknown_tokens.extend(unknowns)
        recorded.unknown_calls += 1

    def fake_upserts(products):
        products = list(products)
        recorded.upserted.extend(products)
        recorded.upsert_calls += 1
        return len(products)

    monkeypatch.setattr(engine, "log_interaction_gaps", fake_gaps)
    monkeypatch.setattr(parser, "log_parser_unknowns", fake_unknowns)
    monkeypatch.setattr(product_catalog, "upsert_products", fake_upserts)
    return recorded


@pytest.fixture(autouse=True)
def block_db_writes(request, monkeypatch):
    """Neutralise every write path unless the test opts in."""
    if request.node.get_closest_marker("allow_db_writes"):
        return
    if "recorded_writes" in request.fixturenames:
        return  # that fixture already installed its own stubs
    monkeypatch.setattr(engine, "log_interaction_gaps", lambda pairs, skin_profile: 0)
    monkeypatch.setattr(parser, "log_parser_unknowns", lambda unknowns, source_product=None: None)
    monkeypatch.setattr(product_catalog, "upsert_products", lambda products: 0)


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "allow_db_writes: test may write to the database"
    )
