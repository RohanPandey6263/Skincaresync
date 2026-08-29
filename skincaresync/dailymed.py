"""FDA DailyMed client for OTC / drug product labels.

DailyMed publishes Structured Product Labeling (SPL) as US government work.
Ingredient names come from the official label (active + inactive), not from
scraped brand sites. Cosmetic products that are not drugs will not appear here;
those still come from Open Beauty Facts or the local catalog cache.
"""

from __future__ import annotations

import json
import logging
import xml.etree.ElementTree as ET
import re
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .inci_names import display_inci_name
from .lookup import (
    Deadline,
    MAX_RESPONSE_BYTES,
    ProductLookupResult,
    USER_AGENT,
    normalize_search_text,
)

logger = logging.getLogger(__name__)

DAILYMED_BASE = "https://dailymed.nlm.nih.gov/dailymed/services/v2"

# Each SPL is a separate HTTP round trip. Reading a dozen of them serially was
# the dominant cost of a product search; the shared deadline bounds it, and this
# caps the count even when the budget is generous.
MAX_LABELS_PER_SEARCH = 4

# `xml.etree` expands internal entities, so a document defining nested entities
# ("billion laughs") can exhaust memory. Nothing DailyMed publishes needs a DTD,
# so documents carrying one are refused rather than parsed.
_DOCTYPE_RE = re.compile(rb"<!\s*(DOCTYPE|ENTITY)", re.IGNORECASE)
SPL_NS = {"v3": "urn:hl7-org:v3"}
NDC_CODE_SYSTEM = "2.16.840.1.113883.6.69"

# DailyMed uses USAN / FDA names. Map the common ones onto INCI so the
# compatibility parser can resolve them against the CosIng catalog.
USAN_TO_INCI = {
    "water": "Aqua",
    "benzoyl peroxide": "Benzoyl Peroxide",
    "adapalene": "Adapalene",
    "salicylic acid": "Salicylic Acid",
    "sulfur": "Sulfur",
    "zinc oxide": "Zinc Oxide",
    "titanium dioxide": "Titanium Dioxide",
    "glycerin": "Glycerin",
    "polyoxyl 40 stearate": "PEG-40 Stearate",
    "sodium hydroxide": "Sodium Hydroxide",
    "stearic acid": "Stearic Acid",
    "palmitic acid": "Palmitic Acid",
    "dimethicone": "Dimethicone",
    "cetostearyl alcohol": "Cetearyl Alcohol",
    "silicon dioxide": "Silica",
    "propanediol": "Propanediol",
    "docusate sodium": "Diethylhexyl Sodium Sulfosuccinate",
}

GENERIC_PRODUCT_WORDS = {
    "cleanser",
    "toner",
    "moisturizer",
    "cream",
    "wash",
    "serum",
    "lotion",
    "foam",
    "gel",
    "soap",
    "sunscreen",
    "pads",
    "ampoule",
    "oil",
    "mask",
    "bar",
    "treatment",
    "spot",
}

FORM_ALIASES = {
    "wash": ("cleanser", "face wash", "wash", "foaming wash"),
    "soap": ("cleanser", "bar", "wash"),
    "bar": ("cleanser", "bar", "soap", "wash"),
    "cleansing": ("cleanser", "wash", "face wash"),
    "cleanser": ("cleanser", "wash", "face wash"),
    "gel": ("gel", "gel wash"),
    "cream": ("cream", "creamy wash"),
    "lotion": ("lotion", "moisturizer"),
    "spray": ("spray", "body spray"),
    "mask": ("mask",),
}

# SPL <title> is often "Drug Facts" or the highlights boilerplate. The search
# API title ("PANOXYL (BENZOYL PEROXIDE) CREAM [CROWN LABORATORIES]") is usable.
JUNK_TITLE_PREFIXES = (
    "drug facts",
    "these highlights",
    "highlights of prescribing",
    "warning",
    "indications",
)
JUNK_BRANDS = {
    "drug",
    "these",
    "this",
    "highlights",
    "facts",
    "warning",
    "indications",
    "the",
    "a",
    "an",
}
MULTIWORD_BRANDS = (
    "Gold Bond",
    "Burt's Bees",
    "Burts Bees",
    "La Roche-Posay",
    "First Aid Beauty",
    "Hero Cosmetics",
    "SkinCeuticals",
)
ACTIVE_ONLY_NAMES = {
    "benzoyl peroxide",
    "adapalene",
    "salicylic acid",
    "sulfur",
    "avobenzone",
    "octisalate",
    "octocrylene",
    "zinc oxide",
    "titanium dioxide",
}
LISTING_TITLE_RE = re.compile(
    r"^(?P<head>.+?)\s*(?:\((?P<active>[^)]*)\))?\s*(?P<form>[A-Z][A-Z0-9 /.-]*)?\s*(?:\[(?P<labeler>[^\]]+)\])?\s*$"
)


