import html
import re
import unicodedata
from dataclasses import dataclass

from .database import get_cursor


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
                category,
                ph_min,
                ph_max,
                comodogenic
            FROM ingredients
            ORDER BY inci_name
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
            )
            for row in cur.fetchall()
        ]


def log_parser_unknown(raw_token: str, normalized_token: str, source_product: str | None = None) -> None:
    with get_cursor() as cur:
        cur.execute(
            """
            INSERT INTO parser_unknowns (raw_token, normalized_token, source_product)
            VALUES (%s, %s, %s)
            ON CONFLICT (raw_token)
            DO UPDATE SET
                occurrence_count = parser_unknowns.occurrence_count + 1,
                normalized_token = EXCLUDED.normalized_token,
                source_product = COALESCE(EXCLUDED.source_product, parser_unknowns.source_product),
                last_seen = NOW()
            """,
            (raw_token, normalized_token, source_product),
        )


class IngredientResolver:
    def __init__(self, ingredients: list[Ingredient] | None = None):
        self.ingredients = ingredients if ingredients is not None else fetch_ingredients()
        self.by_name = {
            normalize_token(ingredient.inci_name): ingredient
            for ingredient in self.ingredients
        }
        self.by_synonym: dict[str, Ingredient] = {}
        for ingredient in self.ingredients:
            for synonym in ingredient.synonyms:
                self.by_synonym[normalize_token(synonym)] = ingredient

    def resolve_token(self, raw_token: str, source_product: str | None = None) -> ResolvedIngredient:
        normalized = normalize_token(raw_token)
        if not normalized:
            return ResolvedIngredient(raw_token, normalized, None, "empty")

        if normalized in self.by_name:
            return ResolvedIngredient(raw_token, normalized, self.by_name[normalized], "exact")

        if normalized in self.by_synonym:
            return ResolvedIngredient(raw_token, normalized, self.by_synonym[normalized], "synonym")

        log_parser_unknown(raw_token, normalized, source_product)
        return ResolvedIngredient(raw_token, normalized, None, "unknown")

    def resolve_label(self, raw_text: str, source_product: str | None = None) -> list[ResolvedIngredient]:
        return [
            self.resolve_token(token, source_product=source_product)
            for token in tokenize_inci(raw_text)
        ]

