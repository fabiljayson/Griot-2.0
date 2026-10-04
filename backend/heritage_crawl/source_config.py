"""The built-in source registry.

Sources are configuration, not code (§1: "Do not hard-code the crawler around
only these websites"). This module is only the *seed* — what
`manage.py crawl_seed_sources` writes into `CrawlSource` on first run.
After that the database is the source of truth and an administrator can add a
museum without a deploy.

Two things about this list are deliberate and worth knowing before editing it:

**Licensing is unknown for most of these.** §6 forbids copying copyrighted
material and requires media reuse permission to be established before
redistribution. None of the museums, ministries or UNESCO collections in this
registry publishes an explicit reuse licence for its page text, so
`allow_media_download` is False everywhere and `default_licence` is
`undetermined`. That is the honest state, not an oversight — it means the
crawler records *that* an image exists, where it lives and who to credit, and
leaves the decision to a human. Setting `allow_media_download=True` is a
statement that you have checked that specific source's terms.

**`max_pages` is small on purpose.** §14 says do not crawl aggressively. These
are small government and museum sites; a deep crawl is both impolite and a good
way to get the crawler blocked, which would cost the project the source.
"""

from dataclasses import dataclass

from .models import CrawlSource


@dataclass(frozen=True)
class SeedSource:
    """A source to write into the database on first run."""

    slug: str
    name: str
    base_url: str
    source_type: str
    reliability: str
    seed_urls: tuple[str, ...] = ()
    allowed_domains: tuple[str, ...] = ()
    seed_urls: tuple[str, ...] = ()
    include_url_patterns: tuple[str, ...] = ()
    exclude_url_patterns: tuple[str, ...] = ()
    max_pages: int = 25
    max_depth: int = 1
    request_delay: float = 3.0
    relevance_threshold: float = 0.70
    default_licence: str = 'undetermined'
    allow_media_download: bool = False
    contact_note: str = ''


# Government and museum sites get a longer delay than the crawler's 2s default.
# These are small, frequently single-server sites; being a good citizen is
# cheap here and the crawl volume is low anyway.
_POLITE = 3.0
_POLITER = 5.0

# Shared excludes. Every site in the registry has one of these somewhere.
_EXCLUDE_NOISE = (
    r'/login',
    r'/register',
    r'/cart',
    r'/checkout',
    r'/search\?',
    r'\.pdf$',
    r'/feed$',
    r'/rss',
    r'/wp-admin',
    r'/wp-json',
    r'/tag/',
    r'/author/',
    r'/comment',
)


