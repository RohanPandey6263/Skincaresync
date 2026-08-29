import json
import logging
import os
import re
import time
import unicodedata
from difflib import SequenceMatcher
from dataclasses import asdict, dataclass
from urllib.parse import quote_plus, urlencode
from urllib.request import Request, urlopen

logger = logging.getLogger(__name__)

OPEN_BEAUTY_FACTS_BASE = "https://world.openbeautyfacts.org"
USER_AGENT = "SkincareSync MVP - local development"

# Match thresholds. These are the single source of truth: the frontend used to
# carry its own copy of the final floor, and two of these constants were defined
# here but never read while the call sites hardcoded different numbers.
MIN_BRAND_SCORE = 70   # reject a candidate from the wrong brand outright
MIN_NAME_SCORE = 35    # floor for the name/alias score
MIN_MATCH_SCORE = 35   # floor for the combined score actually returned
GOOD_MATCH_SCORE = 70  # local hit this strong means we skip the upstream calls

# One lookup may touch DailyMed and Open Beauty Facts several times over. Without
# a shared budget the worst case was minutes: up to 13 DailyMed calls at 20s plus
# three Open Beauty Facts searches at 8s, each holding a threadpool worker.
LOOKUP_BUDGET_SECONDS = float(os.getenv("LOOKUP_BUDGET_SECONDS", "8"))
UPSTREAM_TIMEOUT_SECONDS = float(os.getenv("UPSTREAM_TIMEOUT_SECONDS", "4"))
# Cap on a single upstream response, so a huge or hostile body cannot exhaust
# memory. Real records are a few hundred kilobytes at most.
MAX_RESPONSE_BYTES = 5 * 1024 * 1024


class Deadline:
    """A wall-clock budget shared across every upstream call in one lookup."""

    def __init__(self, budget_seconds: float | None = None):
        self.expiry = time.monotonic() + (
            LOOKUP_BUDGET_SECONDS if budget_seconds is None else budget_seconds
        )

    def remaining(self) -> float:
        return max(0.0, self.expiry - time.monotonic())

    def expired(self) -> bool:
        return self.remaining() <= 0.0

    def timeout(self, cap: float = UPSTREAM_TIMEOUT_SECONDS) -> float:
        return min(cap, self.remaining())


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
    """Pull the product code out of a raw scan.

    A QR code is often a URL carrying both the product code and tracking
    parameters. Taking the last digit run picked the tracking id; the longest run
    is the barcode, and the earliest one wins a tie because the product path
    precedes the query string.
    """
    value = (scanned_value or "").strip()
    if value.isdigit():
        return value

    numeric_matches = re.findall(r"\d{8,14}", value)
    if not numeric_matches:
        return value
    return max(numeric_matches, key=len)


def _get_json(url: str, deadline: Deadline) -> dict:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=deadline.timeout()) as response:
        body = response.read(MAX_RESPONSE_BYTES)
    return json.loads(body.decode("utf-8"))


def normalize_search_text(value: str) -> str:
    """Fold a brand or product name to comparable ASCII tokens.

    Accented characters are decomposed and their marks dropped before the
    non-alphanumeric filter runs. Without that step the filter deleted the
    accented letter itself: "Bioré" became "bior" and could never match a stored
    "Biore", "L'Oréal" became "or" + "al" and matched almost every product, and
    "Nº7" produced no usable token at all. `products.search_text` is folded the
    same way by its trigger, so both sides of the comparison agree.
    """
    decomposed = unicodedata.normalize("NFKD", value or "")
    value = "".join(ch for ch in decomposed if not unicodedata.combining(ch)).lower()
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
    min_brand: int = MIN_BRAND_SCORE,
    min_name: int = MIN_NAME_SCORE,
    min_score: int = MIN_MATCH_SCORE,
) -> list[dict]:
    """Score, filter and rank candidates. Only confident matches are returned.

    The combined-score floor is applied here rather than in the browser, so the
    client no longer needs its own copy of the threshold.
    """
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
        if score < min_score:
            continue
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


