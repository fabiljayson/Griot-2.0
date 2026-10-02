"""Material-type classification for Artifact rows.

This lives in the backend rather than being imported from the standalone
`crawler/` package for two reasons:

1. The crawler is a separate deployment target with its own requirements
   (bs4, lxml, httpx) that the Django app does not depend on. Importing across
   that boundary would drag scrape dependencies into the web app.
2. The backfill command needs to classify rows that are already in the
   database, with no crawl JSON in hand. One implementation serves both the
   import path and the backfill path.

Returns `Artifact.Category` values. "other" means "we looked and nothing
matched" — it is a real answer, not a fallback for input we failed to
understand. Callers distinguish those two cases explicitly; see
`resolve_material_type` in the import command.
"""

from .models import Artifact

# Content type = what kind of thing this row is. Mirrors the crawler's
# `config.CONTENT_TYPE_KEYWORDS`; kept in the backend because rows already in
# the database no longer carry the crawler's own classification, and the
# backfill has to re-derive it. The import path prefers the crawler's value
# when the crawl file has one, so this is only authoritative for backfill and
# for older crawl files that predate the split.
CONTENT_TYPE_KEYWORDS: dict[str, list[str]] = {
    Artifact.ContentType.KINGDOM: [
        'kingdom', 'palace', 'sultan', 'sultanate', 'royal court',
        'chief', 'bandjoun', 'baham', 'bangoulap', 'batoufam', 'bamoun',
        'bamileke', 'feudal', 'dynasty',
    ],
    Artifact.ContentType.LANDMARK: [
        'monument', 'memorial', 'statue', 'fountain', 'castle',
        'courthouse', 'temple', 'church', 'mosque', 'bridge', 'museum',
        'waterfall', 'falls', 'national park', 'reserve', 'lagoon',
        'beach', 'mountain', 'cave', 'river',
    ],
    Artifact.ContentType.LEGEND: [
        'legend', 'myth', 'crater lake', 'sacred', 'mystical',
        'magical', 'supernatural', 'spirit', 'ancestral',
    ],
    Artifact.ContentType.CULTURE: [
        'culture', 'tradition', 'festival', 'ceremony', 'language',
        'religion', 'ethnic', 'people', 'pygmy', "ba'aka", 'bayaka',
        'food', 'cuisine', 'music', 'dance', 'craft', 'clothing',
        'language', 'geography', 'climate', 'region', 'zone',
        # Practical travel-guide entries — electricity, visas, currency,
        # driving. Not cultural content in the narrow sense, but they are
        # reference material, not objects, and calling them "other" with an
        # unknown content type hid that.
        'visa', 'currency', 'outlet', 'electricity', 'driver',
        'license', 'gratuity', 'bargaining', 'photography', 'swimming',
        'safety', 'transport', 'accommodation', 'weather',
    ],
}

# Keyword sets per Artifact.Category. Ordered by specificity where two
# categories compete for the same word: "carving" reads as a sculpture unless
# the text also says "mask", and "woven" reads as fabric unless it names a
# garment. Scoring is by hit count with a deterministic tie-break, so the
# ordering here only decides ties, never a clear winner.
MATERIAL_TYPE_KEYWORDS: dict[str, list[str]] = {
    Artifact.Category.SCULPTURE: [
        'sculpture', 'statue', 'statuette', 'carved figure',
        'bas-relief', 'relief', 'effigy', 'figurine',
    ],
    Artifact.Category.INSTRUMENT: [
        'drum', 'xylophone', 'balafon', 'horn', 'flute', 'rattle',
        'musical instrument', 'kenkeni', 'mbira', 'talking drum',
    ],
    Artifact.Category.POTTERY: [
        'pottery', 'pot', 'vase', 'terracotta', 'ceramic',
        'earthenware', 'water jar', 'cooking pot', 'clay pot',
    ],
    Artifact.Category.MASK: [
        'mask', 'masquerade', 'helmet mask', 'wooden mask',
    ],
    Artifact.Category.TEXTILE: [
        'textile', 'embroidered', 'embroidery', 'wrapper', 'garment',
        'attire', 'clothes',
    ],
    Artifact.Category.JEWELRY: [
        'necklace', 'bracelet', 'bead', 'beads', 'earring', 'bangle',
        'jewelry', 'jewellery', 'anklet',
    ],
    Artifact.Category.WEAPON: [
        'spear', 'sword', 'dagger', 'shield', 'knife', 'cutlass',
        'matchet', 'war axe', 'machete',
    ],
    Artifact.Category.FABRIC: [
        'fabric', 'raffia', 'fibre', 'fiber', 'basket', 'weaving',
        'loom', 'woven', 'plaited', 'plait', 'woven mat',
    ],
    Artifact.Category.TOOL: [
        'tool', 'hoe', 'fishing net', 'agricultural implement',
        'farm tool', 'gourd', 'calabash',
    ],
}


def score_material(text: str) -> tuple[str, int]:
    """Return (best_category, hit_count) for `text`.

    The hit count is returned because the caller needs it to judge whether the
    evidence is strong enough. On a long narrative, a single incidental word
    ("pot" in "potato farms", "bead" in "I beads to you") can win a category
    outright, so a best-match without its score is not actionable.
    """
    text_lower = (text or '').lower()
    scores = {
        category: sum(1 for kw in keywords if kw in text_lower)
        for category, keywords in MATERIAL_TYPE_KEYWORDS.items()
    }
    # max over a dict is insertion-ordered, so a tie resolves to the first
    # category declared above rather than to set or hash order.
    best = max(scores, key=scores.get)
    return best, scores[best]


def classify_content_type(text: str, min_score: int = 1) -> str:
    """Return the best-matching `Artifact.ContentType`, or `UNKNOWN`.

    Same substring-scoring approach as `classify_material`. Content type is
    inferred more confidently than material type because "national park" and
    "museum" name a content type directly, whereas material type usually
    needs the object's own description.
    """
    text_lower = (text or '').lower()
    scores = {
        content_type: sum(1 for kw in keywords if kw in text_lower)
        for content_type, keywords in CONTENT_TYPE_KEYWORDS.items()
    }
    best = max(scores, key=scores.get)
    return best if scores[best] >= min_score else Artifact.ContentType.UNKNOWN


def classify_material(text: str, min_score: int = 1) -> str:
    """Return the best-matching `Artifact.Category`, or `Category.OTHER`.

    Matching is a substring test over the lowercased text, which is crude but
    predictable and — unlike a tokeniser — handles the multi-word keywords
    that carry most of the signal ('talking drum', 'helmet mask'). It also
    matches inside longer words ('pot' in 'pottery'), which is deliberate
    over-triggering: with no real corpus to tune against, over-triggering is
    safer than losing an artifact to a missed keyword.

    `min_score` raises the evidence bar for callers working from thin or noisy
    text. The import path can pass the crawler's own classification and so
    uses the default; the backfill, which only has stored prose, should raise
    it — see the note in `reclassify_artifacts`.
    """
    category, score = score_material(text)
    return category if score >= min_score else Artifact.Category.OTHER


def classification_text(*parts: str | None) -> str:
    """Join the fields worth classifying on, dropping the empty ones.

    Title alone is usually too terse to classify from, so callers pass the
    narrative fields too. Empty strings are dropped rather than joined, which
    keeps a run of separators out of the text and avoids a stray separator
    being the thing that matched a keyword.
    """
    return ' '.join(part for part in parts if part)