BUILTIN_SOURCES: tuple[SeedSource, ...] = (
    SeedSource(
        slug='cameroon-national-museum',
        name='Cameroon National Museum',
        base_url='https://cameroon-nationalmuseum.cm/',
        source_type=CrawlSource.SourceType.MUSEUM,
        reliability=CrawlSource.Reliability.AUTHORITATIVE,
        seed_urls=('https://cameroon-nationalmuseum.cm/',),
        request_delay=_POLITE,
        exclude_url_patterns=_EXCLUDE_NOISE,
        contact_note='Museum website. Check contact page before enabling media download.',
    ),
    SeedSource(
        slug='musecam',
        name='Musée National du Cameroun (Musécam)',
        base_url='https://www.musecam.org/',
        source_type=CrawlSource.SourceType.MUSEUM,
        reliability=CrawlSource.Reliability.AUTHORITATIVE,
        seed_urls=('https://www.musecam.org/',),
        request_delay=_POLITE,
        exclude_url_patterns=_EXCLUDE_NOISE,
    ),
    SeedSource(
        slug='minac',
        name='Ministry of Arts and Culture of Cameroon (MINAC)',
        base_url='https://minac.gov.cm/',
        source_type=CrawlSource.SourceType.GOVERNMENT,
        reliability=CrawlSource.Reliability.AUTHORITATIVE,
        seed_urls=('https://minac.gov.cm/',),
        request_delay=_POLITE,
        exclude_url_patterns=_EXCLUDE_NOISE,
        contact_note='Government site; low volume expected. Keep request_delay high.',
    ),
    SeedSource(
        slug='minac-patrimoine',
        name='MINAC — patrimoine culturel',
        base_url='https://www.minac-gouv.com/patrimoine-culturel/',
        source_type=CrawlSource.SourceType.GOVERNMENT,
        reliability=CrawlSource.Reliability.AUTHORITATIVE,
        seed_urls=('https://www.minac-gouv.com/patrimoine-culturel/',),
        request_delay=_POLITE,
        include_url_patterns=(r'patrimoine', r'culture'),
        exclude_url_patterns=_EXCLUDE_NOISE,
    ),
    SeedSource(
        slug='unesco-ich-cameroon',
        name='UNESCO Intangible Cultural Heritage — Cameroon',
        base_url='https://ich.unesco.org/en/state/cameroon-CM',
        source_type=CrawlSource.SourceType.UNESCO,
        reliability=CrawlSource.Reliability.AUTHORITATIVE,
        seed_urls=('https://ich.unesco.org/en/state/cameroon-CM',),
        # UNESCO is a large, heavily-trafficked origin serving the whole world.
        # Do not crawl it as if it were a small museum site.
        request_delay=_POLITER,
        max_pages=10,
        max_depth=1,
        # UNESCO element pages are CC BY-SA, but the state listing page carries
        # no licence statement that the crawler can read reliably, so media is
        # recorded by URL only until a human checks each element's terms.
        default_licence='undetermined',
        exclude_url_patterns=_EXCLUDE_NOISE,
    ),
    SeedSource(
        slug='unesco-oral-traditions',
        name='UNESCO Oral Traditions and Expressions',
        base_url='https://ich.unesco.org/en/oral-traditions-and-expressions-00053',
        source_type=CrawlSource.SourceType.UNESCO,
        reliability=CrawlSource.Reliability.AUTHORITATIVE,
        seed_urls=(
            'https://ich.unesco.org/en/oral-traditions-and-expressions-00053',
        ),
        request_delay=_POLITER,
        max_pages=10,
        max_depth=1,
        exclude_url_patterns=_EXCLUDE_NOISE,
    ),
    SeedSource(
        slug='unesco-world-heritage-cameroon',
        name='UNESCO World Heritage — Cameroon',
        base_url='https://whc.unesco.org/en/statesparties/cm',
        source_type=CrawlSource.SourceType.UNESCO,
        reliability=CrawlSource.Reliability.AUTHORITATIVE,
        seed_urls=('https://whc.unesco.org/en/statesparties/cm',),
        request_delay=_POLITER,
        max_pages=15,
        max_depth=1,
        exclude_url_patterns=_EXCLUDE_NOISE,
        contact_note='World Heritage list entries describe sites, not artefacts. '
        'Expected yield is heritage locations.',
    ),
    # The legacy standalone crawler in /crawler reads this one. It stays in the
    # registry so its output can be ingested through the same reviewed pipeline
    # instead of living beside it as a parallel path.
    SeedSource(
        slug='discover-cameroon',
        name='Discover Cameroon',
        base_url='https://discover-cameroon.com',
        source_type=CrawlSource.SourceType.OTHER,
        reliability=CrawlSource.Reliability.CURATED,
        seed_urls=(
            'https://discover-cameroon.com/en/about-cameroon/',
            'https://discover-cameroon.com/en/attractions/',
            'https://discover-cameroon.com/en/foumban-en/',
            'https://discover-cameroon.com/en/culture-languages-religions/',
            'https://discover-cameroon.com/en/history/',
        ),
        request_delay=1.5,
        max_pages=40,
        max_depth=1,
        exclude_url_patterns=_EXCLUDE_NOISE,
        contact_note='Tourism site. Existing /crawler script targets this source.',
    ),
)


def seed_sources(*, only_missing: bool = True) -> list[CrawlSource]:
    """Write the built-in registry to the database.

    `only_missing` is the default and the reason this is safe to re-run: an
    administrator who disabled a source, or tuned its delay, does not get those
    edits reverted by someone re-seeding.
    """
    created: list[CrawlSource] = []
    for seed in BUILTIN_SOURCES:
        if only_missing and CrawlSource.objects.filter(slug=seed.slug).exists():
            continue
        source, _ = CrawlSource.objects.update_or_create(
            slug=seed.slug,
            defaults={
                'name': seed.name,
                'base_url': seed.base_url,
                'source_type': seed.source_type,
                'reliability': seed.reliability,
                'enabled': False,  # §14: opt-in, never crawling by default.
                'is_builtin': True,
                'max_pages': seed.max_pages,
                'max_depth': seed.max_depth,
                'request_delay': seed.request_delay,
                'relevance_threshold': seed.relevance_threshold,
                'allowed_domains': list(seed.allowed_domains),
                'seed_urls': list(seed.seed_urls),
                'include_url_patterns': list(seed.include_url_patterns),
                'exclude_url_patterns': list(seed.exclude_url_patterns),
                'default_licence': seed.default_licence,
                'allow_media_download': seed.allow_media_download,
                'contact_note': seed.contact_note,
            },
        )
        created.append(source)
    return created