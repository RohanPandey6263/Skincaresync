from skincaresync.lookup import (
    ProductLookupResult,
    brand_similarity_score,
    extract_product_code,
    name_similarity_score,
    product_similarity_score,
)


def test_extract_product_code_from_plain_barcode():
    assert extract_product_code("1234567890123") == "1234567890123"


def test_extract_product_code_from_qr_url():
    assert extract_product_code("https://example.com/products/1234567890123") == "1234567890123"


def test_product_similarity_handles_shorthand_brand_and_product_name():
    candidate = ProductLookupResult(
        code="0769915190977",
        brand="The Ordinary",
        name="The Ordinary Glycolic Acid 7% Toning Solution",
        raw_ingredient_list="Aqua, Glycolic Acid",
        source="open_beauty_facts",
    )

    score = product_similarity_score("ordinary", "glycolic acid toner", candidate)

    assert score >= 75


def test_brand_similarity_is_strict_enough_to_reject_wrong_brand():
    candidate = ProductLookupResult(
        code="0769915190977",
        brand="The Ordinary",
        name="The Ordinary Glycolic Acid 7% Toning Solution",
        raw_ingredient_list="Aqua, Glycolic Acid",
        source="open_beauty_facts",
    )

    assert brand_similarity_score("ordinary", candidate) >= 90
    assert brand_similarity_score("CeraVe", candidate) < 70


def test_name_similarity_rejects_unrelated_same_brand_product():
    candidate = ProductLookupResult(
        code="3337875597180",
        brand="CeraVe",
        name="Hydrating Cleanser",
        raw_ingredient_list="Aqua, Glycerin",
        source="open_beauty_facts",
    )

    assert name_similarity_score("glycolic acid toner", candidate) < 50

