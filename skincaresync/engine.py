import itertools
import json
from dataclasses import asdict, dataclass
from typing import Iterable

from .database import get_cursor
from .parser import IngredientResolver, ResolvedIngredient, get_shared_resolver


SEVERITY_RANK = {"low": 1, "medium": 2, "high": 3}
ESCALATING_CONCERNS = {"rosacea", "eczema"}


@dataclass(frozen=True)
class ProductInput:
    name: str
    brand: str = ""
    raw_ingredient_list: str = ""

    @property
    def label(self) -> str:
        return f"{self.brand} {self.name}".strip() or "Unnamed product"


@dataclass(frozen=True)
class SkinProfileInput:
    skin_type: str
    concerns: list[str]


@dataclass(frozen=True)
class ProductIngredients:
    product: ProductInput
    resolved: list[ResolvedIngredient]

    @property
    def known(self) -> list[ResolvedIngredient]:
        return [item for item in self.resolved if item.ingredient is not None]

    @property
    def unknown(self) -> list[ResolvedIngredient]:
        return [item for item in self.resolved if item.ingredient is None and item.match_type == "unknown"]


def _json_dict(value) -> dict:
    if not value:
        return {}
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        return json.loads(value)
    return dict(value)


def fetch_interactions(ingredient_ids: Iterable[int]) -> dict[tuple[int, int], list[dict]]:
    ids = sorted(set(ingredient_ids))
    if len(ids) < 2:
        return {}

    with get_cursor() as cur:
        cur.execute(
            """
            SELECT
                interaction_id,
                ingredient_a_id,
                ingredient_b_id,
                interaction_type,
                severity,
                conflict_scope,
                mechanism,
                description,
                source_citation,
                confidence,
                skin_type_modifier
            FROM interactions
            WHERE ingredient_a_id = ANY(%s)
              AND ingredient_b_id = ANY(%s)
            """,
            (ids, ids),
        )
        interactions: dict[tuple[int, int], list[dict]] = {}
        for row in cur.fetchall():
            row = dict(row)
            row["skin_type_modifier"] = _json_dict(row["skin_type_modifier"])
            key = tuple(sorted((row["ingredient_a_id"], row["ingredient_b_id"])))
            interactions.setdefault(key, []).append(row)
        return interactions


def log_interaction_gap(
    ingredient_a_id: int,
    ingredient_b_id: int,
    skin_profile: SkinProfileInput,
) -> None:
    a_id, b_id = sorted((ingredient_a_id, ingredient_b_id))
    with get_cursor() as cur:
        cur.execute(
            """
            SELECT interaction_gap_id
            FROM interaction_gaps
            WHERE ingredient_a_id = %s
              AND ingredient_b_id = %s
              AND user_skin_type IS NOT DISTINCT FROM %s
            """,
            (a_id, b_id, skin_profile.skin_type),
        )
        existing = cur.fetchone()
        if existing:
            cur.execute(
                """
                UPDATE interaction_gaps
                SET query_count = query_count + 1,
                    user_concerns = %s,
                    last_seen = NOW()
                WHERE interaction_gap_id = %s
                """,
                (skin_profile.concerns, existing["interaction_gap_id"]),
            )
            return

        cur.execute(
            """
            INSERT INTO interaction_gaps (
                ingredient_a_id,
                ingredient_b_id,
                user_skin_type,
                user_concerns
            )
            VALUES (%s, %s, %s, %s)
            """,
            (a_id, b_id, skin_profile.skin_type, skin_profile.concerns),
        )


def effective_severity(interaction: dict, skin_profile: SkinProfileInput) -> tuple[str, bool]:
    base = interaction["severity"]
    if (
        interaction["interaction_type"] == "conflict"
        and ESCALATING_CONCERNS.intersection({c.lower() for c in skin_profile.concerns})
    ):
        return "high", base != "high"

    modifier = interaction.get("skin_type_modifier", {}).get(skin_profile.skin_type)
    if modifier in SEVERITY_RANK:
        return modifier, modifier != base
    return base, False


def _pair_key(a: ResolvedIngredient, b: ResolvedIngredient) -> tuple[int, int]:
    assert a.ingredient is not None
    assert b.ingredient is not None
    return tuple(sorted((a.ingredient.id, b.ingredient.id)))


def _pair_product_key(a: ResolvedIngredient, b: ResolvedIngredient, scope: str) -> tuple[int, int, str]:
    key = _pair_key(a, b)
    return key[0], key[1], scope


def _scope_allows(interaction_scope: str, requested_scope: str) -> bool:
    return interaction_scope == "both" or interaction_scope == requested_scope


