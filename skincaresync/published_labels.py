"""Brand-published cosmetic ingredient lists that Open Beauty Facts lacks.

These are transcribed from official brand pages or authorized retailer pages
that print the full INCI. We do not invent formulas. Packaging remains the
source of truth if a brand reformulates.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from .inci_names import display_inci_name
from .parser import tokenize_inci

VITAMIN_C_MARKERS = (
    "ascorbic acid",
    "ascorbyl",
    "ascorbate",
    "ethyl ascorbic",
    "tetrahexyldecyl",
)

FAMILY_ALIASES = {
    "vitamin-c": (
        "vitamin c",
        "vit c",
        "serum",
        "ascorbic acid",
        "ascorbyl",
    ),
}

AQUA_ALIASES = {
    "water",
    "aqua",
    "eau",
    "aqua/water",
    "aqua/water/eau",
    "aqua / water / eau",
    "deionized water",
    "distilled water",
    "water deionized",
}

FIL_RE = re.compile(r"\(F\.I\.L\.[^)]+\)", re.IGNORECASE)
FIL_BARE_RE = re.compile(r"F\.I\.L\.\s*\S+", re.IGNORECASE)
CODE_PREFIX_RE = re.compile(r"^\s*\d{5,}\s+\d{1,3}\s*[-–]?\s*", re.IGNORECASE)


@dataclass(frozen=True)
class PublishedProduct:
    family: str
    brand: str
    name: str
    raw_ingredient_list: str
    product_url: str
    extra_aliases: tuple[str, ...] = ()


def normalize_published_inci(raw: str) -> str:
    text = (raw or "").replace("•", ",").replace("·", ",").replace(";", ",").replace("，", ",")
    text = FIL_RE.sub("", text)
    text = FIL_BARE_RE.sub("", text)
    text = CODE_PREFIX_RE.sub("", text)
    text = re.sub(r"\bingredients?\b\s*:?\s*,?\s*", "", text, flags=re.IGNORECASE)
    # Keep 1,2-Hexanediol as one token through the comma splitter.
    text = re.sub(r"(?<=\d),(?=\d)", "@@COMMA@@", text)
    tokens = tokenize_inci(text)
    cleaned: list[str] = []
    seen: set[str] = set()
    for token in tokens:
        name = _clean_token(token.replace("@@COMMA@@", ","))
        if not name:
            continue
        key = name.casefold()
        if key in seen:
            continue
        seen.add(key)
        cleaned.append(name)
    return ", ".join(cleaned)


def _clean_token(token: str) -> str:
    token = re.sub(r"\s+", " ", token).strip(" .")
    token = re.sub(r"\(\s*[\d.]+\s*%\s*\)", "", token).strip()
    token = re.sub(r"\[\s*[\d.]+\s*%\s*\]", "", token).strip()
    token = re.sub(r"\[\s*[\d.]+\s*ppm\s*\]", "", token, flags=re.IGNORECASE).strip()
    token = token.replace("3-0-Ethyl", "3-O-Ethyl").replace("3-0-ethyl", "3-O-Ethyl")
    token = re.sub(r"\(\s*\)", "", token).strip()
    bare = re.sub(r"\([^)]*\)", "", token)
    collapsed = re.sub(r"[\s/]+", " ", bare).strip().lower()
    if collapsed in AQUA_ALIASES:
        return "Aqua"
    aqua_parts = [part for part in re.split(r"[/\s]+", collapsed) if part]
    if aqua_parts and all(part in {"water", "aqua", "eau"} for part in aqua_parts):
        return "Aqua"
    if collapsed in {"l-ascorbic acid", "l ascorbic acid"}:
        return "Ascorbic Acid"
    if collapsed in {"parfum", "fragrance", "parfum fragrance"}:
        return "Parfum"
    if token.isupper():
        formatted = display_inci_name(token)
        if formatted:
            return formatted
    return token


def contains_vitamin_c(inci: str) -> bool:
    low = (inci or "").lower()
    return any(marker in low for marker in VITAMIN_C_MARKERS)


def aliases_for(product: PublishedProduct) -> tuple[str, ...]:
    aliases = [*FAMILY_ALIASES.get(product.family, ()), *product.extra_aliases]
    seen: set[str] = set()
    ordered: list[str] = []
    for alias in aliases:
        key = alias.casefold()
        if key and key not in seen:
            seen.add(key)
            ordered.append(alias)
    return tuple(ordered)


def products_for_family(family: str) -> list[PublishedProduct]:
    return [item for item in PUBLISHED_PRODUCTS if item.family == family]


# Transcribed INCI. Each product_url is the page the list was taken from.
PUBLISHED_PRODUCTS: tuple[PublishedProduct, ...] = (
    PublishedProduct(
        family="vitamin-c",
        brand="SkinCeuticals",
        name="C E Ferulic",
        extra_aliases=("c e ferulic", "ce ferulic", "ferulic"),
        product_url="https://bluemercury.com/products/skinceuticals-c-e-ferulic",
        raw_ingredient_list=(
            "aqua / water / eau, ethoxydiglycol, ascorbic acid, glycerin, "
            "propylene glycol, laureth-23, tocopherol, phenoxyethanol, "
            "sodium hydroxide, ferulic acid, carnosine, panthenol, "
            "sodium hyaluronate, pentylene glycol, taraxacum officinale "
            "rhizome/root extract, maltodextrin, citric acid, "
            "eperua falcata bark extract"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Timeless",
        name="20% Vitamin C + E Ferulic Acid Serum",
        extra_aliases=("ferulic", "20% vitamin c"),
        product_url="https://www.timelessha.com/products/20-vitamin-c-e-ferulic-acid-serum-1-oz",
        raw_ingredient_list=(
            "Water, Ethoxydiglycol, L-Ascorbic Acid, Propylene Glycol, "
            "Alpha Tocopherol, Polysorbate 80, Panthenol, Ferulic Acid, "
            "Sodium Hyaluronate, Benzylalcohol, Dehydroacetic Acid"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="CeraVe",
        name="Skin Renewing Vitamin C Serum",
        extra_aliases=("skin renewing",),
        product_url="https://www.cerave.com/skincare/facial-serums/skin-renewing-vitamin-c-serum",
        raw_ingredient_list=(
            "WATER, ASCORBIC ACID, GLYCERIN, DIMETHICONE, CETEARYL ETHYLHEXANOATE, "
            "ALCOHOL DENAT., SODIUM HYDROXIDE, AMMONIUM POLYACRYLOYLDIMETHYL TAURATE, "
            "PANTHENOL, CERAMIDE NP, CERAMIDE AP, CERAMIDE EOP, CARBOMER, "
            "CETEARYL ALCOHOL, BEHENTRIMONIUM METHOSULFATE, SODIUM HYALURONATE, "
            "SODIUM LAUROYL LACTYLATE, CHOLESTEROL, PHENOXYETHANOL, "
            "TOCOPHERYL ACETATE, DISODIUM EDTA, ISOPROPYL MYRISTATE, "
            "CAPRYLYL GLYCOL, XANTHAN GUM, PHYTOSPHINGOSINE, ETHYLHEXYLGLYCERIN"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Paula's Choice",
        name="C15 Super Booster",
        extra_aliases=("c15", "booster"),
        product_url="https://www.paulaschoice.com.au/products/c15-super-booster",
        raw_ingredient_list=(
            "Water/Aqua/Eau, Ascorbic Acid, Glycerin, Ethoxydiglycol, "
            "PPG-26-Buteth-26, Mannitol, Tridecapeptide-1, Palmitoyl Tripeptide-5, "
            "Ergothioneine, Sodium Hyaluronate, Pentylene Glycol, "
            "PEG-40 Hydrogenated Castor Oil, Bisabolol, Sodium Gluconate, "
            "Decylene Glycol, Ferulic Acid, Oryza Sativa (Rice) Bran Extract, "
            "Tocopherol, Polyacrylate Crosspolymer-6, 1,2-Hexanediol, Panthenol, "
            "Sodium Phytate, Sodium Hydroxide, Citric Acid, Phenoxyethanol"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="La Roche-Posay",
        name="Pure Vitamin C12 Serum",
        extra_aliases=("c12", "c10", "pure vitamin c"),
        product_url="https://www.laroche-posay.co.uk/en_GB/pure-vitamin-c10-serum-for-sensitive-skin-30ml/LRP_114.html",
        raw_ingredient_list=(
            "AQUA / WATER / EAU, ASCORBIC ACID, DIMETHICONE, GLYCERIN, "
            "ALCOHOL DENAT., POTASSIUM HYDROXIDE, POLYSILICONE-11, SILICA, "
            "PENTAERYTHRITYL TETRAETHYLHEXANOATE, PEG-20 METHYL GLUCOSE "
            "SESQUISTEARATE, SODIUM HYALURONATE, ADENOSINE, POLOXAMER 338, "
            "AMMONIUM POLYACRYLOYLDIMETHYL TAURATE, HYDROLYZED HYALURONIC ACID, "
            "CAPRYLIC/CAPRIC TRIGLYCERIDE, CAPRYLYL GLYCOL, CITRIC ACID, "
            "LAURETH-7, TRISODIUM ETHYLENEDIAMINE DISUCCINATE, "
            "BIS-PEG/PPG-16/16 PEG/PPG-16/16 DIMETHICONE, "
            "ACETYL DIPEPTIDE-1 CETYL ESTER, XANTHAN GUM, PENTYLENE GLYCOL, "
            "POLYACRYLAMIDE, C13-14 ISOALKANE, TOCOPHEROL, "
            "PENTAERYTHRITYL TETRA-DI-T-BUTYL HYDROXYHYDROCINNAMATE, "
            "SALICYLIC ACID, PARFUM / FRAGRANCE"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="The Ordinary",
        name="Ascorbyl Glucoside Solution 12%",
        extra_aliases=("ascorbyl glucoside", "12%"),
        product_url="https://theordinary.com/en-my/ascorbyl-glucoside-solution-12-vitamin-c-100405.html",
        raw_ingredient_list=(
            "Aqua (Water), Ascorbyl Glucoside, Propanediol, Aminomethyl Propanol, "
            "Triethanolamine, Isoceteth-20, Xanthan Gum, Dimethyl Isosorbide, "
            "Ethoxydiglycol, Trisodium Ethylenediamine Disuccinate, "
            "1,2-Hexanediol, Caprylyl Glycol"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="The Ordinary",
        name="Vitamin C Suspension 23% + HA Spheres 2%",
        extra_aliases=("suspension", "23%"),
        product_url="https://theordinary.com/en-ws/vitamin-c-suspension-23-ha-spheres-2-vitamin-c-100451.html",
        raw_ingredient_list=(
            "Ascorbic Acid, Squalane, Isodecyl Neopentanoate, Isononyl Isononanoate, "
            "Coconut Alkanes, Ethylene/Propylene/Styrene Copolymer, Ethylhexyl Palmitate, "
            "Silica Dimethyl Silylate, Sodium Hyaluronate, Glucomannan, "
            "Coco-Caprylate/Caprate, Butylene/Ethylene/Styrene Copolymer, "
            "Acrylates/Ethylhexyl Acrylate Crosspolymer, Trihydroxystearin, Bht"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="The Ordinary",
        name="Ascorbyl Tetraisopalmitate Solution 20% in Vitamin F",
        extra_aliases=("tetraisopalmitate", "vitamin f", "tetrahexyldecyl"),
        product_url="https://theordinary.com/en-au/ascorbyl-tetraisopalmitate-solution-20-in-vitamin-f-vitamin-c-100406.html",
        raw_ingredient_list=(
            "Coconut Alkanes, Tetrahexyldecyl Ascorbate, Ethyl Linoleate, "
            "Coco-Caprylate/Caprate, Simmondsia Chinensis (Jojoba) Seed Oil, "
            "Solanum Lycopersicum (Tomato) Fruit Extract, Squalane"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="COSRX",
        name="Advanced The Vitamin C 23 Serum",
        extra_aliases=("vitamin c 23", "23 serum"),
        product_url="https://www.cosrx.com/products/advanced-the-vitamin-c-23-serum-%eb%b2%88%eb%93%a4",
        raw_ingredient_list=(
            "Aqua/Water, Ascorbic Acid(23%), Butylene Glycol, Dimethicone, Panthenol, "
            "3-O-Ethyl Ascorbic Acid, Squalane, Sodium Hydroxide, Caffeine, "
            "Sodium Hyaluronate, Sodium Metaphosphate, Adenosine, Acetyl Glucosamine, "
            "Gardenia Florida Fruit Extract, Allantoin, Dextrin, Tocotrienols, "
            "Tocopherol, Elaeis Guineensis (Palm) Oil, Arginine, Niacinamide, "
            "Pentylene Glycol, Glutathione, Helianthus Annuus (Sunflower) Seed Oil, "
            "Methyl Trimethicone, Carthamus Tinctorius (Safflower) Seed Oil, "
            "Camellia Japonica Seed Oil, Daucus Carota Sativa (Carrot) Root Extract, "
            "Glycyrrhiza Glabra (Licorice) Root Extract, Beta-Carotene"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Naturium",
        name="Vitamin C Complex Serum",
        extra_aliases=("complex",),
        product_url="https://naturium.com/products/vitamin-c-complex-serum",
        raw_ingredient_list=(
            "Water (Aqua), Glycerin, Propanediol, Sodium Ascorbyl Phosphate, "
            "Ascorbic Acid, Glutathione, Ananas Sativus (Pineapple) Fruit Extract, "
            "Carica Papaya (Papaya) Fruit Extract, Mangifera Indica (Mango) Fruit Extract, "
            "Terminalia Ferdinandiana Fruit Extract, Pleiogynium Timoriense Fruit Extract, "
            "Podocarpus Elatus Fruit Extract, Aloe Barbadensis Leaf Juice, "
            "Sodium Hyaluronate, Carbomer, Tocopheryl Acetate, Phenoxyethanol, "
            "Caprylyl Glycol, Citric Acid, Hydroxyethylcellulose, Sodium Hydroxide, "
            "Beta-Glucan, Potassium Sorbate, Hexylene Glycol, Sorbitol, Xanthan Gum, "
            "Algin, Benzoic Acid, Sorbic Acid, 1,2-Hexanediol, Sodium Benzoate, "
            "Disodium Phosphate, Gold, Polysorbate 60, Sodium Phosphate"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Mad Hippie",
        name="Vitamin C Serum",
        extra_aliases=("sap",),
        product_url="https://madhippie.com/blogs/naked-ingredients/vitamin-c-sap-stability",
        raw_ingredient_list=(
            "Deionized Water (Aqua), Sodium Ascorbyl Phosphate, Alkyl Benzoate, "
            "Glycerin, Sodium Levulinate, Sodium Anisate, Salvia Sclarea, "
            "Citrus Grandis, Hyaluronic Acid, Amorphophallus Konjac Root Powder, "
            "Aloe Barbadensis Leaf, Tocotrienol, Ferulic Acid, "
            "Chamomilla Recutita Flower Extract, Sodium Phytate, Xanthan Gum, "
            "Hydroxyethyl Cellulose"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Garnier",
        name="Vitamin C Brightening Serum",
        extra_aliases=("melasyl", "brightening"),
        product_url="https://www.garnier.co.uk/our-brands/skin-care/vitamin-c/garnier-vitamin-c-brightening-serum",
        raw_ingredient_list=(
            "AQUA / WATER, GLYCERIN, ALCOHOL DENAT., DIPROPYLENE GLYCOL, "
            "BUTYLENE GLYCOL, NIACINAMIDE, PEG/PPG/POLYBUTYLENE GLYCOL-8/5/3 GLYCERIN, "
            "HYDROXYETHYLPIPERAZINE ETHANE SULFONIC ACID, ISONONYL ISONONANOATE, "
            "ASCORBYL GLUCOSIDE, CITRUS LIMON FRUIT EXTRACT, POTASSIUM HYDROXIDE, "
            "2-MERCAPTONICOTINOYL GLYCINE, SODIUM HYALURONATE, SODIUM THIOSULFATE, "
            "SILICA, ADENOSINE, PHENYLETHYL RESORCINOL, "
            "AMMONIUM POLYACRYLOYLDIMETHYL TAURATE, HYDROGENATED LECITHIN, "
            "CAPRYLYL GLYCOL, TETRASODIUM GLUTAMATE DIACETATE, "
            "TRISODIUM ETHYLENEDIAMINE DISUCCINATE, XANTHAN GUM, TOCOPHERYL ACETATE, "
            "SALICYLIC ACID, CHLORPHENESIN, CI 15510, CI 19140, LINALOOL, GERANIOL, "
            "LIMONENE, PARFUM / FRAGRANCE"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Garnier",
        name="Vitamin C Brightening Night Serum",
        extra_aliases=("night serum", "10% vitamin c"),
        product_url="https://www.garnier.co.uk/our-brands/skin-care/vitamin-c/anti-dark-spot-night-serum",
        raw_ingredient_list=(
            "AQUA / WATER, ASCORBIC ACID, PENTYLENE GLYCOL, GLYCERIN, "
            "SODIUM HYDROXIDE, HYDROXYACETOPHENONE, SALICYLIC ACID, CAPRYLYL GLYCOL, "
            "CAPRYLYL/CAPRYL GLUCOSIDE, POLYQUATERNIUM-67, ADENOSINE, "
            "TRISODIUM ETHYLENEDIAMINE DISUCCINATE, SODIUM HYALURONATE, "
            "LINALOOL, LIMONENE, GERANIOL, PARFUM / FRAGRANCE"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Neutrogena",
        name="Rapid Tone Repair 20% Vitamin C Serum Capsules",
        extra_aliases=("rapid tone repair", "capsules", "20% vitamin c"),
        product_url="https://www.neutrogena.ca/face/moisturizer-hydration-serum/neutrogena-rapid-tone-repair-20-pct-vitaminc-serum",
        raw_ingredient_list=(
            "Dimethicone, Ascorbic Acid, Trisiloxane, Dimethiconol, "
            "Silica Dimethyl Silylate, Dimethicone/Vinyltrimethylsiloxysilicate "
            "Crosspolymer, Tocopheryl Acetate, Caprylic/Capric Triglyceride, "
            "Diethylhexyl Syringylidenemalonate, Rubus Idaeus (Raspberry) Leaf Extract"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Vichy",
        name="LiftActiv 16% Vitamin C Brightening Serum",
        extra_aliases=("liftactiv", "16%"),
        product_url="https://www.vichy.com.au/all-products/skincare/face-serums/liftactiv-vitamin-c-serum",
        raw_ingredient_list=(
            "AQUA / WATER / EAU, ASCORBIC ACID, GLYCERIN, SODIUM HYDROXIDE, "
            "PENTYLENE GLYCOL, LAURETH-23, HAEMATOCOCCUS PLUVIALIS EXTRACT, "
            "CARNOSINE, NEOHESPERIDIN DIHYDROCHALCONE, SODIUM HYALURONATE, "
            "TRISODIUM ETHYLENEDIAMINE DISUCCINATE, TOCOPHEROL, "
            "DIPOTASSIUM GLYCYRRHIZATE, CAPRYLIC/CAPRIC TRIGLYCERIDE, "
            "CAPRYLYL GLYCOL, CARRAGEENAN, PHENOXYETHANOL"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Minimalist",
        name="Vitamin C + E + Ferulic 16% Face Serum",
        extra_aliases=("16%", "ethyl ascorbic", "ferulic"),
        product_url="https://beminimalist.co/products/vitamin-c-e-ferulic-16",
        raw_ingredient_list=(
            "Water/Aqua, 3-O-Ethyl Ascorbic Acid, Propanediol, Ethoxydiglycol, "
            "1,2-Hexanediol, Butylene Glycol, Dimethyl Isosorbide, "
            "Argan Oil Glycereth-8 Esters, Sodium Hyaluronate, Panthenol, "
            "Ferulic Acid, Phenoxyethanol, Sodium Gluconate, Fullerenes, "
            "Tocopheryl Acetate, Pentylene Glycol, Citric Acid, Sodium Citrate, "
            "Ethylhexylglycerin, PVP, Trisodium Ethylenediamine Disuccinate"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Minimalist",
        name="Vitamin C 10% Face Serum",
        extra_aliases=("10%", "ethyl ascorbic", "acetyl glucosamine"),
        product_url="https://beminimalist.co/products/vitamin-c-ethyl-ascorbic-acid-10-acetyl-glucosamine-1",
        raw_ingredient_list=(
            "Centella Asiatica Leaf Extract, 3-O-Ethyl Ascorbic Acid, "
            "Dimethyl Isosorbide, Ethoxydiglycol, Glycerin, Sodium Gluconate, "
            "Acetyl Glucosamine, Gluconolactone, Citric Acid, Pentylene Glycol, "
            "Sodium Hyaluronate, Pullulan, Hydroxyethylcellulose, "
            "Hydrolyzed Sodium Hyaluronate, Xanthan Gum, Sclerotium Gum, "
            "Phenoxyethanol, Ethylhexylglycerin, Lecithin, PEG/PPG-17/6 Copolymer, "
            "Trisodium Ethylenediamine Disuccinate, Sodium Citrate"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Klairs",
        name="Freshly Juiced Vitamin Drop",
        extra_aliases=("dear klairs", "vitamin drop", "freshly juiced"),
        product_url="https://www.klairs.com/products/freshly-juiced-vitamin-drop",
        raw_ingredient_list=(
            "Aqua (Water), Propylene Glycol, Ascorbic Acid, Hydroxyethylcellulose, "
            "Citrus Junos Fruit Extract, Centella Asiatica Extract, Polysorbate 60, "
            "Illicium Verum (Anise) Fruit Extract, Chaenomeles Sinensis Fruit Extract, "
            "Paeonia Suffruticosa Root Extract, Brassica Oleracea Italica (Broccoli) Extract, "
            "Nelumbium Speciosum Flower Extract, Citrus Paradisi (Grapefruit) Fruit Extract, "
            "Scutellaria Baicalensis Root Extract, Butylene Glycol, Glycerin, "
            "Citrus Aurantium Dulcis (Orange) Oil, 1,2-Hexanediol, "
            "Sodium Acrylate/Sodium Acryloyldimethyl Taurate Copolymer, Isohexadecane, "
            "Disodium EDTA, Lavandula Angustifolia (Lavender) Oil, "
            "Camellia Sinensis Callus Culture Extract, Polysorbate 80, Disodium Phosphate, "
            "Sorbitan Oleate, Chrysanthellum Indicum Extract, Asarum Sieboldii Root Extract, "
            "Quercus Mongolica Leaf Extract, Persicaria Hydropiper Extract, "
            "Larix Europaea Wood Extract, Magnolia Obovata Bark Extract, "
            "Rheum Palmatum Root Extract, Corydalis Turtschaninovii Root Extract, "
            "Coptis Chinensis Root Extract, Sodium Phosphate, Lysine HCl, "
            "Sodium Ascorbyl Phosphate, Acetyl Methionine, Theanine, Proline, Lecithin, "
            "Acetyl Glutamine, Bacillus/Folic Acid/Soybean Ferment Extract, "
            "Sodium Hyaluronate, sh-Oligopeptide-1, sh-Oligopeptide-2, sh-Polypeptide-1, "
            "sh-Polypeptide-11, sh-Polypeptide-9, Caprylyl Glycol, Limonene"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="COSRX",
        name="The Vitamin C 13 Serum",
        extra_aliases=("vitamin c 13", "13 serum"),
        product_url="https://www.cosrx.com/products/the-vitamin-c-13-serum",
        raw_ingredient_list=(
            "Water, Ascorbic Acid(13%), Butylene Glycol, Dipropylene Glycol, "
            "Tromethamine, 3-0-Ethyl Ascorbic Acid, Panthenol, Acetyl Glucosamine, "
            "Caffeine, Sodium Hyaluronate, Sodium Sulfite, Disodium EDTA, Glutathione, "
            "Adenosine, Gardenia Florida Fruit Extract, Allantoin, Dextrin, Squalane, "
            "Tocotrienols, Tocopherol, Elaeis Guineensis (Palm) Oil, Arginine, "
            "Niacinamide, Pentylene Glycol, Glycyrrhiza Glabra (Licorice) Root Extract"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Isntree",
        name="Hyper Vitamin C 23 Serum",
        extra_aliases=("hyper vitamin c", "23 serum"),
        product_url="https://www.yesstyle.com/en/isntree-hyper-vitamin-c-23-serum-20ml/info.html/pid.1122107009",
        raw_ingredient_list=(
            "Water, Ascorbic Acid(23%), Propanediol, Betaine, 1,2-Hexanediol, "
            "Polyglycerin-3, Tromethamine, Ethyl Ascorbyl Ether, Hydroxyethyl Urea, "
            "Betula Platyphylla Japonica Juice, Ethylhexylglycerin, Adenosine, "
            "Disodium EDTA, Panthenol, Gardenia Florida Fruit Extract, Dextrin, Tocopherol"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="By Wishtrend",
        name="Pure Vitamin C 21.5% Advanced Serum",
        extra_aliases=("wishtrend", "21.5", "21.5%"),
        product_url="https://www.yesstyle.com/en/by-wishtrend-pure-vitamin-c-21-5-advanced-serum/info.html/pid.1060739471",
        raw_ingredient_list=(
            "Hippophae Rhamnoides Water, Ascorbic Acid, Sodium Lactate, "
            "1,2-Hexanediol, Sodium Hyaluronate, Panthenol, "
            "Cassia Obtusifolia Seed Extract, Allantoin, Xanthan Gum, Ethyl Hexanediol"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Goodal",
        name="Green Tangerine Vita C Dark Spot Care Serum",
        extra_aliases=("green tangerine", "vita c", "dark spot"),
        product_url="https://lewkin.com/en-ph/products/green-tangerine-vita-c-dark-spot-care-serum-40ml",
        raw_ingredient_list=(
            "Citrus Tangerina (Tangerine) Extract (70%), Butylene Glycol, Niacinamide, "
            "Dipropylene Glycol, Methyl Gluceth-20, Water, 1,2-Hexanediol, Glycereth-26, "
            "Arbutin, Chondrus Crispus Extract, Saccharum Officinarum (Sugarcane) Extract, "
            "Hydrolyzed Jojoba Esters, Sodium Hyaluronate, "
            "Citrus Aurantium Bergamia (Bergamot) Fruit Oil, Melia Azadirachta Flower Extract, "
            "Ocimum Sanctum Leaf Extract, Melia Azadirachta Leaf Extract, "
            "Curcuma Longa (Turmeric) Root Extract, Corallina Officinalis Extract, "
            "Lavandula Angustifolia (Lavender) Oil, Citrus Limon (Lemon) Peel Oil, "
            "Cananga Odorata Flower Oil, Citrus Aurantium Dulcis (Orange) Peel Oil, "
            "Eucalyptus Globulus Leaf Extract, Glycyrrhiza Glabra (Licorice) Root Extract, "
            "Anthemis Nobilis Flower Extract, Camellia Sinensis Leaf Extract, "
            "Centella Asiatica Extract, Rosmarinus Officinalis (Rosemary) Leaf Extract, "
            "Polygonum Cuspidatum Root Extract, Centella Asiatica Leaf Extract, "
            "Ammonium Acryloyldimethyltaurate/VP Copolymer, Panthenol, Choleth-24, "
            "Tromethamine, Ethylhexylglycerin, Allantoin, Tocopheryl Acetate, Adenosine, "
            "Sodium Phytate, Ascorbyl Glucoside, Dipotassium Glycyrrhizate, Glycerin, "
            "Madecassoside, Maltodextrin, Saccharide Hydrolysate, Tocopherol, "
            "Asiaticoside, Carbomer, Xanthan Gum, Limonene, Linalool"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Beauty of Joseon",
        name="Light On Serum: Centella + Vita C",
        extra_aliases=("centella vita c", "light on", "boj", "joseon"),
        product_url="https://beautyofjoseon.com/pages/light-on-serum-cpnp-scpn-information",
        raw_ingredient_list=(
            "Aqua, 3-O-Ethyl Ascorbic Acid, Glycerin, Propanediol, 1,2-Hexanediol, "
            "Betaine, Cetyl Ethylhexanoate, Methyl Trimethicone, Panthenol, "
            "Dicaprylyl Carbonate, Cetearyl Alcohol, Centella Asiatica Extract, "
            "Dimethicone/Vinyl Dimethicone Crosspolymer, Cetearyl Olivate, Bisabolol, "
            "Potassium Cetyl Phosphate, Silica, Sorbitan Olivate, Dipropylene Glycol, "
            "Hydroxyethyl Acrylate/Sodium Acryloyldimethyl Taurate Copolymer, "
            "Ammonium Acryloyldimethyltaurate/Beheneth-25 Methacrylate Crosspolymer, "
            "Eclipta Prostrata Leaf Extract, Hydrolyzed Jojoba Esters, Hydroxyacetophenone, "
            "Laminaria Japonica Extract, Ethylhexylglycerin, Xanthan Gum, Alcohol, "
            "Polyglyceryl-10 Myristate, Adenosine, Fructooligosaccharides, Butylene Glycol, "
            "Beta-Glucan, Hydrogenated Lecithin, Sorbitan Isostearate, "
            "Citrus Unshiu Peel Extract, Hydrolyzed Hyaluronic Acid, "
            "Phellodendron Amurense Bark Extract, Tocopherol, Arginine, Carbomer, "
            "Maltodextrin, Hydrolyzed Gardenia Florida Extract, "
            "Brassica Oleracea Acephala Leaf Extract, Ascorbic Acid Polypeptide"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="Innisfree",
        name="Green Tea Enzyme Vitamin C Brightening Serum",
        extra_aliases=("green tea enzyme", "vitamin c brightening"),
        product_url="https://us.innisfree.com/products/green-tea-enzyme-vitamin-c-brightening-serum",
        raw_ingredient_list=(
            "Water / Aqua / Eau, Propanediol, 1,2-Hexanediol, Glycerin, "
            "3-O-Ethyl Ascorbic Acid, Butylene Glycol, Lactobacillus Ferment Lysate, "
            "Squalane, Helianthus Annuus (Sunflower) Seed Oil, Dextrin, "
            "Acrylates/C10-30 Alkyl Acrylate Crosspolymer, Caprylic/Capric Triglyceride, "
            "Tromethamine, Xanthan Gum, Gluconolactone, "
            "Citrus Reticulata (Tangerine) Peel Extract, Panthenol, Niacinamide, "
            "Allantoin, Daucus Carota Sativa (Carrot) Root Extract, Hyaluronic Acid, "
            "Pentylene Glycol, Sodium Metaphosphate, Silica Dimethyl Silylate, "
            "Cyclodextrin, Tocopherol, Ethylhexylglycerin, Madecassoside, "
            "Hydrogenated Poly(C6-20 Olefin), Protease, Ascorbyl Tetraisopalmitate, "
            "Glutathione, Achillea Millefolium Extract, "
            "HDI/Trimethylol Hexyllactone Crosspolymer, Beta-Carotene, Ferulic Acid"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="TIA'M",
        name="My Signature C Source",
        extra_aliases=("c source", "tiam", "20%"),
        product_url="https://lilabeauty.com.au/products/my-signature-c-source-30ml",
        raw_ingredient_list=(
            "Water, Ascorbic Acid (20%), Alcohol, Sodium Lactate, Butylene Glycol, "
            "Glucose, PEG-60 Hydrogenated Castor Oil, 1,2-Hexanediol, Sodium Hyaluronate, "
            "Bis-PEG-18 Methyl Ether Dimethyl Silane, Xanthan Gum, Diethoxyethyl Succinate, "
            "Ammonium Acryloyldimethyltaurate/VP Copolymer, "
            "Carthamus Tinctorius (Safflower) Flower Extract, "
            "Citrus Aurantium Dulcis (Orange) Peel Oil, Glycerin, Zinc PCA, Panthenol, "
            "Niacinamide, t-Butyl Alcohol, Camellia Sinensis (Green Tea) Leaf Extract, "
            "Beta-Glucan, Ubiquinone, Phenoxyethanol"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="TIA'M",
        name="Vita C Source",
        extra_aliases=("vita c source", "tiam", "20%"),
        product_url="https://www.kanvasbeauty.com.au/products/tiam-my-signature-c-source-30ml",
        raw_ingredient_list=(
            "Water (Aqua), Ascorbic Acid (20%), Butylene Glycol, Sodium Lactate, "
            "1,2-Hexanediol, Glucose, PEG-60 Hydrogenated Castor Oil, Sodium Hyaluronate, "
            "Xanthan Gum, Ammonium Acryloyldimethyltaurate/VP Copolymer, Limonene, "
            "Glutathione, Niacinamide, Zinc PCA, Panthenol, Cassia Obtusifolia Seed Extract, "
            "Citrus Aurantium Dulcis (Orange) Peel Oil, Beta-Glucan, Tocopherol, Ferulic Acid"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="SOME BY MI",
        name="Yuja Niacin Anti Blemish Serum",
        extra_aliases=("yuja niacin", "some by mi", "yuja"),
        product_url="https://www.yesstyle.com/en/some-by-mi-yuja-niacin-anti-blemish-serum-2023-renewed-version-50ml/info.html/pid.1123305203",
        raw_ingredient_list=(
            "Citrus Junos Fruit Extract [83%], Niacinamide [10%], "
            "Caprylic/Capric Triglyceride, 1,2-Hexanediol, Hydrogenated Poly(C6-14 Olefin), "
            "Alpha-Bisabolol, Carbomer, Arginine, Brassica Campestris (rapeseed) Seed Oil, "
            "Xanthan Gum, Ethylhexylglycerin, Adenosine, Citrus Junos Peel Oil [293.1 ppm], "
            "Melia Azadirachta Flower Extract, Ocimum Sanctum Leaf Extract, "
            "Glycyrrhiza Glabra (Licorice) Root Extract, Polyglyceryl-3 Diisostearate, "
            "Melia Azadirachta Flower Extract, Distilled Water, Curcuma Longa Root Extract, "
            "Corallina Officinalis Extract, Glycerin, Butylene Glycol, "
            "Althaea Officinalis Root Extract, Oryza Sativa (Rice) Bran Extract, "
            "3-0-Ethyl Ascorbic Acid, Hydrogenated Lecithin, "
            "Ficus Carica(Fig) Fruit Extract, Punica granatum fruit Ext., "
            "Morus Alba Fruit Extract, Ginkgo biloba leaf extract, Tocopherols, "
            "Polyglyceryl-10 Stearate, Panthenol, Sodium Ascorbyl Phosphate, Biotin, "
            "Folic Acid, Pyridoxine, Cyanocobalamin, Linoleic acid, Riboflavin, "
            "Beta-Carotene, Inositol, Thiamine HCL, Disodium EDTA, Limonene, Linalool"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="numbuzin",
        name="No.5+ Glutathione Vitamin Concentrated Serum",
        extra_aliases=("no.5", "no 5", "glutathione", "numbuzin"),
        product_url="https://us.numbuzin.com/products/no-5-vitamin-concentrated-serum",
        raw_ingredient_list=(
            "Water, Butylene Glycol, Niacinamide, Panthenol, Tranexamic Acid, "
            "1,2-Hexanediol, Neopentyl Glycol Dicaprate, Caprylic/Capric Triglyceride, "
            "Sorbitol, Vaccinium Vitis-Idaea Fruit Extract, Behenyl Alcohol, "
            "Pentylene Glycol, Glycerin, Chondrus Crispus Extract, "
            "Butyrospermum Parkii (Shea) Butter, 3-O-Ethyl Ascorbic Acid, "
            "Saccharum Officinarum (Sugarcane) Extract, Carbomer, Alpha-Arbutin, "
            "Bisabolol, Tromethamine, Ethylhexylglycerin, Bifida Ferment Lysate, "
            "Adenosine, Hydrogenated Lecithin, Allantoin, Sodium Hyaluronate, "
            "Xanthan Gum, Glutathione, Disodium EDTA, Melia Azadirachta Flower Extract, "
            "Ocimum Sanctum Leaf Extract, Melia Azadirachta Leaf Extract, Ceramide NP, "
            "Curcuma Longa (Turmeric) Root Extract, Corallina Officinalis Extract, "
            "Beta-Glucan, Dipotassium Glycyrrhizate, Tocopherol, Ascorbic Acid, "
            "Ascorbyl Glucoside, Tocopheryl Acetate, Hydroxypropyl Cyclodextrin, "
            "Ubiquinone, Thioctic Acid, Tremella Fuciformis (Mushroom) Extract, "
            "Potassium Hydroxide"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="MISSHA",
        name="Vita C Plus Spot Correcting Concentrate Ampoule",
        extra_aliases=("vita c plus", "missha"),
        product_url="https://misshaus.com/products/vita-c-plus-spot-correcting-concentrate-ampoule",
        raw_ingredient_list=(
            "Water, Ascorbic Acid, Hippophae Rhamnoides Water, Dipropylene Glycol, "
            "Glycyrrhiza Uralensis (Licorice) Root Extract, Ethoxydiglycol, 1,2-Hexanediol, "
            "Tranexamic Acid, Sodium Citrate, Chlorella Vulgaris Extract, Glucose, "
            "Choleth-24, Butylene Glycol, Fructooligosaccharides, Fructose, Tromethamine, "
            "Caprylyl Glycol, Arbutin, Niacinamide, Methyl Gluceth-10, Ethylhexylglycerin, "
            "Panthenol, Melia Azadirachta Flower Extract, Melia Azadirachta Leaf Extract, "
            "Xanthan Gum, Citrus Aurantium Dulcis (Orange) Peel Oil, "
            "Curcuma Longa (Turmeric) Root Extract, Ocimum Sanctum Leaf Extract, "
            "Sodium Hyaluronate, Citric Acid, Disodium EDTA, "
            "Citrus Grandis (Grapefruit) Peel Oil, Glycerin, Corallina Officinalis Extract, "
            "Eucalyptus Globulus Leaf Oil, Lavandula Angustifolia (Lavender) Oil, Dextrin, "
            "Theobroma Cacao (Cocoa) Seed Extract, Caprylic/Capric Triglyceride, "
            "Hydrolyzed Collagen, Hydrogenated Lecithin, Ceramide NP, Hyaluronic Acid, "
            "Tocopherol, Allantoin, Glyceryl Glucoside, Acetyl Hexapeptide-8, "
            "Hydrolyzed Hyaluronic Acid, PVP, Pentylene Glycol, Palmitoyl Tripeptide-5, "
            "Laurdimonium Hydroxypropyl Hydrolyzed Wheat Protein, Phytosterols, Fullerenes, "
            "3-O-Ethyl Ascorbic Acid, Ascorbyl Glucoside"
        ),
    ),
    PublishedProduct(
        family="vitamin-c",
        brand="JUMISO",
        name="All Day Vitamin Pure C 5.5 Glow Serum",
        extra_aliases=("jumiso", "pure c 5.5", "5.5"),
        product_url="https://jumiso.us/products/jumiso-all-day-vitamin-pure-c-5-5-glow-serum-l-ascorbic-acid-alpha-arbutin-ferulic-acid-tocopherol-targets-dark-spots-dullness-fine-lines",
        raw_ingredient_list=(
            "Aronia Melanocarpa Fruit Extract, Butylene Glycol, Ascorbic Acid, "
            "Ascorbyl Glucoside, 1,2-Hexanediol, Tromethamine, Alpha-Arbutin, "
            "Sodium Hyaluronate, Glycerin, Polyglyceryl-10 Laurate, "
            "Polyglyceryl-10 Myristate, Xanthan Gum, Tocopherol, Ferulic Acid"
        ),
    ),
)
