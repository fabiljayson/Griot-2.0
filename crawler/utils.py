"""Text helpers for slugging, categorizing, and cleaning extracted content."""

import re
import unicodedata
from urllib.parse import urlparse

import config


def slugify(text: str) -> str:
    """Convert text to a URL/file-safe slug."""
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    text = re.sub(r"-+", "-", text)
    return text.strip("-")[:80]


def _best_match(text_lower: str, keywords_by_label: dict[str, list[str]], default: str) -> str:
    """Return the label whose keywords hit most often, or `default`.

    `max` over a dict is insertion-ordered, so a tie resolves to the first
    label declared in the config rather than to set/hash order. That keeps
    classification deterministic across runs and interpreter versions.
    """
    scores = {
        label: sum(1 for kw in keywords if kw in text_lower)
        for label, keywords in keywords_by_label.items()
    }
    best = max(scores, key=scores.get)
    return best if scores[best] > 0 else default


def classify_content_type(text: str) -> str:
    """Classify what kind of page this is: Kingdom, Landmark, Artifact, Legend, Culture."""
    return _best_match(text.lower(), config.CONTENT_TYPE_KEYWORDS, "Culture")


def classify_material_type(text: str) -> str:
    """Classify what the object is, as a qr_codes.Artifact.Category value.

    Returns "other" when nothing matches — which is a real answer meaning
    "not enough signal", and is why the backend counts it rather than
    treating it as a fallback for values it failed to understand.
    """
    return _best_match(text.lower(), config.MATERIAL_TYPE_KEYWORDS, "other")


def get_location_from_url(url: str) -> str:
    """Infer location from the page URL path."""
    path = urlparse(url).path.lower()
    for key, loc in config.REGION_LOCATIONS.items():
        if key in path:
            return loc
    return "Cameroon"


def is_skip_heading(text: str) -> bool:
    """Check if a heading should be skipped (footer/nav)."""
    return text.lower().strip() in config.SKIP_HEADINGS or len(text.strip()) < 3


def clean_description(text: str) -> str:
    """Remove footer/navigation artifacts and clean description text."""
    if not text:
        return text

    # Patterns to remove (footer text, navigation, placeholders)
    footer_patterns = [
        r"Follow & Like us.*",
        r"Facebook.*Instagram.*Twitter.*",
        r"Discover our tours.*",
        r"Book your tours.*",
        r"Our Products.*",
        r"Our Tours.*",
        r"Contact - Us.*",
        r"Contact Us.*",
        r"Privacy Policy.*",
        r"Terms & Conditions.*",
        r"Impressum.*",
        r"Languages.*",
        r"Français.*",
        r"English.*",
        r"Deutsch.*",
        r"XXXXXX.*",
        r"XXX.*",
    ]

    for pattern in footer_patterns:
        text = re.sub(pattern, "", text, flags=re.IGNORECASE | re.DOTALL)

    # Remove multiple newlines and clean whitespace
    text = re.sub(r"\n{3,}", "\n\n", text)
    text = re.sub(r"\s{2,}", " ", text)
    text = text.strip()

    return text


def summarize_description(text: str, max_length: int = 240) -> str:
    """Return a concise lead description while keeping source wording intact."""
    cleaned = clean_description(text)
    if not cleaned:
        return ""

    normalized = re.sub(r"\s+", " ", cleaned)
    sentences = re.split(r"(?<=[.!?])\s+", normalized)
    summary_parts = []

    for sentence in sentences:
        sentence = sentence.strip()
        if not sentence:
            continue
        candidate = " ".join([*summary_parts, sentence])
        if len(candidate) > max_length:
            break
        summary_parts.append(sentence)
        if len(summary_parts) == 2 or len(candidate) >= 120:
            break

    if summary_parts:
        return " ".join(summary_parts)

    excerpt = normalized[:max_length].rsplit(" ", 1)[0].rstrip(" ,;:-")
    return f"{excerpt}..." if len(excerpt) < len(normalized) else excerpt


def trim_description(text: str, max_length: int = 1500) -> str:
    """Trim description to a reasonable length, preserving complete sentences."""
    if not text or len(text) <= max_length:
        return text

    # Find a good breaking point (end of sentence)
    trimmed = text[:max_length]
    last_period = trimmed.rfind(".")
    last_newline = trimmed.rfind("\n")

    # Use the last sentence end or paragraph break
    break_point = max(last_period, last_newline)
    if break_point > max_length * 0.7:  # At least 70% of max_length
        return trimmed[:break_point + 1].strip()

    return trimmed.strip() + "..."


def infer_location(text: str) -> str:
    """Try to infer a more specific location from text content."""
    text_lower = text.lower()
    location_hints = [
        ("foumban", "Foumban, West Region"),
        ("douala", "Douala, Littoral Region"),
        ("limbe", "Limbe, Southwest Region"),
        ("buea", "Buea, Southwest Region"),
        ("bamenda", "Bamenda, Northwest Region"),
        ("kribi", "Kribi, South Region"),
        ("yaoundé", "Yaoundé, Centre Region"),
        ("yaounde", "Yaoundé, Centre Region"),
        ("garoua", "Garoua, North Region"),
        ("rhumsiki", "Rhumsiki, Far North Region"),
        ("bertoua", "Bertoua, East Region"),
        ("dschang", "Dschang, West Region"),
        ("ngaoundéré", "Ngaoundéré, Adamawa Region"),
        ("mount cameroon", "Mount Cameroon, Southwest Region"),
        ("bandjoun", "Bandjoun, West Region"),
        ("baham", "Baham, West Region"),
        ("bangoulap", "Bangoulap, West Region"),
        ("bimbia", "Bimbia, Southwest Region"),
        ("korup", "Korup National Park, Southwest Region"),
        ("kribi", "Kribi, South Region"),
        ("djé", "Dja Reserve, South Region"),
        ("loéké", "Lobéké National Park, Southeast Region"),
    ]
    for hint, loc in location_hints:
        if hint in text_lower:
            return loc
    return "Cameroon"