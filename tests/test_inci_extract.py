from skincaresync.brand_catalog import (
    CATALOG_BRANDS,
    SHOPIFY_STORES,
    ShopifyStore,
    encode_http_url,
    should_skip_listing,
    vitamin_c_brands,
)
from skincaresync.inci_extract import extract_inci_from_html, looks_like_inci


COSRX_HTML = """
<details class="cb-collapse">
  <summary class="cb-summary"><span>Ingredient List</span></summary>
  <div class="cb-body">
    Snail Secretion Filtrate, Betaine, Butylene Glycol, 1,2-Hexanediol,
    Sodium Polyacrylate, Phenoxyethanol, Sodium Hyaluronate, Allantoin,
    Ethyl Hexanediol, Carbomer, Panthenol, Arginine, Aqua/Water
  </div>
</details>
"""

MINIMALIST_HTML = """
<span class="text-weight--bold">All Ingredients</span>
<span class="metafield-multi_line_text_field">Water/Aqua, Methylpropanediol, Propylene Glycol, Dimethyl Isosorbide, Glycolic Acid, Ethoxydiglycol, Salicylic Acid, Glycerin, Sodium Hydroxide, Pentylene Glycol, Phenoxyethanol, Ethylhexylglycerin</span>
"""

NUMBUZIN_HTML = r"""
<script>
{"ingredients":"Water, Butylene Glycol, Niacinamide, Panthenol, Tranexamic Acid, 1,2-Hexanediol, Glycerin, 3-O-Ethyl Ascorbic Acid, Ascorbic Acid"}
{"ingredients":"gid:\/\/shopify\/Metaobject\/356819632325"}
</script>
"""

KEY_INGREDIENTS_HTML = """
{"@type":"PropertyValue","name":"Ingredients","value":"Hyaluronic Acid, Matrixyl 3000, Aloe Barbadensis, Lavender Extract"}
"""

ORDINARY_HTML = """
<div class="title">Ingredients</div>
<p class="ingredients-flyout-content" data-original-ingredients="Aqua (Water), Niacinamide, Pentylene Glycol, Zinc PCA, Dimethyl Isosorbide, Tamarindus Indica Seed Gum, Xanthan Gum, Isoceteth-20, Ethoxydiglycol, Phenoxyethanol, Chlorphenesin.">
"""

TIMELESS_HTML = """
<strong>Full Ingredient List:</strong> Water, Ethoxydiglycol, L-Ascorbic Acid, Propylene Glycol, Alpha Tocopherol, Polysorbate 80, Panthenol, Ferulic Acid, Sodium Hyaluronate, Benzylalcohol, Dehydroacetic Acid.
<br/><br/>
<strong>Price:</strong> $27.90. Please consult your healthcare provider if needed.
"""


def test_extracts_cosrx_ingredient_list_details():
    inci = extract_inci_from_html(COSRX_HTML)
    assert inci is not None
    assert "Snail Secretion Filtrate" in inci
    assert inci.endswith("Aqua") or "Aqua" in inci


def test_extracts_minimalist_metafield():
    inci = extract_inci_from_html(MINIMALIST_HTML)
    assert inci is not None
    assert inci.startswith("Aqua")
    assert "Salicylic Acid" in inci


def test_extracts_json_ingredients_and_ignores_metaobject_ids():
    inci = extract_inci_from_html(NUMBUZIN_HTML)
    assert inci is not None
    assert "Niacinamide" in inci
    assert "gid://" not in inci


def test_rejects_short_key_ingredient_callouts():
    assert extract_inci_from_html(KEY_INGREDIENTS_HTML) is None
    assert not looks_like_inci("Hyaluronic Acid, Matrixyl 3000, Aloe, Lavender")


def test_extracts_data_original_ingredients_attribute():
    inci = extract_inci_from_html(ORDINARY_HTML)
    assert inci is not None
    assert inci.startswith("Aqua")
    assert "Niacinamide" in inci


def test_extracts_full_ingredient_list_before_adjacent_prose():
    inci = extract_inci_from_html(TIMELESS_HTML)
    assert inci is not None
    assert "Ascorbic Acid" in inci
    assert "healthcare" not in inci.lower()


def test_strips_transparency_disclaimer_after_inci():
    html = (
        '<div class="metafield-rich_text_field"><p>'
        "Aqua/Water/Eau, Cocamidopropyl Hydroxysultaine, Sodium Cocoyl Isethionate, "
        "Glycerin, Phenoxyethanol. Learn more about all our ingredients. "
        "Our ingredient lists shown here may vary slightly from packaging."
        "</p></div>"
    )
    inci = extract_inci_from_html(html)
    assert inci is not None
    assert "Cocamidopropyl Hydroxysultaine" in inci
    assert "Learn more" not in inci
    assert "may vary" not in inci.lower()


def test_rejects_marketing_copy():
    assert not looks_like_inci("Add to cart. Free shipping on this hydrating serum for your skin.")


def test_encode_http_url_percent_encodes_emoji_in_path():
    encoded = encode_http_url("https://beminimalist.co/products/gift-\U0001f381-pouch")
    assert "\U0001f381" not in encoded
    assert encoded.startswith("https://beminimalist.co/products/gift-")
    assert "%F0%9F%8E%81" in encoded


