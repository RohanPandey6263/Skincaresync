"""Official-catalog sources for brands already in the vitamin C seed.

Shopify and Demandware listings are used only as an index. Ingredient text
comes from the product page itself (or a CPNP page). Open Beauty Facts and
DailyMed cover brands that do not publish a crawlable storefront INCI.
"""

from __future__ import annotations

import json
import os
import re
import time
import unicodedata
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen

from .inci_extract import extract_inci_from_html, looks_like_inci
from .lookup import OPEN_BEAUTY_FACTS_BASE, ProductLookupResult, USER_AGENT, _product_from_payload
from .published_labels import normalize_published_inci, products_for_family

# This client identifies itself honestly. It previously sent a Chrome user agent
# string, which misrepresents an automated importer as a person browsing and
# works against the terms of service of most storefronts -- a poor fit for a
# project that is otherwise careful about attribution and licensing.
#
# Some storefronts will refuse an unrecognised agent. If a brand has given you
# permission to crawl and requires a specific string, set CATALOG_USER_AGENT
# rather than editing this default, so the choice stays visible in deployment
# config instead of hidden in the source.
BROWSER_UA = os.getenv(
    "CATALOG_USER_AGENT",
    "SkincareSyncBot/0.1 (+https://github.com/skincaresync; ingredient-list importer)",
)
SKIP_LISTING_RE = re.compile(
    r"gift card|bundle-builder-dummy|dummy product|do not add this product|"
    r"sca_clone|freegift|gwp-choice",
    re.IGNORECASE,
)
TITLE_SKIP_RE = re.compile(
    r"\b(gift card|dummy|bundle builder|deluxe sample|packette|freegift|merch)\b|"
    r"\[subscr\.\]|100%\s*off|\bholiday set\b",
    re.IGNORECASE,
)
BUNDLE_TITLE_RE = re.compile(
    r"\b(kit|duo|trio|set|bundle|collection)\b",
    re.IGNORECASE,
)
SUBSCRIPTION_HANDLE_RE = re.compile(r"(^|/)subscr-", re.IGNORECASE)
HANDLE_SKIP_RE = re.compile(
    r"freegift|sca_clone|packette|deluxe-sample|sample-kit",
    re.IGNORECASE,
)
H1_RE = re.compile(r"<h1[^>]*>(.*?)</h1>", re.IGNORECASE | re.DOTALL)
OG_TITLE_RE = re.compile(
    r'<meta[^>]+property=["\']og:title["\'][^>]+content=["\']([^"\']+)["\']',
    re.IGNORECASE,
)
PRODUCT_PATH_RE = re.compile(r"/en-us/[^\"']+-\d{5,6}\.html")
FETCH_ERRORS = (HTTPError, URLError, TimeoutError, OSError, UnicodeError)


@dataclass(frozen=True)
class ShopifyStore:
    brand: str
    base_url: str
    extra_aliases: tuple[str, ...] = ()
    keep_vendors: tuple[str, ...] = ()
    skip_product_types: tuple[str, ...] = ()


@dataclass(frozen=True)
class DemandwareCatalog:
    brand: str
    grid_url: str
    site_origin: str
    extra_aliases: tuple[str, ...] = ()


