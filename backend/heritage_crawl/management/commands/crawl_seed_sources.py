"""
`manage.py crawl_seed_sources` — install the built-in source registry (§1).

    manage.py crawl_seed_sources              add missing sources only
    manage.py crawl_seed_sources --list       show the registry without writing
    manage.py crawl_seed_sources --enable-mine
    manage.py crawl_seed_sources --refresh    overwrite from the registry

Everything it creates is **disabled**. That is the important property: this
command must be safe to run in any deployment, so installing it never causes
outbound traffic to a third party. Somebody has to choose to crawl, and §14's
"Do not crawl aggressively" starts with somebody choosing.

`--enable-mine` exists because `only_missing=True` means re-running the command
cannot re-enable a source an administrator deliberately turned off — which is
correct, but it makes "why is nothing crawling?" a confusing first experience.
That flag opts in to the opposite behaviour explicitly, per run.
"""

from django.core.management.base import BaseCommand, CommandError

from heritage_crawl.models import CrawlSource
from heritage_crawl.source_config import BUILTIN_SOURCES, seed_sources


class Command(BaseCommand):
    help = 'Register the built-in cultural heritage sources from Crawler.md §1.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--list', action='store_true', dest='list_sources',
            help='Print the built-in registry and exit without writing.',
        )
        parser.add_argument(
            '--refresh', action='store_true',
            help=(
                'Overwrite existing rows with registry values. Reverts any '
                'administrator edits to built-in sources, including disabled.'
            ),
        )
        parser.add_argument(
            '--enable-mine', action='store_true',
            help='Also enable sources this run created.',
        )

    def handle(self, *args, **options):
        if options['list_sources']:
            self._list()
            return

        created = seed_sources(only_missing=not options['refresh'])

        if options['enable_mine']:
            if options['refresh']:
                raise CommandError(
                    '--enable-mine cannot be combined with --refresh: enabling '
                    'every built-in source on a refresh is how a crawler ends '
                    'up hammering seven websites at once.'
                )
            for source in created:
                source.enabled = True
                source.save(update_fields=['enabled'])

        self.stdout.write(
            self.style.SUCCESS(f'Seeded {len(created)} source(s).')
        )
        for source in created:
            self.stdout.write(
                f'  {source.slug:<28} {"ENABLED" if source.enabled else "disabled"}'
            )

        if created and not options['enable_mine']:
            self.stdout.write(
                self.style.WARNING(
                    '\nAll seeded sources are disabled, which is deliberate.\n'
                    'Enable one in the admin, or re-run with --enable-mine:\n'
                    '  manage.py crawl_seed_sources --enable-mine\n'
                )
            )

    def _list(self):
        self.stdout.write(f'{"slug":<30} {"type":<11} {"delay":>6}  name')
        for seed in BUILTIN_SOURCES:
            self.stdout.write(
                f'{seed.slug:<30} {seed.source_type:<11} '
                f'{seed.request_delay:>5.1f}s  {seed.name}'
            )
        self.stdout.write(f'\n{len(BUILTIN_SOURCES)} source(s) in the registry.')
        installed = set(
            CrawlSource.objects.filter(is_builtin=True).values_list('slug', flat=True)
        )
        missing = [s.slug for s in BUILTIN_SOURCES if s.slug not in installed]
        if missing:
            self.stdout.write(
                self.style.WARNING(
                    f'Not yet installed: {", ".join(missing)}'
                )
            )
