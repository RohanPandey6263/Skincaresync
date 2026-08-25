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

