from skincaresync.engine import SkinProfileInput, effective_severity


def test_sensitive_skin_modifier_overrides_base_severity():
    interaction = {
        "interaction_type": "caution",
        "severity": "medium",
        "skin_type_modifier": {"sensitive": "high"},
    }
    skin_profile = SkinProfileInput(skin_type="sensitive", concerns=[])

    severity, modified = effective_severity(interaction, skin_profile)

    assert severity == "high"
    assert modified is True


def test_rosacea_escalates_conflicts_to_high():
    interaction = {
        "interaction_type": "conflict",
        "severity": "medium",
        "skin_type_modifier": {},
    }
    skin_profile = SkinProfileInput(skin_type="normal", concerns=["rosacea"])

    severity, modified = effective_severity(interaction, skin_profile)

    assert severity == "high"
    assert modified is True