SHOPIFY_STORES: tuple[ShopifyStore, ...] = (
    ShopifyStore("COSRX", "https://www.cosrx.com"),
    ShopifyStore("Minimalist", "https://beminimalist.co"),
    ShopifyStore("Beauty of Joseon", "https://beautyofjoseon.com", extra_aliases=("boj", "joseon")),
    ShopifyStore("Naturium", "https://naturium.com"),
    ShopifyStore("numbuzin", "https://us.numbuzin.com"),
    ShopifyStore("Innisfree", "https://us.innisfree.com"),
    ShopifyStore("Klairs", "https://www.klairs.com", extra_aliases=("dear klairs",)),
    ShopifyStore("MISSHA", "https://misshaus.com"),
    ShopifyStore("JUMISO", "https://jumiso.us"),
    ShopifyStore("Timeless", "https://www.timelessha.com"),
    ShopifyStore("Mad Hippie", "https://madhippie.com"),
    ShopifyStore("By Wishtrend", "https://wishtrend.com", extra_aliases=("wishtrend",)),
    ShopifyStore("Paula's Choice", "https://www.paulaschoice.com.au"),
    ShopifyStore("medicube", "https://medicube.us", extra_aliases=("medicube", "age-r")),
    ShopifyStore("Byoma", "https://byoma.com"),
    ShopifyStore("Cocokind", "https://www.cocokind.com"),
    ShopifyStore("Good Molecules", "https://shop.goodmolecules.com", extra_aliases=("good molecules",)),
    ShopifyStore("Hero Cosmetics", "https://www.herocosmetics.us", extra_aliases=("hero", "mighty patch")),
    ShopifyStore("Versed", "https://www.versedskin.com"),
    ShopifyStore("The INKEY List", "https://www.theinkeylist.com", extra_aliases=("inkey",)),
    ShopifyStore("Sunday Riley", "https://sundayriley.com"),
    ShopifyStore("Glow Recipe", "https://glowrecipe.com"),
    ShopifyStore("Rhode", "https://www.rhodeskin.com"),
    ShopifyStore("Summer Fridays", "https://summerfridays.com"),
    ShopifyStore("First Aid Beauty", "https://www.firstaidbeauty.com", extra_aliases=("fab",)),
    ShopifyStore("Tatcha", "https://www.tatcha.com"),
    ShopifyStore("Murad", "https://www.murad.com"),
    ShopifyStore("Peter Thomas Roth", "https://www.peterthomasroth.com", extra_aliases=("ptr",)),
    ShopifyStore("EltaMD", "https://eltamd.com"),
    ShopifyStore("Tula", "https://www.tula.com"),
    ShopifyStore(
        "Glossier",
        "https://www.glossier.com",
        skip_product_types=("Makeup", "Merch", "Fragrance", "Collateral", "Gift Cards"),
    ),
    ShopifyStore(
        "Fenty Skin",
        "https://www.fentybeauty.com",
        extra_aliases=("fenty",),
        keep_vendors=("Fenty Skin",),
        skip_product_types=("Apparel", "Pillowcases & Shams", "Cosmetic & Toiletry Bags", "Makeup Bag"),
    ),
    ShopifyStore(
        "Sol de Janeiro",
        "https://www.soldejaneiro.com",
        extra_aliases=("sdj",),
        skip_product_types=("GWP-choice", "GWP", "Perfume & Cologne"),
    ),
    ShopifyStore("Supergoop!", "https://supergoop.com", extra_aliases=("supergoop",)),
    ShopifyStore("Olay", "https://www.olay.com"),
    ShopifyStore("RoC", "https://www.rocskincare.com"),
    ShopifyStore("Laneige", "https://us.laneige.com"),
    ShopifyStore("SK-II", "https://www.sk-ii.com", extra_aliases=("skii", "sk ii")),
    ShopifyStore("Sulwhasoo", "https://us.sulwhasoo.com"),
    ShopifyStore("Bubble", "https://hellobubble.myshopify.com", extra_aliases=("bubble skincare",)),
)

DEMANDWARE_CATALOGS: tuple[DemandwareCatalog, ...] = (
    DemandwareCatalog(
        brand="The Ordinary",
        grid_url=(
            "https://theordinary.com/on/demandware.store/Sites-deciem-us-Site/"
            "en_US/Search-UpdateGrid?cgid=theordinary&start={start}&sz={sz}"
        ),
        site_origin="https://theordinary.com",
    ),
)

