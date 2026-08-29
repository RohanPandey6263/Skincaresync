from skincaresync.dailymed import (
    aliases_for,
    parse_listing_title,
    parse_spl,
    search_queries,
    to_inci_name,
)

MINIMAL_SPL = """<?xml version="1.0"?>
<document xmlns="urn:hl7-org:v3">
  <title>Panoxyl Acne Foaming Wash</title>
  <manufacturedProduct>
    <manufacturedMedicine>
      <name>PanOxyl</name>
      <code code="0316-0228" codeSystem="2.16.840.1.113883.6.69"/>
      <ingredient classCode="ACTIB">
        <ingredientSubstance><name>BENZOYL PEROXIDE</name></ingredientSubstance>
      </ingredient>
      <ingredient classCode="IACT">
        <ingredientSubstance><name>WATER</name></ingredientSubstance>
      </ingredient>
      <ingredient classCode="IACT">
        <ingredientSubstance><name>GLYCERIN</name></ingredientSubstance>
      </ingredient>
    </manufacturedMedicine>
  </manufacturedProduct>
</document>
"""


def test_usan_water_maps_to_inci_aqua():
    assert to_inci_name("WATER") == "Aqua"
    assert to_inci_name("BENZOYL PEROXIDE") == "Benzoyl Peroxide"
    assert to_inci_name("1,2-HEXANEDIOL") == "1,2-Hexanediol"
    assert to_inci_name("Carbomer Homopolymer, Unspecified Type") == (
        "Carbomer Homopolymer Unspecified Type"
    )


def test_parse_spl_puts_active_first_and_maps_inci():
    products = parse_spl(MINIMAL_SPL.encode(), "test-setid")
    assert len(products) == 1
    product = products[0]
    assert product.source == "dailymed"
    assert product.ndc == "0316-0228"
    assert product.raw_ingredient_list.startswith("Benzoyl Peroxide")
    assert "Aqua" in product.raw_ingredient_list
    assert "Glycerin" in product.raw_ingredient_list
    assert "cleanser" in product.search_aliases


def test_search_queries_do_not_send_generic_words_alone():
    assert search_queries("PanOxyl", "cleanser") == ["PanOxyl"]
    assert search_queries("", "cleanser") == []
    assert search_queries("PanOxyl", "foaming wash")[0].lower().startswith("panoxyl")


def test_wash_title_gets_cleanser_alias():
    aliases = aliases_for("Panoxyl Acne Foaming Wash", "PanOxyl")
    assert "cleanser" in aliases
    assert "face wash" in aliases


def test_cleansing_bar_gets_cleanser_alias():
    aliases = aliases_for("Panoxyl Acne Cleansing Bar", "Panoxyl Acne Cleansing Bar")
    assert "cleanser" in aliases


def test_listing_title_extracts_brand_from_dailymed_search_row():
    brand, name = parse_listing_title(
        "PANOXYL (BENZOYL PEROXIDE) CREAM [CROWN LABORATORIES]"
    )
    assert brand == "Panoxyl"
    assert name == "Panoxyl Cream"

    brand, name = parse_listing_title(
        "GOLD BOND MAXIMUM STRENGTH FOOT PAIN RELIEF (LIDOCAINE HYDROCHLORIDE) CREAM [GOLD BOND CO LLC]"
    )
    assert brand == "Gold Bond"
    assert "Gold Bond" in name

    brand, name = parse_listing_title(
        "DIFFERIN MAX STRENGTH ACNE FOAMING BPO CLEANSER (BENZOYL PEROXIDE) SOLUTION [GALDERMA LABORATORIES, L.P.]"
    )
    assert brand == "Differin"
    assert "Foaming" in name


def test_parse_spl_prefers_listing_title_over_drug_facts():
    xml = """<?xml version="1.0"?>
<document xmlns="urn:hl7-org:v3">
  <title>Drug Facts</title>
  <manufacturedProduct>
    <manufacturedMedicine>
      <name>Differin Max Strength Acne Foaming BPO Cleanser</name>
      <code code="0299-4137" codeSystem="2.16.840.1.113883.6.69"/>
      <ingredient classCode="ACTIB">
        <ingredientSubstance><name>BENZOYL PEROXIDE</name></ingredientSubstance>
      </ingredient>
      <ingredient classCode="IACT">
        <ingredientSubstance><name>WATER</name></ingredientSubstance>
      </ingredient>
      <ingredient classCode="IACT">
        <ingredientSubstance><name>Carbomer Homopolymer, Unspecified Type</name></ingredientSubstance>
      </ingredient>
    </manufacturedMedicine>
  </manufacturedProduct>
</document>
"""
    products = parse_spl(
        xml.encode(),
        "setid-differin",
        listing_title="DIFFERIN MAX STRENGTH ACNE FOAMING BPO CLEANSER (BENZOYL PEROXIDE) SOLUTION [GALDERMA]",
    )
    assert len(products) == 1
    product = products[0]
    assert product.brand == "Differin"
    assert "Cleanser" in product.name
    assert product.raw_ingredient_list.startswith("Benzoyl Peroxide")
    assert "Aqua" in product.raw_ingredient_list
    assert "Carbomer Homopolymer Unspecified Type" in product.raw_ingredient_list
    assert "Homopolymer, Unspecified" not in product.raw_ingredient_list


def test_parse_spl_uses_xml_title_when_label_is_just_the_brand():
    products = parse_spl(MINIMAL_SPL.encode(), "test-setid")
    assert products[0].name == "Panoxyl Acne Foaming Wash"
    assert products[0].brand.lower() == "panoxyl"


def test_parse_spl_prefers_document_title_over_generic_listing_form():
    products = parse_spl(
        MINIMAL_SPL.encode(),
        "test-setid",
        listing_title="PANOXYL (BENZOYL PEROXIDE) CREAM [CROWN LABORATORIES]",
    )
    assert products[0].brand == "Panoxyl"
    assert products[0].name == "Panoxyl Acne Foaming Wash"


def test_parse_spl_falls_back_to_listing_when_xml_title_is_just_the_brand():
    xml = """<?xml version="1.0"?>
<document xmlns="urn:hl7-org:v3">
  <title>PanOxyl ®</title>
  <manufacturedProduct>
    <manufacturedMedicine>
      <name>PanOxyl ®</name>
      <code code="0316-0143" codeSystem="2.16.840.1.113883.6.69"/>
      <ingredient classCode="ACTIB">
        <ingredientSubstance><name>ADAPALENE</name></ingredientSubstance>
      </ingredient>
      <ingredient classCode="IACT">
        <ingredientSubstance><name>WATER</name></ingredientSubstance>
      </ingredient>
    </manufacturedMedicine>
  </manufacturedProduct>
</document>
"""
    products = parse_spl(
        xml.encode(),
        "setid-gel",
        listing_title="PANOXYL (ADAPALENE) GEL [CROWN LABORATORIES]",
    )
    assert products[0].brand == "Panoxyl"
    assert products[0].name == "Panoxyl Gel"
