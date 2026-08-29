from scripts.import_ingredient_catalog import build_records


def test_build_records_keeps_translations_as_alt_names_and_merges_duplicates():
    taxonomy = {
        "en:ascorbic-acid": {
            "name": {"en": "ASCORBIC ACID", "es": "Ácido ascórbico", "fr": "Acide ascorbique"},
            "inci_functions": {"en": "en:antioxidant, en:buffering"},
            "inci_description": {"en": "Vitamin C"},
            "cas": {"en": "50-81-7"},
            "cosing": {"en": "74328"},
        },
        "en:ascorbic-acid-alias": {
            "name": {"en": "L-ASCORBIC ACID"},
            "inci_functions": {"en": "en:antioxidant"},
            "inn-name": {"en": "ascorbic acid"},
        },
    }

    records, duplicates = build_records(taxonomy)

    assert duplicates == 0
    names = {record["inci_name"] for record in records}
    assert "ASCORBIC ACID" in names
    ascorbic = next(record for record in records if record["inci_name"] == "ASCORBIC ACID")
    assert "Ácido ascórbico" in ascorbic["alt_names"]
    assert "Acide ascorbique" in ascorbic["alt_names"]
    assert ascorbic["functions"] == ["antioxidant", "buffering"]
    assert ascorbic["cas_number"] == "50-81-7"
    assert ascorbic["cosing_ref"] == "74328"


def test_build_records_merges_when_normalized_names_collide():
    taxonomy = {
        "en:retinol": {
            "name": {"en": "RETINOL"},
            "inci_functions": {"en": "en:skin-conditioning"},
            "cas": {"en": "68-26-8"},
        },
        "en:retinol-dup": {
            "name": {"en": "Retinol"},
            "inci_functions": {"en": "en:skin-conditioning"},
            "inci_description": {"en": "Vitamin A"},
        },
    }

    records, duplicates = build_records(taxonomy)
    assert duplicates == 1
    assert len(records) == 1
    assert records[0]["description"] == "Vitamin A"
    assert records[0]["cas_number"] == "68-26-8"