def _product_payload(product: ProductInput) -> dict:
    payload = asdict(product)
    payload["label"] = product.label
    return payload


def _result_for_interaction(
    interaction: dict,
    ingredient_a: ResolvedIngredient,
    ingredient_b: ResolvedIngredient,
    product_a: ProductInput,
    product_b: ProductInput,
    scope: str,
    skin_profile: SkinProfileInput,
) -> dict:
    severity, modified = effective_severity(interaction, skin_profile)
    return {
        "interaction_id": interaction["interaction_id"],
        "interaction_type": interaction["interaction_type"],
        "severity": severity,
        "base_severity": interaction["severity"],
        "skin_modifier_applied": modified,
        "scope": scope,
        "mechanism": interaction["mechanism"],
        "description": interaction["description"],
        "source_citation": interaction["source_citation"],
        "confidence": interaction["confidence"],
        "ingredient_a": asdict(ingredient_a.ingredient),
        "ingredient_b": asdict(ingredient_b.ingredient),
        "product_a": _product_payload(product_a),
        "product_b": _product_payload(product_b),
    }


def _analyze_pairs(
    product_ingredients: list[ProductIngredients],
    interactions: dict[tuple[int, int], list[dict]],
    skin_profile: SkinProfileInput,
    requested_scope: str,
    seen_unknowns: set[tuple[int, int, str]],
) -> tuple[list[dict], list[dict]]:
    known_results: list[dict] = []
    unknown_pairs: list[dict] = []

    for left, right in itertools.combinations(product_ingredients, 2):
        for ingredient_a in left.known:
            for ingredient_b in right.known:
                if ingredient_a.ingredient.id == ingredient_b.ingredient.id:
                    continue

                pair_key = _pair_key(ingredient_a, ingredient_b)
                matched = [
                    interaction
                    for interaction in interactions.get(pair_key, [])
                    if _scope_allows(interaction["conflict_scope"], requested_scope)
                ]

                if matched:
                    for interaction in matched:
                        known_results.append(
                            _result_for_interaction(
                                interaction,
                                ingredient_a,
                                ingredient_b,
                                left.product,
                                right.product,
                                requested_scope,
                                skin_profile,
                            )
                        )
                    continue

                unknown_key = _pair_product_key(ingredient_a, ingredient_b, requested_scope)
                if unknown_key in seen_unknowns:
                    continue

                seen_unknowns.add(unknown_key)
                log_interaction_gap(
                    ingredient_a.ingredient.id,
                    ingredient_b.ingredient.id,
                    skin_profile,
                )
                unknown_pairs.append(
                    {
                        "scope": requested_scope,
                        "ingredient_a": asdict(ingredient_a.ingredient),
                        "ingredient_b": asdict(ingredient_b.ingredient),
                        "product_a": _product_payload(left.product),
                        "product_b": _product_payload(right.product),
                        "message": "We do not have enough data on this combination yet.",
                    }
                )

    return known_results, unknown_pairs


def _analyze_cross_pairs(
    am_products: list[ProductIngredients],
    pm_products: list[ProductIngredients],
    interactions: dict[tuple[int, int], list[dict]],
    skin_profile: SkinProfileInput,
    seen_unknowns: set[tuple[int, int, str]],
) -> tuple[list[dict], list[dict]]:
    known_results: list[dict] = []
    unknown_pairs: list[dict] = []

    for left in am_products:
        for right in pm_products:
            for ingredient_a in left.known:
                for ingredient_b in right.known:
                    if ingredient_a.ingredient.id == ingredient_b.ingredient.id:
                        continue

                    pair_key = _pair_key(ingredient_a, ingredient_b)
                    matched = [
                        interaction
                        for interaction in interactions.get(pair_key, [])
                        if _scope_allows(interaction["conflict_scope"], "cumulative")
                    ]

                    if matched:
                        for interaction in matched:
                            known_results.append(
                                _result_for_interaction(
                                    interaction,
                                    ingredient_a,
                                    ingredient_b,
                                    left.product,
                                    right.product,
                                    "cumulative",
                                    skin_profile,
                                )
                            )
                        continue

                    unknown_key = _pair_product_key(ingredient_a, ingredient_b, "cumulative")
                    if unknown_key in seen_unknowns:
                        continue

                    seen_unknowns.add(unknown_key)
                    log_interaction_gap(
                        ingredient_a.ingredient.id,
                        ingredient_b.ingredient.id,
                        skin_profile,
                    )
                    unknown_pairs.append(
                        {
                            "scope": "cumulative",
                            "ingredient_a": asdict(ingredient_a.ingredient),
                            "ingredient_b": asdict(ingredient_b.ingredient),
                            "product_a": _product_payload(left.product),
                            "product_b": _product_payload(right.product),
                            "message": "We do not have enough data on this combination yet.",
                        }
                    )

    return known_results, unknown_pairs


