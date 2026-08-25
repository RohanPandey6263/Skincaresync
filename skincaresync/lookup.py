import json
import re
from dataclasses import asdict, dataclass
from urllib.parse import quote_plus, urlencode
from urllib.request import Request, urlopen


OPEN_BEAUTY_FACTS_BASE = "https://world.openbeautyfacts.org"
USER_AGENT = "SkincareSync MVP - local development"


@dataclass(frozen=True)
class ProductLookupResult:
    code: str | None
    brand: str
    name: str
    raw_ingredient_list: str
    source: str
    image_url: str | None = None
    product_url: str | None = None


def extract_product_code(scanned_value: str) -> str:
    value = (scanned_value or "").strip()
    if value.isdigit():
        return value

    numeric_matches = re.findall(r"\d{8,14}", value)
    return numeric_matches[-1] if numeric_matches else value


def _get_json(url: str) -> dict:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=8) as response:
        return json.loads(response.read().decode("utf-8"))


def _product_from_payload(product: dict, source: str) -> ProductLookupResult | None:
    ingredients = (
        product.get("ingredients_text")
        or product.get("ingredients_text_en")
        or product.get("ingredients_text_with_allergens")
        or ""
    ).strip()
    name = (product.get("product_name") or product.get("product_name_en") or "").strip()
    brand = (product.get("brands") or "").split(",")[0].strip()

    if not ingredients:
        return None

    return ProductLookupResult(
        code=(product.get("code") or "").strip() or None,
        brand=brand,
        name=name or "Unknown product",
        raw_ingredient_list=ingredients,
        source=source,
        image_url=product.get("image_front_url"),
        product_url=product.get("url"),
    )


def lookup_by_code(scanned_value: str) -> dict | None:
    code = extract_product_code(scanned_value)
    if not code:
        return None

    fields = "code,product_name,product_name_en,brands,ingredients_text,ingredients_text_en,ingredients_text_with_allergens,image_front_url,url"
    url = f"{OPEN_BEAUTY_FACTS_BASE}/api/v2/product/{quote_plus(code)}.json?fields={fields}"
    payload = _get_json(url)
    if payload.get("status") != 1:
        return None

    result = _product_from_payload(payload.get("product") or {}, "open_beauty_facts")
    return asdict(result) if result else None


def search_by_brand_and_name(brand: str, name: str, limit: int = 5) -> list[dict]:
    terms = " ".join(part.strip() for part in [brand, name] if part and part.strip())
    if not terms:
        return []

    params = urlencode(
        {
            "search_terms": terms,
            "search_simple": 1,
            "action": "process",
            "json": 1,
            "page_size": limit,
            "fields": "code,product_name,product_name_en,brands,ingredients_text,ingredients_text_en,ingredients_text_with_allergens,image_front_url,url",
        }
    )
    payload = _get_json(f"{OPEN_BEAUTY_FACTS_BASE}/cgi/search.pl?{params}")
    results = []
    for product in payload.get("products", []):
        result = _product_from_payload(product, "open_beauty_facts")
        if result:
            results.append(asdict(result))
    return results