OBF_BRAND_QUERIES: tuple[tuple[str, str], ...] = (
    ("Aquaphor", "Aquaphor"),
    ("Aveeno", "Aveeno"),
    ("Burt's Bees", "Burt's Bees"),
    ("CeraVe", "CeraVe"),
    ("Cetaphil", "Cetaphil"),
    ("Differin", "Differin"),
    ("Dove", "Dove"),
    ("Eucerin", "Eucerin"),
    ("Garnier", "Garnier"),
    ("Gold Bond", "Gold Bond"),
    ("L'Oréal Paris", "L'Oreal Paris"),
    ("Neutrogena", "Neutrogena"),
    ("Nivea", "Nivea"),
    ("Olay", "Olay"),
    ("PanOxyl", "PanOxyl"),
    ("Pond's", "Pond's"),
    ("RoC", "RoC"),
    ("Vanicream", "Vanicream"),
    ("Vaseline", "Vaseline"),
    ("Avène", "Avene"),
    ("Bioderma", "Bioderma"),
    ("EltaMD", "EltaMD"),
    ("La Roche-Posay", "La Roche-Posay"),
    ("SkinCeuticals", "SkinCeuticals"),
    ("Vichy", "Vichy"),
    ("Bubble", "Bubble"),
    ("Byoma", "Byoma"),
    ("Cocokind", "Cocokind"),
    ("Good Molecules", "Good Molecules"),
    ("Hero Cosmetics", "Hero Cosmetics"),
    ("Naturium", "Naturium"),
    ("Paula's Choice", "Paula's Choice"),
    ("The INKEY List", "INKEY"),
    ("The Ordinary", "The Ordinary"),
    ("Thayers", "Thayers"),
    ("Versed", "Versed"),
    ("Caudalie", "Caudalie"),
    ("Clinique", "Clinique"),
    ("Dr. Dennis Gross", "Dennis Gross"),
    ("Drunk Elephant", "Drunk Elephant"),
    ("Estée Lauder", "Estee Lauder"),
    ("First Aid Beauty", "First Aid Beauty"),
    ("Fresh", "Fresh"),
    ("Kiehl's", "Kiehl's"),
    ("La Mer", "La Mer"),
    ("Lancôme", "Lancome"),
    ("Murad", "Murad"),
    ("Origins", "Origins"),
    ("Peter Thomas Roth", "Peter Thomas Roth"),
    ("Sunday Riley", "Sunday Riley"),
    ("Supergoop!", "Supergoop"),
    ("Tatcha", "Tatcha"),
    ("Beauty of Joseon", "Beauty of Joseon"),
    ("COSRX", "COSRX"),
    ("Dr. Jart+", "Dr. Jart"),
    ("Glow Recipe", "Glow Recipe"),
    ("Innisfree", "Innisfree"),
    ("Laneige", "Laneige"),
    ("medicube", "medicube"),
    ("Shiseido", "Shiseido"),
    ("SK-II", "SK-II"),
    ("Sulwhasoo", "Sulwhasoo"),
    ("Fenty Skin", "Fenty Skin"),
    ("Glossier", "Glossier"),
    ("Rhode", "Rhode"),
    ("Sol de Janeiro", "Sol de Janeiro"),
    ("Summer Fridays", "Summer Fridays"),
    ("Tula", "Tula"),
    ("Youth to the People", "Youth to the People"),
    ("Timeless", "Timeless"),
    ("Mad Hippie", "Mad Hippie"),
    ("Minimalist", "Minimalist"),
    ("Klairs", "Klairs"),
    ("Isntree", "Isntree"),
    ("By Wishtrend", "Wishtrend"),
    ("Goodal", "Goodal"),
    ("TIA'M", "TIA'M"),
    ("SOME BY MI", "SOME BY MI"),
    ("numbuzin", "numbuzin"),
    ("MISSHA", "MISSHA"),
    ("JUMISO", "JUMISO"),
)

DAILYMED_BRANDS: tuple[str, ...] = (
    "Aquaphor",
    "Aveeno",
    "Burts Bees",
    "CeraVe",
    "Cetaphil",
    "Differin",
    "Dove",
    "Eucerin",
    "Garnier",
    "Gold Bond",
    "L'Oreal",
    "Neutrogena",
    "Nivea",
    "Olay",
    "PanOxyl",
    "Pond's",
    "RoC",
    "Vanicream",
    "Vaseline",
    "Avene",
    "Bioderma",
    "EltaMD",
    "La Roche-Posay",
    "SkinCeuticals",
    "Vichy",
    "Thayers",
    "First Aid Beauty",
    "Hero Cosmetics",
)