def lookup_by_code(scanned_value: str, budget_seconds: float | None = None) -> dict | None:
    from . import dailymed
    from . import product_catalog

    code = extract_product_code(scanned_value)
    if not code:
        return None

    local = product_catalog.get_by_code(code)
    if local:
        return asdict(local)

    deadline = Deadline(budget_seconds)

    try:
        remote = dailymed.lookup_by_ndc(code, deadline)
    except Exception:
        logger.exception("DailyMed NDC lookup failed for %r", code)
        remote = None
    if remote:
        product_catalog.upsert_product(remote)
        return asdict(remote)

    if deadline.expired():
        logger.warning("lookup budget spent before Open Beauty Facts for %r", code)
        return None

    fields = "code,product_name,product_name_en,brands,ingredients_text,ingredients_text_en,ingredients_text_with_allergens,image_front_url,url"
    url = f"{OPEN_BEAUTY_FACTS_BASE}/api/v2/product/{quote_plus(code)}.json?fields={fields}"
    try:
        payload = _get_json(url, deadline)
    except Exception:
        logger.exception("Open Beauty Facts lookup failed for %r", code)
        raise

    if payload.get("status") != 1:
        return None

    result = _product_from_payload(payload.get("product") or {}, "open_beauty_facts")
    if result:
        product_catalog.upsert_product(result)
        return asdict(result)
    return None


def search_by_brand_and_name(
    brand: str,
    name: str,
    limit: int = 5,
    budget_seconds: float | None = None,
) -> list[dict]:
    from . import dailymed
    from . import product_catalog

    deadline = Deadline(budget_seconds)

    local = product_catalog.search_local(brand, name, limit=max(limit * 4, 12))
    scored = _score_candidates(local, brand, name)
    if scored and scored[0]["similarity_score"] >= GOOD_MATCH_SCORE:
        return scored[:limit]

    fetched: list[ProductLookupResult] = []

    if not deadline.expired():
        try:
            fetched.extend(dailymed.search_products(brand, name, deadline=deadline))
        except Exception:
            logger.exception("DailyMed search failed for brand=%r name=%r", brand, name)

    search_terms = [
        " ".join(part.strip() for part in [brand, name] if part and part.strip()),
        name.strip(),
        brand.strip(),
    ]
    search_terms = [term for term in dict.fromkeys(search_terms) if term]
    obf_candidates: dict[str, ProductLookupResult] = {}
    for terms in search_terms:
        if deadline.expired():
            logger.info("lookup budget spent; skipping remaining Open Beauty Facts terms")
            break
        try:
            for product in _search_products(terms, max(limit * 4, 12), deadline):
                key = product.code or f"{product.brand}:{product.name}"
                obf_candidates[key] = product
        except Exception:
            # Keep whatever earlier terms found. This used to reset the whole
            # dict, turning a partial success into "no results".
            logger.exception("Open Beauty Facts search failed for %r", terms)
            break

    # One connection for the whole page of results rather than one per product.
    product_catalog.upsert_products([*fetched, *obf_candidates.values()])

    merged = [*local, *fetched, *obf_candidates.values()]
    deduped: dict[str, ProductLookupResult] = {}
    for product in merged:
        key = product.setid or product.code or f"{product.brand}:{product.name}"
        deduped[key] = product

    return _score_candidates(list(deduped.values()), brand, name)[:limit]


def _search_products(
    search_terms: str,
    page_size: int,
    deadline: Deadline,
) -> list[ProductLookupResult]:
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
    payload = _get_json(f"{OPEN_BEAUTY_FACTS_BASE}/cgi/search.pl?{params}", deadline)
    results: list[ProductLookupResult] = []
    for product in payload.get("products", []):
        result = _product_from_payload(product, "open_beauty_facts")
        if result:
            results.append(result)
    return results
