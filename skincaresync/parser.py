import html
import logging
import re
import threading
import time
import unicodedata
from dataclasses import dataclass, field

from psycopg2.extras import execute_values

from .database import get_cursor

logger = logging.getLogger(__name__)

# How long a process may serve its in-memory catalog before rebuilding it. The
# importer runs as a separate process, so it cannot invalidate a running API
# server's cache; without a TTL the server serves the pre-import catalog until
# it is manually restarted.
RESOLVER_TTL_SECONDS = 300


LABEL_PREFIX_RE = re.compile(
    r"^\s*(ingredients|ingredient list|inci|active ingredients)\s*:\s*",
    re.IGNORECASE,
)
PERCENT_RE = re.compile(r"\b\d+(\.\d+)?\s*%")
TRAILING_PUNCT_RE = re.compile(r"[\s.;:]+$")


@dataclass(frozen=True)
class Ingredient:
    id: int
    inci_name: str
    synonyms: list[str]
    category: str | None
    ph_min: float | None
    ph_max: float | None
    comodogenic: int | None
    alt_names: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class ResolvedIngredient:
    raw_token: str
    normalized_token: str
    ingredient: Ingredient | None
    match_type: str


def clean_label(raw_text: str) -> str:
    text = html.unescape(raw_text or "")
    text = unicodedata.normalize("NFKC", text)
    text = LABEL_PREFIX_RE.sub("", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def tokenize_inci(raw_text: str) -> list[str]:
    text = clean_label(raw_text)
    tokens: list[str] = []
    current: list[str] = []
    depth = 0

    for char in text:
        if char == "(":
            depth += 1
            current.append(char)
        elif char == ")":
            depth = max(0, depth - 1)
            current.append(char)
        elif char == "," and depth == 0:
            token = "".join(current).strip()
            if token:
                tokens.append(token)
            current = []
        else:
            current.append(char)

    token = "".join(current).strip()
    if token:
        tokens.append(token)

    return tokens


def normalize_token(token: str) -> str:
    normalized = html.unescape(token or "")
    normalized = unicodedata.normalize("NFKC", normalized)
    normalized = PERCENT_RE.sub("", normalized)
    normalized = re.sub(r"\([^)]*\)", "", normalized)
    normalized = TRAILING_PUNCT_RE.sub("", normalized)
    normalized = re.sub(r"\s+", " ", normalized)
    return normalized.strip().lower()


def fetch_ingredients() -> list[Ingredient]:
    with get_cursor() as cur:
        cur.execute(
            """
            SELECT
                ingridient_id,
                inci_name,
                synonyms,
                alt_names,
                category,
                ph_min,
                ph_max,
                comodogenic
            FROM ingredients
            ORDER BY ingridient_id
            """
        )
        return [
            Ingredient(
                id=row["ingridient_id"],
                inci_name=row["inci_name"],
                synonyms=row["synonyms"] or [],
                category=row["category"],
                ph_min=row["ph_min"],
                ph_max=row["ph_max"],
                comodogenic=row["comodogenic"],
                alt_names=row["alt_names"] or [],
            )
            for row in cur.fetchall()
        ]


_resolver_cache: tuple[float, "IngredientResolver"] | None = None
_resolver_lock = threading.Lock()


def get_shared_resolver() -> "IngredientResolver":
    """Process-wide resolver over the full catalog, rebuilt every TTL.

    Rebuilding the lookup tables on every `/api/analyze` call would rescan ~22k
    rows. This was an `lru_cache`, which meant a running server never picked up a
    catalog import at all: `cache_clear()` only affects the process that calls
    it, and the importer is a different process. A TTL bounds the staleness
    without any cross-process signalling.

    Tests that construct `IngredientResolver([...])` directly are unaffected.
    """
    global _resolver_cache
    cached = _resolver_cache
    now = time.monotonic()
    if cached is not None and now - cached[0] < RESOLVER_TTL_SECONDS:
        return cached[1]

    with _resolver_lock:
        # Another thread may have rebuilt it while we waited for the lock.
        cached = _resolver_cache
        if cached is not None and time.monotonic() - cached[0] < RESOLVER_TTL_SECONDS:
            return cached[1]
        resolver = IngredientResolver()
        _resolver_cache = (time.monotonic(), resolver)
        return resolver


def clear_shared_resolver() -> None:
    """Drop the cached resolver so the next call rebuilds it."""
    global _resolver_cache
    with _resolver_lock:
        _resolver_cache = None


def log_parser_unknowns(
    unknowns: list[tuple[str, str]],
    source_product: str | None = None,
) -> None:
    """Record unrecognised INCI tokens from one label in a single statement.

    This ran once per unknown token, each on its own pooled connection, inside
    the per-product parse loop. A label full of unrecognised botanical names cost
    one round trip per token.

    Failures are logged and swallowed: this is telemetry for catalog gaps and
    must never fail a user's analysis.
    """
    if not unknowns:
        return

    # De-duplicate within the batch: `raw_token` is the conflict key, and
    # Postgres rejects an ON CONFLICT statement that hits one key twice.
    rows = list({raw: (raw, normalized, source_product) for raw, normalized in unknowns}.values())

    try:
        with get_cursor() as cur:
            execute_values(
                cur,
                """
                INSERT INTO parser_unknowns (raw_token, normalized_token, source_product)
                VALUES %s
                ON CONFLICT (raw_token)
                DO UPDATE SET
                    occurrence_count = parser_unknowns.occurrence_count + 1,
                    normalized_token = EXCLUDED.normalized_token,
                    source_product = COALESCE(EXCLUDED.source_product, parser_unknowns.source_product),
                    last_seen = NOW()
                """,
                rows,
                page_size=500,
            )
    except Exception:
        logger.exception("failed to record %d unknown parser token(s)", len(rows))


class IngredientResolver:
    def __init__(self, ingredients: list[Ingredient] | None = None):
        self.ingredients = ingredients if ingredients is not None else fetch_ingredients()
        self.by_name: dict[str, Ingredient] = {}
        for ingredient in self.ingredients:
            # Preserve the first canonical match when names normalize to the same key,
            # e.g. "Hydroquinone" and "Hydroquinone 4%".
            self.by_name.setdefault(normalize_token(ingredient.inci_name), ingredient)
        self.by_synonym: dict[str, Ingredient] = {}
        for ingredient in self.ingredients:
            for alias in [*ingredient.synonyms, *ingredient.alt_names]:
                self.by_synonym.setdefault(normalize_token(alias), ingredient)

    def resolve_token(self, raw_token: str) -> ResolvedIngredient:
        """Classify one token. Pure: logging is batched by `resolve_label`."""
        normalized = normalize_token(raw_token)
        if not normalized:
            return ResolvedIngredient(raw_token, normalized, None, "empty")

        if normalized in self.by_name:
            return ResolvedIngredient(raw_token, normalized, self.by_name[normalized], "exact")

        if normalized in self.by_synonym:
            return ResolvedIngredient(raw_token, normalized, self.by_synonym[normalized], "synonym")

        return ResolvedIngredient(raw_token, normalized, None, "unknown")

    def resolve_label(self, raw_text: str, source_product: str | None = None) -> list[ResolvedIngredient]:
        resolved = [self.resolve_token(token) for token in tokenize_inci(raw_text)]
        log_parser_unknowns(
            [(item.raw_token, item.normalized_token) for item in resolved if item.match_type == "unknown"],
            source_product=source_product,
        )
        return resolved
