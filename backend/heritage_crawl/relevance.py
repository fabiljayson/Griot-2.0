"""Deciding whether a page is about Cameroonian cultural heritage.

§8 is explicit that this must not be keyword-only: "Do not rely only on
keywords. Use the page context to determine whether the information is actually
relevant." So the score here is a weighted blend rather than a hit count, and
the two conditions that matter most are structural:

* **Cameroonian-ness is mandatory, not additive.** A page about Greek
  pottery has `museum`, `artefact` and `sculpture` all over it. If the page is
  not about Cameroon, it is not relevant to this corpus no matter how many
  heritage words it contains, so a missing Cameroon signal caps the score
  below every threshold anyone would configure.
* **A primary-source institutional origin counts.** A page on `ich.unesco.org`
  about a Cameroonian element is relevant on provenance grounds even when its
  prose is thin — the page *is* the record.

The cultural-group and region detection below is deliberately conservative.
§9 says "Do not infer a cultural group merely from the geographical location",
so groups are only ever returned when the source text names them.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# --- Cameroon regions (§9). Spellings as sources actually use them. ---
#: Region names in both official languages. The French names are not optional
#: decoration: MINAC, Musécam and most museum pages are written in French, and
#: a detector that only knows "West" cannot find "l'Ouest" — it would silently
#: leave `region` empty on exactly the authoritative sources most likely to
#: state it.
REGIONS: dict[str, str] = {
    'adamaoua': 'Adamawa',
    'adamaoua (adamawa)': 'Adamawa',
    'centre': 'Centre',
    'est': 'East',
    'east': 'East',
    'extrême nord': 'Far North',
    'extreme nord': 'Far North',
    'far north': 'Far North',
    'littoral': 'Littoral',
    'nord': 'North',
    'nord-ouest': 'North-West',
    'nord-ouest (north-west)': 'North-West',
    'north': 'North',
    'north-west': 'North-West',
    'northwest': 'North-West',
    'ouest': 'West',
    'west': 'West',
    'south': 'South',
    'sud': 'South',
    'sud-est': 'South',
    'sud-ouest': 'South-West',
    'sud-ouest (south-west)': 'South-West',
    'south-east': 'South',
    'south-east (sud-est)': 'South',
    'south-west': 'South-West',
    'southwest': 'South-West',
}

# --- Cultural groups. Only matched when the text names them. ---
CULTURAL_GROUPS: dict[str, tuple[str, ...]] = {
    'Bamileke': ('bamileke', 'bamiléké', 'bamileques', 'bamiléké'),
    'Bamoun': ('bamoun',),
    'Bangwa': ('bangwa', 'bangoua'),
    'Beti': ('beti', 'betsi', 'beti-fang', 'fang-beti'),
    'Bulu': ('bulu',),
    'Bassa': ('bassa', 'bakweri-kwe', 'kwe'),
    'Mafa': ('mafa',),
    'Mambila': ('mambila', 'mambilé'),
    'Tikar': ('tikar',),
    'Kabre': ('kabre', 'kabrè'),
    'Anyi': ('anyi', "anyi'a"),
    'Gbaya': ('gbaya',),
    'Baka': ('baka', "ba'aka", 'baaka', 'baka pygmy'),
    'Bedik': ('bedik', 'bedik'),
    'Koma': ('koma',),
    'Moghamo': ('moghamo', 'moghamao'),
    'Django': ('django', 'djangwé'),
    'Ejagham': ('ejagham', 'ejagham'),
    'Keaka': ('keaka',),
    'Kaka': ('kaka',),
    'Kossindo': ('kossindo',),
    'Bokworong': ('bokworong', 'bokworong'),
}

#: Language names that appear in Cameroonian heritage writing.
LANGUAGES: dict[str, str] = {
    'fulfulde': 'Fula',
    'fula': 'Fula',
    'bamileke': 'Bamileke',
    'bamiléké': 'Bamileke',
    'ewondo': 'Ewondo',
    'duala': 'Duala',
    'bassa': 'Bassa',
    'kikuyu': 'Kikuyu',
    'mboum': 'Mboum',
    'maka': 'Maka',
    'ngoin': 'Ngoin',
    'mendi': 'Mendi',
    'nogui': 'Nogui',
    'bafia': 'Bafia',
    'mambila': 'Mambila',
    'vute': 'Vute',
    'sango': 'Sango',
    'yemba': 'Yemba',
}

#: §8 signal terms, grouped so their weights can be reasoned about.
COUNTRY_TERMS = (
    'cameroon', 'cameroonian', 'cameroon\'s', 'republique du cameroun',
    'cameroun', 'cameroons',
)

STRONG_HERITAGE_TERMS = (
    'intangible cultural heritage', 'oral tradition', 'folklore', 'folktale',
    'folktales', 'heritage site', 'cultural heritage', 'traditional practice',
    'archaeological', 'archaeology', 'ethnographic', 'anthropological',
    'world heritage', 'masterpiece of the oral',
)

MEDIUM_HERITAGE_TERMS = (
    'tradition', 'traditional', 'ritual', 'ceremony', 'legend', 'myth',
    'folklore', 'ancestral', 'heritage', 'custom', 'indigenous', 'ethnic',
    'sacred', 'ancestor', 'lineage', 'taboo', 'festival', 'mask', 'masquerade',
    'sculpture', 'carving', 'pottery', 'textile', 'musical instrument',
    'drum', 'artifact', 'artefact', 'museum', 'cultural group', 'language',
    'agroforestry', 'craft', 'weaving', 'beadwork', 'mansion', 'palace',
)

#: Institutional provenance: these hosts are records in their own right.
SOURCE_HOSTS = ('unesco.org', 'musecam.org', 'minac.gov.cm', 'minac-gouv.com',
                'cameroon-nationalmuseum.cm')


@dataclass
class RelevanceResult:
    score: float
    is_cameroonian: bool
    reasons: list[str] = field(default_factory=list)
    region: str = ''
    cultural_groups: list[str] = field(default_factory=list)
    languages: list[str] = field(default_factory=list)
    content_types: list[str] = field(default_factory=list)


def _count(text: str, terms) -> int:
    return sum(1 for term in terms if term in text)


def detect_region(text: str) -> str:
    """First region named in the text, or ''.

    Order matters only for tie-breaking: longer/more specific labels are tested
    first so "South-West" is not read as "South".
    """
    for needle in sorted(REGIONS, key=len, reverse=True):
        if re.search(rf'\b{re.escape(needle)}\b', text, re.I):
            return REGIONS[needle]
    return ''


def detect_cultural_groups(text: str) -> list[str]:
    """Groups the text explicitly names. Never inferred from location (§9)."""
    found = []
    for canonical, variants in CULTURAL_GROUPS.items():
        for variant in variants:
            if re.search(rf'\b{re.escape(variant)}\b', text, re.I):
                found.append(canonical)
                break
    return sorted(set(found))


def detect_languages(text: str) -> list[str]:
    found = set()
    for needle, canonical in LANGUAGES.items():
        if re.search(rf'\b{re.escape(needle)}\b', text, re.I):
            found.add(canonical)
    return sorted(found)


def classify_content_types(text: str) -> list[str]:
    """What kind of heritage record this looks like.

    Reuses the vocabulary of `qr_codes.Artifact.ContentType` and `Story` so the
    value can be stored without inventing a parallel taxonomy.
    """
    rules = {
        'artifact': ('artefact', 'artifact', 'mask', 'sculpture', 'carving',
                     'pottery', 'textile', 'statue', 'object'),
        'heritage_site': ('heritage site', 'monument', 'memorial', 'museum',
                          'archaeological site', 'ruins', 'palace', 'temple',
                          'national park'),
        'legend': ('legend', 'myth', 'folklore', 'tale', 'story of'),
        'tradition': ('tradition', 'ritual', 'ceremony', 'festival',
                      'custom', 'practice'),
        'music': ('music', 'song', 'drum', 'chant', 'musical instrument',
                  'xylophone', 'balafon'),
        'oral_history': ('oral history', 'oral tradition', 'storytelling',
                         'griot', 'narrative'),
        'language': ('language', 'linguistic', 'dialect'),
        'cuisine': ('food', 'cuisine', 'dish', 'recipe', 'culinary'),
    }
    return sorted(
        name for name, terms in rules.items() if any(term in text for term in terms)
    )


def score_page(
    *,
    title: str,
    body: str,
    description: str = '',
    url: str = '',
) -> RelevanceResult:
    """Score a page 0.0-1.0 for "Cameroonian cultural heritage".

    The weights are chosen so that the three signals §8 lists are separable:

    * Cameroonian-ness 0.45 — required. Without it the score is capped at 0.49,
      below every realistic threshold, which is how a well-written page about
      somewhere else gets rejected rather than marginalised.
    * Strong heritage terms 0.30 — the specific vocabulary of §8.
    * Medium heritage terms 0.20, saturating — a page can mention "traditional"
      four times without being about tradition.
    * Institutional provenance 0.15 — a UNESCO or ministry page is a record.
    * Structural bonus — a description and a non-trivial body both indicate a
      real page rather than an index or a redirect stub.
    """
    haystack = f'{title} {description} {body}'.lower()
    reasons: list[str] = []

    country_hits = _count(haystack, COUNTRY_TERMS)
    on_institutional_host = any(host in url.lower() for host in SOURCE_HOSTS)

    # Cameroonian-ness is a property of the *text*, never of the host.
    #
    # The earlier version also accepted an institutional host as proof, which
    # imported a Musécam or MINAC page whose subject was Mali or Nigeria --
    # §2 says not to import unrelated African or international content "unless
    # the source clearly establishes a connection to Cameroon", and a Cameroian
    # website is not that connection. A national museum's page on a neighbouring
    # country's tradition is real and correctly labelled, and it is not
    # Cameroonian heritage.
    #
    # The host still earns the institutional-provenance bonus below, so a
    # genuine Cameroonian page that never spells out the country keeps its
    # chance through the capped path rather than through a false claim.
    is_cameroonian = country_hits > 0
    if is_cameroonian:
        reasons.append('references Cameroon')
    elif on_institutional_host:
        reasons.append('Cameroonian source, but the page does not mention Cameroon')
    else:
        reasons.append('no Cameroon reference')

    strong_hits = _count(haystack, STRONG_HERITAGE_TERMS)
    medium_hits = _count(haystack, MEDIUM_HERITAGE_TERMS)

    score = 0.0
    if is_cameroonian:
        score += 0.45
        if country_hits > 2:
            score += 0.05
            reasons.append('Cameroon mentioned repeatedly')

    score += min(strong_hits * 0.10, 0.30)
    if strong_hits:
        reasons.append(f'{strong_hits} strong heritage term(s)')

    score += min(medium_hits * 0.05, 0.20)
    if medium_hits:
        reasons.append(f'{medium_hits} supporting heritage term(s)')

    if on_institutional_host:
        score += 0.15
        reasons.append('institutional source')

    if description:
        score += 0.05
        reasons.append('has a description')
    if len(body) > 600:
        score += 0.05
        reasons.append('substantial body text')

    if not is_cameroonian:
        # Cap rather than zero: a genuinely Cameroonian page that fails to spell
        # the country out (a museum's artefact page, say) should still be able
        # to clear a low threshold on institutional provenance alone. But it
        # must not clear a normal one.
        score = min(score, 0.49)
        reasons.append('capped: not demonstrably Cameroonian')

    return RelevanceResult(
        score=round(min(score, 1.0), 4),
        is_cameroonian=is_cameroonian,
        reasons=reasons,
        region=detect_region(haystack),
        cultural_groups=detect_cultural_groups(haystack),
        languages=detect_languages(haystack),
        content_types=classify_content_types(haystack),
    )


def is_relevant(result: RelevanceResult, threshold: float) -> bool:
    return result.is_cameroonian and result.score >= threshold