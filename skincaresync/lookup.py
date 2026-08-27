import json
import re
from difflib import SequenceMatcher
from dataclasses import asdict, dataclass
from urllib.parse import quote_plus, urlencode
from urllib.request import Request, urlopen


OPEN_BEAUTY_FACTS_BASE = "https://world.openbeautyfacts.org"
USER_AGENT = "SkincareSync MVP - local development"
MIN_BRAND_SCORE = 70
MIN_NAME_SCORE = 50


@dataclass(frozen=True)
class ProductLookupResult:
    code: str | None
    brand: str
    name: str
    raw_ingredient_list: str
    source: str
    image_url: str | None = None
    product_url: str | None = None
    similarity_score: int | None = None


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


def normalize_search_text(value: str) -> str:
    value = (value or "").lower()
    value = re.sub(r"[^a-z0-9]+", " ", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def _tokens(value: str) -> list[str]:
    return [token for token in normalize_search_text(value).split() if token not in {"the", "a", "an"}]


def _token_coverage(query: str, candidate: str) -> float:
    query_tokens = _tokens(query)
    candidate_tokens = _tokens(candidate)
    if not query_tokens:
        return 1.0
    if not candidate_tokens:
        return 0.0

    matched = 0
    for query_token in query_tokens:
        if any(
            query_token == candidate_token
            or SequenceMatcher(None, query_token, candidate_token).ratio() >= 0.72
            for candidate_token in candidate_tokens
        ):
            matched += 1
    return matched / len(query_tokens)


def text_similarity(query: str, candidate: str) -> float:
    normalized_query = normalize_search_text(query)
    normalized_candidate = normalize_search_text(candidate)
    if not normalized_query:
        return 1.0
    if not normalized_candidate:
        return 0.0

    sequence_score = SequenceMatcher(None, normalized_query, normalized_candidate).ratio()
    coverage_score = _token_coverage(normalized_query, normalized_candidate)
    return max(sequence_score, coverage_score)


def product_similarity_score(input_brand: str, input_name: str, candidate: ProductLookupResult) -> int:
    brand_query = (input_brand or "").strip()
    name_query = (input_name or "").strip()
    if brand_query and name_query:
        score = 0.35 * text_similarity(brand_query, candidate.brand)
        score += 0.65 * text_similarity(name_query, candidate.name)
        return round(score * 100)
    if name_query:
        return round(text_similarity(name_query, f"{candidate.brand} {candidate.name}") * 100)
    if brand_query:
        return round(text_similarity(brand_query, candidate.brand) * 100)
    return 0


def brand_similarity_score(input_brand: str, candidate: ProductLookupResult) -> int:
    brand_query = (input_brand or "").strip()
    if not brand_query:
        return 100
    return round(text_similarity(brand_query, candidate.brand) * 100)


def name_similarity_score(input_name: str, candidate: ProductLookupResult) -> int:
    name_query = (input_name or "").strip()
    if not name_query:
        return 100
    return round(text_similarity(name_query, candidate.name) * 100)


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


def _search_products(search_terms: str, page_size: int) -> list[ProductLookupResult]:
    params = urlencode(
        {
            "search_terms": search_terms,
            "search_simple": 1,
            "action": "process",
            "json": 1,
            "page_size": page_size,
            "fields": "code,product_name,product_name_en,brands,ingredients_text,ingredients_text_en,ingredients_text_with_allergens,image_front_url,url",
        }
    )
    payload = _get_json(f"{OPEN_BEAUTY_FACTS_BASE}/cgi/search.pl?{params}")
    results: list[ProductLookupResult] = []
    for product in payload.get("products", []):
        result = _product_from_payload(product, "open_beauty_facts")
        if result:
            results.append(result)
    return results


def search_by_brand_and_name(brand: str, name: str, limit: int = 5) -> list[dict]:
    search_terms = [
        " ".join(part.strip() for part in [brand, name] if part and part.strip()),
        name.strip(),
        brand.strip(),
    ]
    search_terms = [term for term in dict.fromkeys(search_terms) if term]
    if not search_terms:
        return []

    candidates: dict[str, ProductLookupResult] = {}
    for terms in search_terms:
        for product in _search_products(terms, page_size=max(limit * 4, 12)):
            key = product.code or f"{product.brand}:{product.name}"
            candidates[key] = product

    scored = []
    for product in candidates.values():
        brand_score = brand_similarity_score(brand, product)
        if brand.strip() and brand_score < MIN_BRAND_SCORE:
            continue
        name_score = name_similarity_score(name, product)
        if name.strip() and name_score < MIN_NAME_SCORE:
            continue
        score = product_similarity_score(brand, name, product)
        scored.append(
            {
                **asdict(product),
                "similarity_score": score,
                "brand_similarity_score": brand_score,
                "name_similarity_score": name_score,
            }
        )

    scored.sort(key=lambda product: product["similarity_score"] or 0, reverse=True)
    return scored[:limit]

