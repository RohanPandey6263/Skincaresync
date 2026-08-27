import psycopg2
import pytest

from skincaresync.database import get_cursor
from skincaresync.engine import ProductInput, SkinProfileInput, analyze_routines


def _fetch_interactions():
    try:
        with get_cursor() as cur:
            cur.execute(
                """
                SELECT
                    i.interaction_id,
                    i.interaction_type,
                    i.conflict_scope,
                    i.source_citation,
                    a.inci_name AS ingredient_a,
                    b.inci_name AS ingredient_b
                FROM interactions i
                JOIN ingredients a ON a.ingridient_id = i.ingredient_a_id
                JOIN ingredients b ON b.ingridient_id = i.ingredient_b_id
                ORDER BY i.interaction_id
                """
            )
            return cur.fetchall()
    except psycopg2.OperationalError as exc:
        pytest.skip(f"Postgres is not available: {exc}")


def test_interaction_dataset_has_pubmed_sources_and_engine_coverage():
    interactions = _fetch_interactions()

    assert len(interactions) >= 150
    assert all(row["source_citation"].startswith("PMID:") for row in interactions)

    skin = SkinProfileInput(skin_type="normal", concerns=[])
    category_map = {
        "conflict": "conflicts",
        "caution": "cautions",
        "redundant": "cautions",
        "synergy": "synergies",
    }

    failures = []
    for row in interactions:
        product_a = ProductInput(
            name=f"Test {row['ingredient_a']}",
            brand="Dataset Test",
            raw_ingredient_list=row["ingredient_a"],
        )
        product_b = ProductInput(
            name=f"Test {row['ingredient_b']}",
            brand="Dataset Test",
            raw_ingredient_list=row["ingredient_b"],
        )
        if row["conflict_scope"] == "cumulative":
            result = analyze_routines([product_a], [product_b], skin)
        else:
            result = analyze_routines([product_a, product_b], [], skin)

        bucket = category_map[row["interaction_type"]]
        if not any(item["interaction_id"] == row["interaction_id"] for item in result[bucket]):
            failures.append(row["interaction_id"])

    assert failures == []

