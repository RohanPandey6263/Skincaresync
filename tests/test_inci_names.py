from skincaresync.inci_names import display_inci_name


def test_display_preserves_already_mixed_case():
    assert display_inci_name("Ascorbic Acid") == "Ascorbic Acid"


def test_display_title_cases_upper_inci_and_keeps_chemical_tokens():
    assert display_inci_name("PEG-40 HYDROGENATED CASTOR OIL") == "PEG-40 Hydrogenated Castor Oil"
    assert display_inci_name("SODIUM C14-16 OLEFIN SULFONATE") == "Sodium C14-16 Olefin Sulfonate"
    assert display_inci_name("EDTA") == "EDTA"