CATALOG_BRANDS: tuple[str, ...] = (
    "Aquaphor",
    "Aveeno",
    "Burt's Bees",
    "CeraVe",
    "Cetaphil",
    "Differin",
    "Dove",
    "Eucerin",
    "Garnier",
    "Gold Bond",
    "L'Oréal Paris",
    "Neutrogena",
    "Nivea",
    "Olay",
    "PanOxyl",
    "Pond's",
    "RoC",
    "Vanicream",
    "Vaseline",
    "Avène",
    "Bioderma",
    "EltaMD",
    "La Roche-Posay",
    "SkinCeuticals",
    "Vichy",
    "Bubble",
    "Byoma",
    "Cocokind",
    "Good Molecules",
    "Hero Cosmetics",
    "Naturium",
    "Paula's Choice",
    "The INKEY List",
    "The Ordinary",
    "Thayers",
    "Versed",
    "Caudalie",
    "Clinique",
    "Dr. Dennis Gross",
    "Drunk Elephant",
    "Estée Lauder",
    "First Aid Beauty",
    "Fresh",
    "Kiehl's",
    "La Mer",
    "Lancôme",
    "Murad",
    "Origins",
    "Peter Thomas Roth",
    "Sunday Riley",
    "Supergoop!",
    "Tatcha",
    "Beauty of Joseon",
    "COSRX",
    "Dr. Jart+",
    "Glow Recipe",
    "Innisfree",
    "Laneige",
    "medicube",
    "Shiseido",
    "SK-II",
    "Sulwhasoo",
    "Fenty Skin",
    "Glossier",
    "Rhode",
    "Sol de Janeiro",
    "Summer Fridays",
    "Tula",
    "Youth to the People",
)


def brand_key(name: str) -> str:
    text = unicodedata.normalize("NFKD", name or "")
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return re.sub(r"[^a-z0-9]+", "", text.casefold())


def brands_wanted(name: str, brands: list[str] | tuple[str, ...]) -> bool:
    if not brands:
        return True
    wanted = {brand_key(item) for item in brands}
    key = brand_key(name)
    if key in wanted:
        return True
    # DailyMed "L'Oreal" should match catalog "L'Oréal Paris".
    return any(
        key.startswith(item) or item.startswith(key)
        for item in wanted
        if min(len(key), len(item)) >= 5
    )


def catalog_brands() -> tuple[str, ...]:
    return CATALOG_BRANDS


def vitamin_c_brands() -> tuple[str, ...]:
    return tuple(sorted({item.brand for item in products_for_family("vitamin-c")}))


def encode_http_url(url: str) -> str:
    """Percent-encode non-ASCII path/query so http.client can send the request."""
    parts = urlsplit(url)
    return urlunsplit(
        (
            parts.scheme,
            parts.netloc,
            quote(parts.path, safe="/%-._~"),
            quote(parts.query, safe="=&%+-._~"),
            quote(parts.fragment, safe="%-._~"),
        )
    )


def _request(url: str, *, accept: str | None = None, timeout: int = 25) -> bytes:
    headers = {"User-Agent": BROWSER_UA}
    if accept:
        headers["Accept"] = accept
    request = Request(encode_http_url(url), headers=headers)
    with urlopen(request, timeout=timeout) as response:
        return response.read()


def fetch_html(url: str) -> str:
    return _request(url).decode("utf-8", "replace")


def fetch_json(url: str) -> dict | list:
    return json.loads(_request(url, accept="application/json").decode("utf-8", "replace"))


def iter_shopify_listings(store: ShopifyStore):
    page = 1
    while page <= 30:
        payload = fetch_json(f"{store.base_url}/products.json?limit=250&page={page}")
        products = payload.get("products") or []
        if not products:
            break
        yield from products
        if len(products) < 250:
            break
        page += 1


