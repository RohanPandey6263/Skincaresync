from skincaresync.published_labels import (
    contains_vitamin_c,
    normalize_published_inci,
    products_for_family,
)


def test_normalize_maps_water_aliases_and_keeps_hexanediol():
    inci = normalize_published_inci(
        "967660 23 - INGREDIENTS • AQUA / WATER • ASCORBIC ACID • 1,2-Hexanediol "
        "• PARFUM / FRAGRANCE (F.I.L. Z70046241/1)"
    )
    assert inci.startswith("Aqua, Ascorbic Acid, 1,2-Hexanediol")
    assert "Parfum" in inci
    assert "F.I.L" not in inci
    assert "967660" not in inci


def test_l_ascorbic_acid_maps_to_ascorbic_acid():
    inci = normalize_published_inci("Water, L-Ascorbic Acid, Ferulic Acid")
    assert inci == "Aqua, Ascorbic Acid, Ferulic Acid"


def test_normalize_strips_percent_notes_and_maps_ethyl_typo():
    inci = normalize_published_inci(
        "Citrus Junos Fruit Extract [83%], Distilled Water, 3-0-Ethyl Ascorbic Acid"
    )
    assert inci == "Citrus Junos Fruit Extract, Aqua, 3-O-Ethyl Ascorbic Acid"


def test_vitamin_c_family_lists_all_contain_a_vitamin_c_form():
    products = products_for_family("vitamin-c")
    assert len(products) >= 25
    for product in products:
        inci = normalize_published_inci(product.raw_ingredient_list)
        assert contains_vitamin_c(inci), product.name
        assert len(inci.split(",")) >= 2
