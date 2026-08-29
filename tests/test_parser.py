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