def test_shopify_stores_cover_vitamin_c_brands_that_have_them():
    store_brands = {store.brand for store in SHOPIFY_STORES}
    seeded = set(vitamin_c_brands())
    for brand in (
        "COSRX",
        "Minimalist",
        "Naturium",
        "Klairs",
        "Innisfree",
        "MISSHA",
        "JUMISO",
        "Timeless",
        "Mad Hippie",
        "By Wishtrend",
        "Beauty of Joseon",
        "Paula's Choice",
        "numbuzin",
    ):
        assert brand in seeded
        assert brand in store_brands
    assert "medicube" in store_brands
    for brand in (
        "Anua",
        "Round Lab",
        "SKIN1004",
        "Haruharu Wonder",
        "Torriden",
        "mixsoon",
        "Glow Recipe",
        "Rhode",
        "Bubble",
        "EltaMD",
        "Fenty Skin",
        "Cocokind",
    ):
        assert brand in store_brands
    assert "Youth to the People" in CATALOG_BRANDS


def test_skips_shopify_subscription_skus():
    assert should_skip_listing(
        {
            "title": "[Subscr.] PDRN Pink Peptide Serum",
            "handle": "subscr-pdrn-pink-peptide-serum",
        }
    )
    assert not should_skip_listing(
        {
            "title": "PDRN Pink Peptide Serum",
            "handle": "pdrn-pink-peptide-serum",
        }
    )


def test_skips_kits_samples_and_non_skin_vendors():
    assert should_skip_listing({"title": "Watermelon Glow Set", "handle": "watermelon-glow-set"})
    assert should_skip_listing(
        {"title": "UFO Face Oil (100% off)", "handle": "ufo-acne-treatment-face-oil-sca_clone_freegift"}
    )
    assert should_skip_listing({"title": "Bean Essence 1 + 1", "handle": "bean-essence-1-1"})
    assert should_skip_listing({"title": "Collagen Powder Lime Flavor", "handle": "collagen-powder"})
    assert should_skip_listing({"title": "Daily Smoothing Body Oil", "handle": "body-oil"})
    fenty = ShopifyStore(
        "Fenty Skin",
        "https://www.fentybeauty.com",
        keep_vendors=("Fenty Skin",),
    )
    assert should_skip_listing(
        {"title": "Gloss Bomb", "handle": "gloss-bomb", "vendor": "Fenty Beauty"},
        fenty,
    )
    assert not should_skip_listing(
        {"title": "Fat Water", "handle": "fat-water", "vendor": "Fenty Skin"},
        fenty,
    )


def test_extracts_inactive_ingredients_block():
    html = """
    <div>View full ingredient list</div>
    Active ingredient: Salicylic acid 1%
    Inactive ingredients:<br>
    water, propanediol, cocamidopropyl betaine, glycerin, 1,2-hexanediol,
    phenoxyethanol, caprylyl glycol, ethylhexylglycerin
    """
    inci = extract_inci_from_html(html)
    assert inci is not None
    assert inci.lower().startswith("aqua") or "Aqua" in inci or "water" in inci.lower()
    assert "Cocamidopropyl Betaine" in inci or "cocamidopropyl betaine" in inci.lower()
    assert "Salicylic acid 1%" not in inci


def test_extracts_full_il_and_percent_table():
    html = """
    <p><strong>Full IL:&nbsp;</strong></p>
    <p>water/eau, glycerin, propanediol, coco-caprylate/caprate, caprylic/capric triglyceride,
    sodium acrylates copolymer, pentylene glycol, phenoxyethanol</p>
    """
    inci = extract_inci_from_html(html)
    assert inci is not None
    assert "glycerin" in inci.lower()
    assert "propanediol" in inci.lower()

    percent = """
    Water - 76.8%<br>Propanediol - 10%<br>Glycerin - 5%<br>Niacinamide - 4%<br>
    1,2-Hexanediol - 2%<br>Phenoxyethanol - 0.5%
    """
    inci = extract_inci_from_html(percent)
    assert inci is not None
    assert "Niacinamide" in inci
    assert "%" not in inci

    percent = """
    Water - 76.8%<br>Propanediol - 10%<br>Glycerin - 5%<br>Niacinamide - 4%<br>
    1,2-Hexanediol - 2%<br>Phenoxyethanol - 0.5%
    """
    inci = extract_inci_from_html(percent)
    assert inci is not None
    assert "Niacinamide" in inci
    assert "%" not in inci


def test_extracts_ingredients_content_class():
    html = """
    <div class="Highlights-ingredients-content">
    water (aqua) (eau), glycerin, caprylic/capric triglyceride, panthenol,
    tocopherol, phenoxyethanol, ethylhexylglycerin, sodium hyaluronate
    </div>
    """
    inci = extract_inci_from_html(html)
    assert inci is not None
    assert "panthenol" in inci.lower()
    assert "hyaluronate" in inci.lower()


def test_rejects_ingredient_dictionary_copy():
    blob = (
        "Butylene Glycol Rating: Good Categories: Humectant, Texture-Enhancer "
        "Humectant (hydration booster), texture/penetration enhancer, and formulary solvent."
    )
    assert not looks_like_inci(blob)
    assert extract_inci_from_html(f"<p>{blob}</p>") is None
    decoded = (
        "Decoded Carrier Water Solvent Butylene Glycol, Propanediol, "
        "1,2-Hexanediol Humectant Glycerin, Betaine Skin-Conditioner Sorbitol"
    )
    assert not looks_like_inci(decoded)
    blurb = (
        "ECTOIN — an amino acid derivative that binds water molecules to the skin "
        "to keep it hydrated, even in dry and hot environments, glycerin boost"
    )
    assert not looks_like_inci(blurb)
    assert extract_inci_from_html(f"<p>{blurb}</p>") is None
