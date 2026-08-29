"""Pull a published INCI list out of a brand product page.

We only keep text that already looks like an ingredient declaration.
Marketing copy, key-ingredient callouts, and Shopify metaobject IDs are dropped.
"""

from __future__ import annotations

import html
import json
import re

from .published_labels import normalize_published_inci

BASE_HINTS = (
    "aqua",
    "glycerin",
    "dimethicone",
    "squalane",
    "propanediol",
    "butylene glycol",
    "alcohol denat",
    "dipropylene glycol",
    "methylpropanediol",
    "caprylic/capric",
    "coconut alkanes",
    "isopropyl myristate",
    "cyclopentasiloxane",
)

INCI_HINTS = BASE_HINTS + (
    "phenoxyethanol",
    "1,2-hexanediol",
    "caprylic",
    "hyaluronate",
    "hyaluronic acid",
    "niacinamide",
    "tocopherol",
    "carbomer",
    "ethylhexylglycerin",
    "caprylyl glycol",
    "xanthan",
    "centella",
    "snail secretion",
    "ascorbic",
    "ascorbyl",
    "panthenol",
    "ethylhexyl methoxycinnamate",
    "titanium dioxide",
    "zinc oxide",
    "isomalt",
)

BAD_SNIPPETS = (
    "add to cart",
    "free shipping",
    "click here",
    "lorem ipsum",
    "gid://shopify",
    "do not add this product",
    "subscribe",
    "write a review",
    "amino acid derivative",
    "click an ingredient",
    "rating:",
    "categories:",
    "texture-enhancer",
    "spreadabilty",
    "skin-conditioner",
    "decoded carrier",
    "\\u003c",
    "\u003c",
)

HEADING_RE = re.compile(
    r"(?:all\s+ingredients|full\s+ingredients?(?:\s+list)?|ingredient\s+list|"
    r"complete\s+ingredients?|inci)\b",
    re.IGNORECASE,
)
JSON_KEY_RE = re.compile(
    r'"(ingredients|ingredient_list|full_ingredients|inci|ingredientList)"\s*:\s*"((?:\\.|[^"\\]){20,8000})"',
    re.IGNORECASE,
)
METAFIELD_RE = re.compile(
    r'class="[^"]*metafield-(?:multi_line_text_field|rich_text_field)[^"]*"[^>]*>(.*?)</(?:span|div|p)>',
    re.IGNORECASE | re.DOTALL,
)
DETAILS_RE = re.compile(
    r"<summary[^>]*>\s*(?:<span[^>]*>)?\s*(?:ingredient list|ingredients|full ingredients?)\s*"
    r"(?:</span>)?\s*</summary>\s*(.*?)</details>",
    re.IGNORECASE | re.DOTALL,
)
FULL_LIST_RE = re.compile(
    r"full ingredient list:\s*(?:</strong>)?\s*(?:&nbsp;|<br\s*/?>|\s)*([^<]{20,8000})",
    re.IGNORECASE,
)
TABLE_ING_RE = re.compile(
    r"(?:<th[^>]*>|<td[^>]*>)\s*ingredients\s*</t[hd]>\s*<td[^>]*>(.*?)</td>",
    re.IGNORECASE | re.DOTALL,
)
JSONLD_ING_RE = re.compile(
    r'"name"\s*:\s*"Ingredients"\s*,\s*"value"\s*:\s*"((?:\\.|[^"\\]){20,8000})"',
    re.IGNORECASE,
)
ATTR_ING_RE = re.compile(
    r'data-(?:original-)?ingredients="([^"]{20,8000})"',
    re.IGNORECASE,
)
INACTIVE_RE = re.compile(
    r"inactive\s+ingredients\s*:?\s*",
    re.IGNORECASE,
)
FULL_IL_RE = re.compile(r"full\s+il\s*:?\s*", re.IGNORECASE)
ING_CLASS_RE = re.compile(
    r'class="[^"]*ingredients?(?:-content)?[^"]*"[^>]*>(.*?)</div>',
    re.IGNORECASE | re.DOTALL,
)
PERCENT_ROW_RE = re.compile(
    r"([A-Za-z][A-Za-z0-9 /'().+\-]{1,80}?)\s*[-–—]\s*\d+(?:\.\d+)?\s*%",
)
SOLVENT_RE = re.compile(r"(?:^|,)\s*(?:aqua|water)\b", re.IGNORECASE)
AQUA_LIST_RE = re.compile(
    r"((?:Aqua|Water)\s*(?:\([^)]{0,60}\))?(?:\s*/\s*(?:Water|Aqua|Eau))*\s*,\s*[A-Za-z][^<]{60,6000})",
    re.IGNORECASE,
)
TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"\s+")


def _strip_html(blob: str) -> str:
    text = TAG_RE.sub(" ", blob or "")
    text = html.unescape(text)
    return WS_RE.sub(" ", text).strip(" \n\t:;,-")


def _json_string(value: str) -> str:
    try:
        return json.loads(f'"{value}"')
    except json.JSONDecodeError:
        return value.replace(r"\/", "/").replace(r"\n", " ").replace(r"\"", '"')


