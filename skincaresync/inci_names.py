"""Display formatting for INCI names.

Upstream regulatory data stores INCI names in upper case, exactly as they appear
on product packaging. We keep the database faithful to the source and format for
display at the serialization boundary, so search and comparison always operate on
the authentic value.
"""

import re

# Tokens that must keep their exact upper-case form: polymer/chemical prefixes,
# regulatory prefixes and common abbreviations found in INCI nomenclature.
_ACRONYMS = {
    "AMP", "AMPD", "BHA", "BHT", "CI", "DEA", "DMDM", "EDTA", "HC", "HEDTA",
    "HDI", "IPBC", "MDI", "MEA", "MIPA", "PABA", "PCA", "PEG", "PPG", "PTFE",
    "PVM", "PVP", "SD", "SLES", "SLS", "TBHQ", "TEA", "TIPA", "VA", "VP",
    "MSM", "TEPA", "THPE", "UV", "PG", "PPT", "ATP", "DNA", "RNA", "CoA",
}

# Prefixes conventionally written in lower case (recombinant/synthetic peptides).
_LOWER_PREFIXES = {"sh", "rh", "sr", "hr"}

_SEPARATORS = re.compile(r"([\s/\\(),\-]+)")


def _format_word(word: str) -> str:
    if not word:
        return word

    upper = word.upper()
    if upper in _ACRONYMS:
        return upper
    if word.lower() in _LOWER_PREFIXES:
        return word.lower()

    # Anything carrying a digit is a chemical designator (PEG-40, C20-40,
    # Oligopeptide-143, CI 77491) — preserve it verbatim.
    if any(char.isdigit() for char in word):
        return upper if word.isupper() else word

    if len(word) <= 2 and word.isupper():
        return upper

    return word[0].upper() + word[1:].lower()


def display_inci_name(name: str) -> str:
    """Render an upper-case INCI name in readable title case.

    Chemical designators, acronyms and peptide prefixes are preserved:

    >>> display_inci_name("PEG-40 HYDROGENATED CASTOR OIL")
    'PEG-40 Hydrogenated Castor Oil'
    >>> display_inci_name("SODIUM C14-16 OLEFIN SULFONATE")
    'Sodium C14-16 Olefin Sulfonate'
    >>> display_inci_name("Ascorbic Acid")
    'Ascorbic Acid'
    """
    if not name:
        return ""

    # Names that are already mixed case were curated by hand; leave them alone.
    if not name.isupper():
        return name

    return "".join(
        part if _SEPARATORS.fullmatch(part) else _format_word(part)
        for part in _SEPARATORS.split(name)
    )
