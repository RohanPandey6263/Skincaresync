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
    ndc: str | None = None
    setid: str | None = None
    search_aliases: tuple[str, ...] = ()


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


def _score_candidates(
    candidates: list[ProductLookupResult],
    brand: str,
    name: str,
    min_brand: int,
    min_name: int,
) -> list[dict]:
    scored = []
    for product in candidates:
        brand_score = brand_similarity_score(brand, product)
        if brand.strip() and brand_score < min_brand:
            continue
        # Aliases let "cleanser" match a DailyMed "wash" without inventing ingredients.
        name_haystack = " ".join([product.name, *product.search_aliases])
        name_score = (
            round(text_similarity(name, name_haystack) * 100)
            if name.strip()
            else 100
        )
        if name.strip() and name_score < min_name:
            continue
        score = product_similarity_score(brand, name, product)
        if name.strip() and product.search_aliases:
            alias_boost = round(text_similarity(name, name_haystack) * 100)
            score = max(score, round(0.35 * (brand_score / 100) * 100 + 0.65 * alias_boost))
        scored.append(
            {
                **asdict(product),
                "similarity_score": score,
                "brand_similarity_score": brand_score,
                "name_similarity_score": name_score,
            }
        )
    scored.sort(key=lambda product: product["similarity_score"] or 0, reverse=True)
    return scored


def lookup_by_code(scanned_value: str) -> dict | None:
    from . import dailymed
    from . import product_catalog

    code = extract_product_code(scanned_value)
    if not code:
        return None

    local = product_catalog.get_by_code(code)
    if local:
        return asdict(local)

    try:
        remote = dailymed.lookup_by_ndc(code)
    except Exception:
        remote = None
    if remote:
        product_catalog.upsert_product(remote)
        return asdict(remote)

    fields = "code,product_name,product_name_en,brands,ingredients_text,ingredients_text_en,ingredients_text_with_allergens,image_front_url,url"
    url = f"{OPEN_BEAUTY_FACTS_BASE}/api/v2/product/{quote_plus(code)}.json?fields={fields}"
    payload = _get_json(url)
    if payload.get("status") != 1:
        return None

    result = _product_from_payload(payload.get("product") or {}, "open_beauty_facts")
    if result:
        product_catalog.upsert_product(result)
        return asdict(result)
    return None


def search_by_brand_and_name(brand: str, name: str, limit: int = 5) -> list[dict]:
    from . import dailymed
    from . import product_catalog

    local = product_catalog.search_local(brand, name, limit=max(limit * 4, 12))
    scored = _score_candidates(local, brand, name, min_brand=70, min_name=35)
    if scored and scored[0]["similarity_score"] >= 70:
        return scored[:limit]

    remote: list[ProductLookupResult] = []
    try:
        remote.extend(dailymed.search_products(brand, name))
    except Exception:
        pass
    for product in remote:
        product_catalog.upsert_product(product)

    search_terms = [
        " ".join(part.strip() for part in [brand, name] if part and part.strip()),
        name.strip(),
        brand.strip(),
    ]
    search_terms = [term for term in dict.fromkeys(search_terms) if term]
    obf_candidates: dict[str, ProductLookupResult] = {}
    try:
        for terms in search_terms:
            for product in _search_products(terms, page_size=max(limit * 4, 12)):
                key = product.code or f"{product.brand}:{product.name}"
                obf_candidates[key] = product
                product_catalog.upsert_product(product)
    except Exception:
        obf_candidates = {}

    merged = [*local, *remote, *obf_candidates.values()]
    deduped: dict[str, ProductLookupResult] = {}
    for product in merged:
        key = product.setid or product.code or f"{product.brand}:{product.name}"
        deduped[key] = product

    # Remote DailyMed fills can match via aliases ("cleanser" → wash), so keep
    # the looser name floor used for the local catalog.
    scored = _score_candidates(list(deduped.values()), brand, name, min_brand=70, min_name=35)
    return scored[:limit]


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