def should_skip_listing(product: dict, store: ShopifyStore | None = None) -> bool:
    title = product.get("title") or ""
    if TITLE_SKIP_RE.search(title) or BUNDLE_TITLE_RE.search(title):
        return True
    handle = product.get("handle") or ""
    if SUBSCRIPTION_HANDLE_RE.search(handle) or HANDLE_SKIP_RE.search(handle):
        return True
    product_type = product.get("product_type") or ""
    vendor = product.get("vendor") or ""
    if store and store.keep_vendors:
        allowed = {item.casefold() for item in store.keep_vendors}
        if vendor.casefold() not in allowed:
            return True
    if store and store.skip_product_types:
        skipped = {item.casefold() for item in store.skip_product_types}
        if product_type.casefold() in skipped:
            return True
    tags = product.get("tags") or ""
    if isinstance(tags, list):
        tags = ",".join(tags)
    blob = f"{title} {tags} {product_type} {product.get('body_html') or ''}"
    return bool(SKIP_LISTING_RE.search(blob))


def _barcode_from_shopify(product: dict) -> str | None:
    for variant in product.get("variants") or []:
        barcode = (variant.get("barcode") or "").strip()
        if barcode:
            return barcode
    return None


def _display_name(title: str, handle: str) -> str:
    name = (title or "").strip()
    handle = (handle or "").strip().lower()
    suffix = None
    if handle.endswith("-eu") or handle.endswith("_eu"):
        suffix = "EU"
    elif handle.endswith("-uk") or handle.endswith("_uk"):
        suffix = "UK"
    if suffix and suffix.casefold() not in name.casefold():
        name = f"{name} ({suffix})"
    return name


def _aliases_for(store_aliases: tuple[str, ...], product_type: str, title: str) -> tuple[str, ...]:
    aliases = list(store_aliases)
    ptype = (product_type or "").strip()
    if ptype and ptype.casefold() not in {"custom", "default"}:
        aliases.append(ptype)
    for token in ("serum", "cleanser", "toner", "moisturizer", "sunscreen", "cream", "essence", "ampoule"):
        if token in title.casefold() and token not in {item.casefold() for item in aliases}:
            aliases.append(token)
    seen: set[str] = set()
    ordered: list[str] = []
    for alias in aliases:
        key = alias.casefold()
        if key and key not in seen:
            seen.add(key)
            ordered.append(alias)
    return tuple(ordered)


def listing_to_product(
    store: ShopifyStore,
    listing: dict,
    page_html: str,
) -> ProductLookupResult | None:
    inci = extract_inci_from_html(page_html)
    if not inci:
        return None
    handle = listing.get("handle") or ""
    url = f"{store.base_url}/products/{handle}"
    return ProductLookupResult(
        code=_barcode_from_shopify(listing),
        brand=store.brand,
        name=_display_name(listing.get("title") or "", handle),
        raw_ingredient_list=inci,
        source="manual",
        image_url=((listing.get("images") or [{}])[0].get("src") if listing.get("images") else None),
        product_url=url,
        search_aliases=_aliases_for(store.extra_aliases, listing.get("product_type") or "", listing.get("title") or ""),
    )


def iter_shopify_products(store: ShopifyStore, *, delay_s: float = 0.15, limit: int | None = None):
    yielded = 0
    for listing in iter_shopify_listings(store):
        if should_skip_listing(listing, store):
            continue
        handle = listing.get("handle")
        if not handle:
            continue
        url = f"{store.base_url}/products/{handle}"
        try:
            page_html = fetch_html(url)
        except FETCH_ERRORS:
            continue
        product = listing_to_product(store, listing, page_html)
        if product:
            yield product
            yielded += 1
            if limit is not None and yielded >= limit:
                return
        time.sleep(delay_s)


def iter_demandware_urls(catalog: DemandwareCatalog, *, page_size: int = 100) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    start = 0
    while start <= 2000:
        url = catalog.grid_url.format(start=start, sz=page_size)
        try:
            html = fetch_html(url)
        except FETCH_ERRORS:
            break
        paths = PRODUCT_PATH_RE.findall(html)
        new = 0
        for path in paths:
            full = catalog.site_origin + path
            if full in seen:
                continue
            seen.add(full)
            found.append(full)
            new += 1
        if new == 0:
            break
        start += page_size
    return found