def _get(url: str, deadline: Deadline) -> bytes:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=deadline.timeout()) as response:
        return response.read(MAX_RESPONSE_BYTES)


def _parse_xml(xml_bytes: bytes) -> ET.Element:
    """Parse an SPL document, refusing any that declares a DTD or entities."""
    if _DOCTYPE_RE.search(xml_bytes[:4096]):
        raise ValueError("SPL document declares a DTD or entity; refusing to parse")
    return ET.fromstring(xml_bytes)


def _element_text(element: ET.Element | None) -> str:
    if element is None:
        return ""
    return " ".join("".join(element.itertext()).split())


def to_inci_name(label_name: str) -> str:
    raw = (label_name or "").strip()
    mapped = USAN_TO_INCI.get(raw.lower())
    if mapped:
        return mapped
    # Keep numeric commas (1,2-Hexanediol). Collapse the rest so
    # "Carbomer Homopolymer, Unspecified Type" stays one INCI token.
    cleaned = re.sub(r"(?<!\d)\s*,\s*", " ", raw)
    return display_inci_name(cleaned)


def _usable_title(text: str) -> bool:
    low = (text or "").strip().lower()
    if not low:
        return False
    if any(low.startswith(prefix) for prefix in JUNK_TITLE_PREFIXES):
        return False
    stripped = re.sub(r"[®™]", "", text).strip()
    # "PanOxyl" / "PanOxyl ®" is a brand, not a shelf name.
    if len(stripped.split()) <= 1:
        return False
    return True


def _title_case_if_needed(text: str) -> str:
    text = (text or "").strip()
    if not text:
        return ""
    return display_inci_name(text) if text.isupper() else text


def parse_listing_title(listing_title: str | None) -> tuple[str, str]:
    """Return (brand, product_name_hint) from a DailyMed search-API title."""
    title = (listing_title or "").strip()
    if not title:
        return "", ""
    match = LISTING_TITLE_RE.match(title)
    head = (match.group("head") if match else title.split("[")[0]).strip()
    head = head.split("(")[0].strip()
    head = _title_case_if_needed(head)
    if not head:
        return "", ""
    known = next(
        (brand for brand in sorted(MULTIWORD_BRANDS, key=len, reverse=True)
         if head.casefold().startswith(brand.casefold())),
        "",
    )
    first = head.split()[0]
    brand = known or (first if first.casefold() not in JUNK_BRANDS else "")
    form = _title_case_if_needed((match.group("form") or "").strip()) if match else ""
    name = head
    if brand and form and name.casefold() == brand.casefold():
        name = f"{brand} {form}"
    return brand, name


def _looks_like_substance_name(name: str) -> bool:
    low = re.sub(r"[®™]", "", name or "").strip().lower()
    if not low:
        return True
    if low in ACTIVE_ONLY_NAMES:
        return True
    return False


def _brand_from_name(name: str) -> str:
    first = (name or "").replace("®", "").replace("™", "").strip().split()
    if not first:
        return ""
    token = first[0]
    if token.casefold() in JUNK_BRANDS:
        return ""
    return _title_case_if_needed(token)


def search_queries(brand: str, name: str) -> list[str]:
    """Build DailyMed drug_name queries without sending generic words alone."""
    brand = (brand or "").strip()
    name = (name or "").strip()
    queries: list[str] = []
    if brand:
        if name and name.lower() not in GENERIC_PRODUCT_WORDS:
            queries.append(f"{brand} {name}".strip())
        queries.append(brand)
    elif name and name.lower() not in GENERIC_PRODUCT_WORDS:
        queries.append(name)

    seen: set[str] = set()
    unique: list[str] = []
    for query in queries:
        key = normalize_search_text(query)
        if key and key not in seen:
            seen.add(key)
            unique.append(query)
    return unique


def aliases_for(title: str, product_name: str) -> list[str]:
    blob = f"{title} {product_name}".lower()
    aliases: list[str] = []
    for token, extras in FORM_ALIASES.items():
        if token in blob:
            aliases.extend(extras)
    seen: set[str] = set()
    result: list[str] = []
    for alias in aliases:
        if alias not in seen:
            seen.add(alias)
            result.append(alias)
    return result


def _ndc_from(node: ET.Element) -> str | None:
    for code in node.findall(".//v3:code", SPL_NS):
        if code.get("codeSystem") == NDC_CODE_SYSTEM and code.get("code"):
            return code.get("code")
    return None


def _ingredients_from(node: ET.Element) -> list[str]:
    actives: list[str] = []
    inactives: list[str] = []
    for ingredient in node.findall("v3:ingredient", SPL_NS):
        substance = ingredient.find("v3:ingredientSubstance", SPL_NS)
        if substance is None:
            continue
        raw = _element_text(substance.find("v3:name", SPL_NS))
        if not raw:
            continue
        name = to_inci_name(raw)
        bucket = actives if ingredient.get("classCode") == "ACTIB" else inactives
        if name.casefold() not in {item.casefold() for item in bucket}:
            bucket.append(name)
    return [*actives, *inactives]


