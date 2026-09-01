import pytest

from skincaresync.parser import Ingredient, IngredientResolver, normalize_token, tokenize_inci


def test_tokenize_preserves_commas_inside_parentheses():
    tokens = tokenize_inci("Ingredients: Water, Parfum (Fragrance, Aroma), Retinol")

    assert tokens == ["Water", "Parfum (Fragrance, Aroma)", "Retinol"]


def test_normalize_token_strips_percent_and_parenthetical_detail():
    assert normalize_token("Retinol 0.2% (Vitamin A).") == "retinol"


def test_resolver_matches_exact_and_synonym():
    retinol = Ingredient(
        id=6,
        inci_name="Retinol",
        synonyms=["Vitamin A", "Pure Retinol"],
        category="retinoid",
        ph_min=5.5,
        ph_max=7,
        comodogenic=2,
    )
    resolver = IngredientResolver([retinol])

    exact = resolver.resolve_token("Retinol")
    synonym = resolver.resolve_token("Vitamin A")

    assert exact.ingredient == retinol
    assert exact.match_type == "exact"
    assert synonym.ingredient == retinol
    assert synonym.match_type == "synonym"


def test_resolver_matches_alternate_international_names():
    caffeine = Ingredient(
        id=40,
        inci_name="Caffeine",
        synonyms=[],
        category="skin-conditioning",
        ph_min=None,
        ph_max=None,
        comodogenic=None,
        alt_names=["Caféine"],
    )
    resolver = IngredientResolver([caffeine])
    resolved = resolver.resolve_token("Caféine")
    assert resolved.ingredient == caffeine
    assert resolved.match_type == "synonym"


def test_resolver_preserves_first_canonical_match_for_normalized_duplicates():
    hydroquinone = Ingredient(
        id=21,
        inci_name="Hydroquinone",
        synonyms=[],
        category="brightening",
        ph_min=None,
        ph_max=None,
        comodogenic=None,
    )
    hydroquinone_strength = Ingredient(
        id=121,
        inci_name="Hydroquinone 4%",
        synonyms=[],
        category="skin_tone_risk",
        ph_min=None,
        ph_max=None,
        comodogenic=None,
    )
    resolver = IngredientResolver([hydroquinone, hydroquinone_strength])

    resolved = resolver.resolve_token("Hydroquinone")

    assert resolved.ingredient == hydroquinone



def _retinoid_catalog() -> list[Ingredient]:
    """Tretinoin plus the neighbours a loose matcher would confuse it with."""
    return [
        Ingredient(
            id=9,
            inci_name="Tretinoin",
            synonyms=["Retinoic Acid", "All-trans Retinoic Acid", "Retin-A"],
            category="retinoid",
            ph_min=None,
            ph_max=None,
            comodogenic=None,
        ),
        Ingredient(
            id=6,
            inci_name="Retinol",
            synonyms=["Vitamin A"],
            category="retinoid",
            ph_min=None,
            ph_max=None,
            comodogenic=2,
        ),
        Ingredient(
            id=7,
            inci_name="Retinal",
            synonyms=["Retinaldehyde"],
            category="retinoid",
            ph_min=None,
            ph_max=None,
            comodogenic=None,
        ),
        Ingredient(
            id=7975,
            inci_name="CIS-RETINOIC ACID",
            synonyms=[],
            category="retinoid",
            ph_min=None,
            ph_max=None,
            comodogenic=None,
        ),
    ]


@pytest.mark.parametrize(
    "token",
    [
        "Retin A",  # brand name without the hyphen
        "retin a",
        "RETIN-A MICRO",  # product line suffix
        "Retin-A Gel",
        "Tretinoin Cream",  # dosage form suffix
        "tretinoin gel",
        "all trans retinoic acid",  # unhyphenated chemical name
        "tretinion",  # misspellings
        "trentinoin",
        "Tret",
    ],
)
def test_resolver_special_cases_tretinoin_variants(token):
    """Tretinoin is prescription-only, so it is typed rather than copied from
    an INCI list. None of these forms are in the catalog, and a miss drops the
    strongest active in the routine from the analysis entirely."""
    resolver = IngredientResolver(_retinoid_catalog())

    resolved = resolver.resolve_token(token)

    assert resolved.ingredient is not None, f"{token!r} did not resolve"
    assert resolved.ingredient.inci_name == "Tretinoin"
    assert resolved.match_type == "alias"


@pytest.mark.parametrize(
    ("token", "expected"),
    [
        ("Retinol", "Retinol"),
        ("Retinal", "Retinal"),
        ("Vitamin A", "Retinol"),
        ("CIS-RETINOIC ACID", "CIS-RETINOIC ACID"),
    ],
)
def test_tretinoin_special_case_does_not_capture_its_neighbours(token, expected):
    """The catalog is authoritative: a name it already knows must never be
    rewritten by the fallback. `CIS-RETINOIC ACID` is the sharp case -- it is a
    different molecule that the tretinoin pattern would otherwise swallow."""
    resolver = IngredientResolver(_retinoid_catalog())

    resolved = resolver.resolve_token(token)

    assert resolved.ingredient is not None
    assert resolved.ingredient.inci_name == expected
    assert resolved.match_type != "alias"