def _demandware_name(page_html: str, url: str) -> str:
    match = H1_RE.search(page_html)
    if match:
        name = re.sub(r"<[^>]+>", " ", match.group(1))
        name = re.sub(r"\s+", " ", name).strip()
        if name:
            return name
    match = OG_TITLE_RE.search(page_html)
    if match:
        name = match.group(1).split("|")[0].strip()
        if name:
            return name
    slug = url.rsplit("/", 1)[-1].removesuffix(".html")
    slug = re.sub(r"-\d{5,6}$", "", slug)
    return slug.replace("-", " ").strip().title()


def iter_demandware_products(
    catalog: DemandwareCatalog, *, delay_s: float = 0.15, limit: int | None = None
):
    yielded = 0
    for url in iter_demandware_urls(catalog):
        if "gift-card" in url:
            continue
        try:
            page_html = fetch_html(url)
        except FETCH_ERRORS:
            continue
        inci = extract_inci_from_html(page_html)
        if not inci:
            time.sleep(delay_s)
            continue
        yield ProductLookupResult(
            code=None,
            brand=catalog.brand,
            name=_demandware_name(page_html, url),
            raw_ingredient_list=inci,
            source="manual",
            product_url=url,
            search_aliases=catalog.extra_aliases,
        )
        yielded += 1
        if limit is not None and yielded >= limit:
            return
        time.sleep(delay_s)


def iter_cpnp_pages(store: ShopifyStore, *, delay_s: float = 0.15, limit: int | None = None):
    yielded = 0
    page = 1
    while page <= 10:
        payload = fetch_json(f"{store.base_url}/pages.json?limit=250&page={page}")
        pages = payload.get("pages") or []
        if not pages:
            break
        for item in pages:
            handle = item.get("handle") or ""
            if "cpnp" not in handle:
                continue
            url = f"{store.base_url}/pages/{handle}"
            try:
                page_html = fetch_html(url)
            except FETCH_ERRORS:
                continue
            inci = extract_inci_from_html(page_html)
            if not inci:
                continue
            title = (item.get("title") or handle).strip()
            title = re.sub(r"\s*CPNP\s*SCPN\s*Information\s*$", "", title, flags=re.I).strip()
            yield ProductLookupResult(
                code=None,
                brand=store.brand,
                name=title,
                raw_ingredient_list=inci,
                source="manual",
                product_url=url,
                search_aliases=store.extra_aliases,
            )
            yielded += 1
            if limit is not None and yielded >= limit:
                return
            time.sleep(delay_s)
        if len(pages) < 250:
            break
        page += 1


def iter_obf_brand(brand: str, query: str, *, page_size: int = 100) -> list[ProductLookupResult]:
    results: list[ProductLookupResult] = []
    page = 1
    while page <= 20:
        params = urlencode(
            {
                "action": "process",
                "tagtype_0": "brands",
                "tag_contains_0": "contains",
                "tag_0": query,
                "json": 1,
                "page_size": page_size,
                "page": page,
                "fields": (
                    "code,product_name,product_name_en,brands,ingredients_text,"
                    "ingredients_text_en,ingredients_text_with_allergens,image_front_url,url"
                ),
            }
        )
        request = Request(
            f"{OPEN_BEAUTY_FACTS_BASE}/cgi/search.pl?{params}",
            headers={"User-Agent": USER_AGENT},
        )
        try:
            with urlopen(request, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError):
            break
        products = payload.get("products") or []
        if not products:
            break
        for raw in products:
            parsed = _product_from_payload(raw, "open_beauty_facts")
            if not parsed:
                continue
            inci = normalize_published_inci(parsed.raw_ingredient_list)
            if not looks_like_inci(inci):
                continue
            results.append(
                ProductLookupResult(
                    code=parsed.code,
                    brand=brand,
                    name=parsed.name,
                    raw_ingredient_list=inci,
                    source="open_beauty_facts",
                    image_url=parsed.image_url,
                    product_url=parsed.product_url,
                )
            )
        if len(products) < page_size:
            break
        page += 1
    return results