def parse_spl(
    xml_bytes: bytes,
    setid: str,
    listing_title: str | None = None,
) -> list[ProductLookupResult]:
    root = _parse_xml(xml_bytes)
    xml_title = _element_text(root.find("v3:title", SPL_NS))
    listing_brand, listing_name = parse_listing_title(listing_title)

    results: list[ProductLookupResult] = []
    seen_lists: set[str] = set()

    for manufactured in root.findall(".//v3:manufacturedProduct", SPL_NS):
        medicine = manufactured.find("v3:manufacturedMedicine", SPL_NS)
        node = medicine if medicine is not None else manufactured
        ingredients = _ingredients_from(node)
        if len(ingredients) < 2:
            continue
        list_key = ", ".join(item.casefold() for item in ingredients)
        if list_key in seen_lists:
            continue
        seen_lists.add(list_key)

        labeled_name = _title_case_if_needed(_element_text(node.find("v3:name", SPL_NS)))
        if _looks_like_substance_name(labeled_name) or re.search(r"®\S", labeled_name):
            labeled_name = ""
        brand_seed = listing_brand or _brand_from_name(labeled_name)
        if labeled_name:
            stripped = labeled_name.replace("®", "").replace("™", "").strip()
            if brand_seed and stripped.casefold() == brand_seed.casefold():
                labeled_name = ""

        if not labeled_name:
            # The search-API title uses a generic dosage form ("CREAM") even when
            # the SPL document title is the shelf name ("Panoxyl Acne Foaming Wash").
            if _usable_title(xml_title):
                labeled_name = _title_case_if_needed(
                    xml_title.split("[")[0].split("(")[0]
                )
            elif listing_name and (
                not brand_seed or listing_name.casefold() != brand_seed.casefold()
            ):
                labeled_name = listing_name
            else:
                labeled_name = listing_name or brand_seed or "Unknown product"

        brand = (
            listing_brand
            or _brand_from_name(labeled_name)
            or (_brand_from_name(xml_title) if _usable_title(xml_title) else "")
            or labeled_name.split()[0]
        )

        ndc = _ndc_from(node)
        alias_source = " ".join(part for part in [listing_title, xml_title, labeled_name] if part)
        results.append(
            ProductLookupResult(
                code=ndc,
                brand=brand,
                name=labeled_name,
                raw_ingredient_list=", ".join(ingredients),
                source="dailymed",
                product_url=f"https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid={setid}",
                ndc=ndc,
                setid=setid,
                search_aliases=tuple(aliases_for(alias_source, labeled_name)),
            )
        )
    return results


def search_spls(drug_name: str, deadline: Deadline, pagesize: int = 20) -> list[dict]:
    params = urlencode({"drug_name": drug_name, "pagesize": pagesize})
    payload = json.loads(_get(f"{DAILYMED_BASE}/spls.json?{params}", deadline))
    return payload.get("data") or []


def fetch_setid(
    setid: str,
    deadline: Deadline,
    listing_title: str | None = None,
) -> list[ProductLookupResult]:
    xml_bytes = _get(f"{DAILYMED_BASE}/spls/{setid}.xml", deadline)
    return parse_spl(xml_bytes, setid, listing_title=listing_title)


def search_products(
    brand: str,
    name: str,
    deadline: Deadline,
    max_labels: int = MAX_LABELS_PER_SEARCH,
) -> list[ProductLookupResult]:
    found: dict[str, ProductLookupResult] = {}
    labels_read = 0
    for query in search_queries(brand, name):
        if deadline.expired():
            break
        for row in search_spls(query, deadline):
            setid = row.get("setid")
            if not setid:
                continue
            if labels_read >= max_labels or deadline.expired():
                break
            labels_read += 1
            try:
                products = fetch_setid(setid, deadline, listing_title=row.get("title"))
            except Exception:
                logger.warning("could not read SPL %s", setid, exc_info=True)
                continue
            for product in products:
                key = product.ndc or f"{product.setid}:{product.name.casefold()}"
                found[key] = product
        if found:
            break
    return list(found.values())


def lookup_by_ndc(ndc: str, deadline: Deadline) -> ProductLookupResult | None:
    digits = "".join(ch for ch in ndc if ch.isdigit())
    if len(digits) < 8:
        return None
    params = urlencode({"ndc": ndc, "pagesize": 5})
    try:
        payload = json.loads(_get(f"{DAILYMED_BASE}/spls.json?{params}", deadline))
    except Exception:
        logger.warning("DailyMed NDC search failed for %r", ndc, exc_info=True)
        return None
    rows = payload.get("data") or []
    if not rows:
        return None
    products = fetch_setid(rows[0]["setid"], deadline, listing_title=rows[0].get("title"))
    return products[0] if products else None