def _parse_products(products: list[ProductInput], resolver: IngredientResolver) -> list[ProductIngredients]:
    return [
        ProductIngredients(
            product=product,
            resolved=resolver.resolve_label(
                product.raw_ingredient_list,
                source_product=product.label,
            ),
        )
        for product in products
        if product.raw_ingredient_list.strip()
    ]


def _score(conflicts: list[dict], cautions: list[dict]) -> dict:
    if conflicts:
        high = sum(1 for item in conflicts if item["severity"] == "high")
        medium = sum(1 for item in conflicts if item["severity"] == "medium")
        return {"status": "conflict", "high": high, "medium": medium}
    if cautions:
        return {"status": "caution", "count": len(cautions)}
    return {"status": "clean"}


def analyze_routines(
    am_products: list[ProductInput],
    pm_products: list[ProductInput],
    skin_profile: SkinProfileInput,
) -> dict:
    resolver = get_shared_resolver()
    am_parsed = _parse_products(am_products, resolver)
    pm_parsed = _parse_products(pm_products, resolver)

    all_known_ids = [
        item.ingredient.id
        for product in [*am_parsed, *pm_parsed]
        for item in product.known
        if item.ingredient is not None
    ]
    interactions = fetch_interactions(all_known_ids)
    seen_unknowns: set[tuple[int, int, str]] = set()

    am_results, am_unknowns = _analyze_pairs(
        am_parsed,
        interactions,
        skin_profile,
        "direct",
        seen_unknowns,
    )
    pm_results, pm_unknowns = _analyze_pairs(
        pm_parsed,
        interactions,
        skin_profile,
        "direct",
        seen_unknowns,
    )
    cross_results, cross_unknowns = _analyze_cross_pairs(
        am_parsed,
        pm_parsed,
        interactions,
        skin_profile,
        seen_unknowns,
    )

    known_results = [*am_results, *pm_results, *cross_results]
    conflicts = [item for item in known_results if item["interaction_type"] == "conflict"]
    cautions = [
        item
        for item in known_results
        if item["interaction_type"] in {"caution", "redundant"}
    ]
    synergies = [item for item in known_results if item["interaction_type"] == "synergy"]

    conflicts.sort(key=lambda item: SEVERITY_RANK[item["severity"]], reverse=True)
    cautions.sort(key=lambda item: SEVERITY_RANK[item["severity"]], reverse=True)

    unresolved_tokens = [
        {
            "product": product.product.label,
            "raw_token": item.raw_token,
            "normalized_token": item.normalized_token,
        }
        for product in [*am_parsed, *pm_parsed]
        for item in product.unknown
    ]

    unknown_pair_count = len([*am_unknowns, *pm_unknowns, *cross_unknowns])

    return {
        "overall_score": _score(conflicts, cautions),
        "conflicts": conflicts,
        "cautions": cautions,
        "synergies": synergies,
        "unknown_pair_count": unknown_pair_count,
        "unresolved_tokens": unresolved_tokens,
        "parsed_products": [
            {
                "product": _product_payload(product.product),
                "known_ingredients": [
                    asdict(item.ingredient)
                    for item in product.known
                    if item.ingredient is not None
                ],
                "unknown_tokens": [
                    {
                        "raw_token": item.raw_token,
                        "normalized_token": item.normalized_token,
                    }
                    for item in product.unknown
                ],
            }
            for product in [*am_parsed, *pm_parsed]
        ],
    }


def fetch_gap_backlog(limit: int = 50) -> list[dict]:
    with get_cursor() as cur:
        cur.execute(
            """
            SELECT
                gap.interaction_gap_id,
                a.inci_name AS ingredient_a,
                b.inci_name AS ingredient_b,
                gap.user_skin_type,
                gap.user_concerns,
                gap.query_count,
                gap.status,
                gap.last_seen
            FROM interaction_gaps gap
            JOIN ingredients a ON a.ingridient_id = gap.ingredient_a_id
            JOIN ingredients b ON b.ingridient_id = gap.ingredient_b_id
            ORDER BY gap.query_count DESC, gap.last_seen DESC
            LIMIT %s
            """,
            (limit,),
        )
        return [dict(row) for row in cur.fetchall()]