def _truncate_disclaimer(text: str) -> str:
    cut_markers = (
        ". Learn more",
        ". We strive",
        ". Due to",
        "shown here may vary",
        "ingredients subject to change",
        "please refer to the",
        "for the most complete",
        "please consult the product packaging",
        "*for the most",
        "for external use",
        "consult your",
        "healthcare provider",
        "avoid contact",
        "while summer fridays",
        "we cannot guarantee",
    )
    lowered = text.lower()
    cut_at = len(text)
    for marker in cut_markers:
        idx = lowered.find(marker)
        if 40 <= idx < cut_at:
            cut_at = idx
    text = text[:cut_at]
    sentence = re.search(
        r"\.\s+(?:Learn|We |Due |Please |This |Our |For informational)",
        text,
    )
    if sentence and sentence.start() > 40:
        text = text[: sentence.start()]
    return text.strip(" .;")


def _clean_candidate(text: str) -> str:
    raw = text or ""
    raw = re.sub(r"\\u([0-9a-fA-F]{4})", lambda match: chr(int(match.group(1), 16)), raw)
    raw = html.unescape(raw)
    raw = _strip_html(raw)
    raw = re.sub(r"^/?[a-z][a-z0-9]*\s*>\s*", "", raw, flags=re.IGNORECASE)
    raw = re.sub(r"^(?:inactive|active)\s+ingredients?\s*:?\s*", "", raw, flags=re.IGNORECASE)
    return _truncate_disclaimer(raw)


def _has_base(normalized: str) -> bool:
    low = normalized.lower()
    if any(hint in low for hint in BASE_HINTS):
        return True
    return bool(SOLVENT_RE.search(low))


def _percent_table_lists(page_html: str) -> list[str]:
    text = TAG_RE.sub("\n", page_html or "")
    text = html.unescape(text)
    names: list[str] = []
    for match in PERCENT_ROW_RE.finditer(text):
        name = WS_RE.sub(" ", match.group(1)).strip(" \n\t:-")
        if len(name) < 3 or name.casefold() in {"key ingredients", "nothing to hide"}:
            continue
        names.append(name)
    if len(names) < 4:
        return []
    return [", ".join(names)]


def looks_like_inci(text: str) -> bool:
    raw = (text or "").strip()
    if len(raw) < 20:
        return False
    low = raw.lower()
    if any(bad in low for bad in BAD_SNIPPETS):
        return False
    # Em-dash blurbs ("ECTOIN — an amino acid...") are marketing, not INCI.
    if "—" in raw and not SOLVENT_RE.search(raw):
        return False
    if raw.count(".") >= 3:
        return False
    normalized = normalize_published_inci(raw)
    parts = [part.strip() for part in normalized.split(",") if part.strip()]
    if len(parts) < 4 or len(parts) > 160:
        return False
    hint_hits = sum(1 for hint in INCI_HINTS if hint in normalized.lower())
    has_base = _has_base(normalized)
    # Short "key ingredient" callouts almost never include a base/solvent.
    if len(parts) < 8 and not has_base:
        return False
    return has_base or (len(parts) >= 10 and hint_hits >= 2)


def extract_inci_from_html(page_html: str) -> str | None:
    if not page_html:
        return None
    candidates: list[str] = []

    for match in ATTR_ING_RE.finditer(page_html):
        candidates.append(html.unescape(match.group(1)))
    for match in JSON_KEY_RE.finditer(page_html):
        candidates.append(_json_string(match.group(2)))
    for match in JSONLD_ING_RE.finditer(page_html):
        candidates.append(_json_string(match.group(1)))
    for match in METAFIELD_RE.finditer(page_html):
        candidates.append(_strip_html(match.group(1)))
    for match in DETAILS_RE.finditer(page_html):
        candidates.append(_strip_html(match.group(1)))
    for match in FULL_LIST_RE.finditer(page_html):
        candidates.append(_strip_html(match.group(1)))
    for match in TABLE_ING_RE.finditer(page_html):
        candidates.append(_strip_html(match.group(1)))
    for match in ING_CLASS_RE.finditer(page_html):
        candidates.append(_strip_html(match.group(1)))
    for match in INACTIVE_RE.finditer(page_html):
        candidates.append(_strip_html(page_html[match.end() : match.end() + 4000]))
    for match in FULL_IL_RE.finditer(page_html):
        candidates.append(_strip_html(page_html[match.end() : match.end() + 4000]))
    candidates.extend(_percent_table_lists(page_html))
    for match in AQUA_LIST_RE.finditer(page_html):
        candidates.append(match.group(1))

    for match in HEADING_RE.finditer(page_html):
        window = page_html[match.end() : match.end() + 20000]
        window = re.sub(r"^[\s:<\-–]*", "", window)
        candidates.append(_strip_html(window[:8000]))
        for block in re.finditer(
            r"<(?:p|div|span|td|li)[^>]*>(.{20,6000}?)</(?:p|div|span|td|li)>",
            window,
            re.IGNORECASE | re.DOTALL,
        ):
            text = _strip_html(block.group(1))
            if text.count(",") >= 4:
                candidates.append(text)

    viable: list[str] = []
    seen: set[str] = set()
    for candidate in candidates:
        cleaned = _clean_candidate(candidate)
        if not looks_like_inci(cleaned):
            continue
        normalized = normalize_published_inci(cleaned)
        key = normalized.casefold()
        if key in seen:
            continue
        seen.add(key)
        viable.append(normalized)
    if not viable:
        return None
    return max(
        viable,
        key=lambda text: (
            sum(1 for hint in INCI_HINTS if hint in text.lower()),
            len(text.split(",")),
        ),
    )
