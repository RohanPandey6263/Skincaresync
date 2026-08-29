import pytest

from skincaresync.database import get_cursor
from skincaresync.ingredients import search_ingredients, suggest_ingredients
from skincaresync.parser import Ingredient, IngredientResolver


def _catalog_size() -> int:
    try:
        with get_cursor() as cur:
            cur.execute("SELECT COUNT(*) AS n FROM ingredients")
            return cur.fetchone()["n"]
    except Exception:
        return 0


pytestmark = pytest.mark.skipif(
    _catalog_size() < 1000,
    reason="Ingredient catalog has not been imported yet",
)


def _names(query, **kwargs):
    result = search_ingredients(query, limit=8, **kwargs)
    return [item["display_name"] for item in result["items"]], result["total"]


def test_common_and_partial_names_rank_canonical_ingredients_first():
    retinol, _ = _names("retinol")
    assert retinol[0] == "Retinol"

    niacinamide, total = _names("niacinamid")
    assert niacinamide[0] == "Niacinamide"
    assert total >= 1

    hyaluronic, _ = _names("hyaluronic")
    assert hyaluronic[0] == "Hyaluronic Acid"


def test_typo_tolerance_finds_niacinamide():
    names, _ = _names("niacinimide")
    assert names[0] == "Niacinamide"


def test_synonym_vitamin_c_resolves_to_ascorbic_acid():
    names, _ = _names("vitamin c")
    assert names[0] == "Ascorbic Acid"


def test_international_and_scientific_names():
    tomato, tomato_total = _names("tomato")
    assert tomato_total >= 1
    assert any("Tomato" in name for name in tomato)

    lycopersicum, _ = _names("lycopersicum")
    assert any("Lycopersicum" in name for name in lycopersicum)

    centella, _ = _names("centella")
    assert any("Centella" in name for name in centella)


def test_multi_word_query_does_not_collapse_to_other_acids():
    names, _ = _names("tranexamic acid")
    assert names[0] == "Tranexamic Acid"
    assert "Tartaric Acid" not in names


def test_punctuation_and_hyphenated_inci_tokens():
    names, total = _names("PEG-40")
    assert total >= 1
    assert names[0].startswith("PEG-40")

    names, total = _names("c12-15")
    assert total >= 1
    assert names[0].upper().startswith("C12-15")


def test_rare_and_specialty_actives():
    bakuchiol, _ = _names("bakuchiol")
    assert bakuchiol[0] == "Bakuchiol"

    names, _ = _names("propolis")
    assert any("Propolis" in name for name in names)
    assert "Proline" not in names


def test_function_filter_limits_results_to_that_function():
    result = search_ingredients("ascorbic", functions=["antioxidant"], limit=10)
    assert result["total"] >= 1
    assert all("antioxidant" in item["functions"] for item in result["items"])


def test_suggest_prefix_and_fuzzy():
    suggestions = suggest_ingredients("niacin")
    labels = [item["display_name"] for item in suggestions]
    assert "Niacinamide" in labels or "Niacin" in labels


def test_resolver_matches_imported_alternate_names():
    ascorbic = Ingredient(
        id=1,
        inci_name="Ascorbic Acid",
        synonyms=["Vitamin C"],
        category="antioxidant",
        ph_min=None,
        ph_max=None,
        comodogenic=None,
        alt_names=["Ácido ascórbico"],
    )
    resolver = IngredientResolver([ascorbic])
    assert resolver.resolve_token("Ácido ascórbico").ingredient == ascorbic
    assert resolver.resolve_token("Vitamin C").ingredient == ascorbic
