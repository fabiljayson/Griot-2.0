"""Cultural Trust Score — strength of the available verification evidence.

The score answers "how well is this account documented?", never "how likely
is it to be true?". It is the weighted sum of the evidence criteria a
reviewer has confirmed, over a configurable weight table (settings
`TRUST_SCORE_WEIGHTS`), so a partial review scores a defensible partial
number instead of a binary claim.

Weighting lives in settings rather than here so operators can retune it
without a code change; the defaults below are the presentation-approved
table (25/25/25/15/10 = 100).
"""

from django.conf import settings

#: The evidence criteria, in display order. Each maps 1:1 to a boolean field
#: on `StoryVerification`; adding one requires a weight in the settings
#: table and a field on the model — nothing else.
CRITERIA = (
    'source_verified',
    'community_validated',
    'expert_validated',
    'references_confirmed',
    'consistency_confirmed',
)

DEFAULT_WEIGHTS = {
    'source_verified': 25,
    'community_validated': 25,
    'expert_validated': 25,
    'references_confirmed': 15,
    'consistency_confirmed': 10,
}

#: Score bands shown to readers. "verified" here means the evidence is
#: strong — it is a label on the documentation, not a truth claim.
DEFAULT_LEVELS = {'verified': 70, 'partial': 30}


def get_weights() -> dict:
    """The active weight table, falling back to the defaults per-key.

    A misconfigured or partially configured settings override degrades to
    the default weight for the missing keys rather than dropping them to
    zero — an operator typo must not silently zero half the score.
    """
    configured = getattr(settings, 'TRUST_SCORE_WEIGHTS', None) or {}
    weights = dict(DEFAULT_WEIGHTS)
    for key in CRITERIA:
        value = configured.get(key)
        if isinstance(value, (int, float)) and 0 <= value <= 100:
            weights[key] = int(value)
    return weights


def calculate_trust_score(evidence) -> int:
    """Weighted sum of the confirmed criteria, clamped to 0-100.

    `evidence` is anything attribute- or key-accessible holding booleans —
    a `StoryVerification` row or a plain dict.
    """
    weights = get_weights()
    total = 0
    for criterion in CRITERIA:
        if _read(evidence, criterion):
            total += weights[criterion]
    return max(0, min(100, total))


def trust_level(score: int) -> str:
    """Map a score to the reader-facing band.

    Returns one of ``unverified`` (no/faint evidence), ``partial``
    (some evidence recorded) or ``verified`` (strong evidence).
    """
    levels = getattr(settings, 'TRUST_LEVEL_THRESHOLDS', None) or {}
    verified_at = levels.get('verified', DEFAULT_LEVELS['verified'])
    partial_at = levels.get('partial', DEFAULT_LEVELS['partial'])
    if score >= verified_at:
        return 'verified'
    if score >= partial_at:
        return 'partial'
    return 'unverified'


def score_breakdown(evidence) -> list:
    """Per-criterion detail for the review UI: what counted, and how much.

    Returns a list of ``{criterion, label, weight, confirmed}`` dicts in
    display order so the reviewer sees exactly which levers move the score.
    """
    weights = get_weights()
    labels = {
        'source_verified': 'Reliable/documented source',
        'community_validated': 'Community validation',
        'expert_validated': 'Cultural expert/reviewer validation',
        'references_confirmed': 'Historical/reference evidence',
        'consistency_confirmed': 'Content consistency',
    }
    return [
        {
            'criterion': criterion,
            'label': labels[criterion],
            'weight': weights[criterion],
            'confirmed': bool(_read(evidence, criterion)),
        }
        for criterion in CRITERIA
    ]


def _read(evidence, key: str) -> bool:
    """Read a criterion from an object or mapping without raising."""
    if isinstance(evidence, dict):
        return bool(evidence.get(key))
    return bool(getattr(evidence, key, False))
