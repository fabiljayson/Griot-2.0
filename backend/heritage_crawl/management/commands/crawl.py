"""
`manage.py crawl` — run the crawler from the command line (§17).

This is the supported way to crawl anything substantial. The HTTP endpoint
blocks for the length of the run, which is fine for a single page and wrong for
a full crawl; a shell does not time out and can be pointed at by cron.

    manage.py crawl --list                      show configured sources
    manage.py crawl --all                       crawl every enabled source
    manage.py crawl --source minac              one source
    manage.py crawl --all --max-pages 5         cap the run
    manage.py crawl --all --dry-run             fetch, extract, score, import nothing

`--dry-run` is the one worth knowing about. It exercises the entire pipeline —
fetching, robots, extraction, relevance, dedup — and writes nothing but
`CrawlJob` rows and `CrawledItem` staging records, so an administrator can see
exactly what a source would contribute before any of it reaches the corpus.
"""

from django.core.management.base import BaseCommand, CommandError

from heritage_crawl.ingest import crawl_source
from heritage_crawl.models import CrawlSource


class Command(BaseCommand):
    help = 'Discover, extract and import Cameroonian cultural heritage from configured sources.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--source', action='append', dest='sources', metavar='SLUG',
            help='Crawl this source. Repeatable.',
        )
        parser.add_argument(
            '--all', action='store_true',
            help='Crawl every enabled source.',
        )
        parser.add_argument(
            '--list', action='store_true', dest='list_sources',
            help='List configured sources and exit.',
        )
        parser.add_argument(
            '--max-pages', type=int, default=None,
            help='Override the per-source page budget for this run.',
        )
        parser.add_argument(
            '--ignore-robots', action='store_true',
            help=(
                'Bypass robots.txt. Exists for tests and for the operator who '
                'holds written permission from the source; do not use it '
                'casually.'
            ),
        )
        parser.add_argument(
            '--full-text', action='store_true',
            help='Store fuller page text instead of the metadata-and-excerpt default.',
        )
        parser.add_argument(
            '--dry-run', action='store_true',
            help='Run the pipeline and record the outcome, but import nothing into the corpus.',
        )

    def handle(self, *args, **options):
        if options['list_sources']:
            self._list_sources()
            return

        sources = self._resolve(options)
        if not sources:
            if options['all']:
                enabled = CrawlSource.objects.filter(enabled=True).count()
                raise CommandError(
                    f'--all matched {enabled} enabled source(s). Crawling '
                    'requires a deliberate opt-in: enable a source in the admin, '
                    'or re-seed with --enable-mine. Run --list to see the '
                    'registry.'
                )
            raise CommandError(
                'Nothing to crawl. Pass --source SLUG or --all, or run with '
                '--list to see what is configured.'
            )

        totals = {
            'imported': 0, 'duplicates': 0, 'skipped': 0, 'errors': 0,
            'media': 0, 'pages': 0,
        }
        failures = 0

        for source in sources:
            self.stdout.write(self.style.MIGRATE_HEADING(f'\n=== {source.name} ==='))
            try:
                outcome = crawl_source(
                    source,
                    max_pages=options['max_pages'],
                    respect_robots=not options['ignore_robots'],
                    store_full_text=options['full_text'] or None,
                    dry_run=options['dry_run'],
                )
            except ValueError as exc:
                self.stderr.write(self.style.ERROR(f'  skipped: {exc}'))
                failures += 1
                continue

            if options['dry_run']:
                self._report_dry_run(source, outcome)
            else:
                self._report(outcome)

            totals['imported'] += outcome.imported
            totals['duplicates'] += outcome.duplicates
            totals['skipped'] += outcome.skipped
            totals['errors'] += outcome.errors
            totals['media'] += outcome.media_recorded
            totals['pages'] += outcome.job.pages_processed

        self.stdout.write(self.style.MIGRATE_HEADING('\n=== Total ==='))
        self.stdout.write(f'  Pages visited:  {totals["pages"]}')
        self.stdout.write(f'  Imported:       {totals["imported"]}')
        self.stdout.write(f'  Duplicates:     {totals["duplicates"]}')
        self.stdout.write(f'  Skipped:        {totals["skipped"]}')
        self.stdout.write(f'  Media recorded: {totals["media"]}')
        self.stdout.write(f'  Errors:         {totals["errors"]}')

        if not options['dry_run'] and totals['imported']:
            self.stdout.write(
                self.style.WARNING(
                    f'\n{totals["imported"]} item(s) are pending review. Nothing '
                    'is public until an administrator approves it:\n'
                    '  http://localhost:8000/admin/heritage_crawl/crawleditem/'
                )
            )

        if failures:
            raise CommandError(f'{failures} source(s) could not be crawled.')

    def _resolve(self, options) -> list[CrawlSource]:
        if options['sources']:
            found = []
            for slug in options['sources']:
                try:
                    found.append(CrawlSource.objects.get(slug=slug))
                except CrawlSource.DoesNotExist:
                    raise CommandError(f'No crawl source with slug {slug!r}.')
            return found
        if options['all']:
            return list(CrawlSource.objects.filter(enabled=True))
        return []

    def _list_sources(self):
        sources = CrawlSource.objects.all()
        if not sources:
            self.stdout.write('No sources configured. Seed the built-ins with:')
            self.stdout.write('  manage.py crawl_seed_sources')
            return
        self.stdout.write(f'{"slug":<28} {"enabled":<8} {"type":<11} name')
        for source in sources:
            self.stdout.write(
                f'{source.slug:<28} '
                f'{"yes" if source.enabled else "no":<8} '
                f'{source.source_type:<11} {source.name}'
            )
        disabled = sum(1 for s in sources if not s.enabled)
        if disabled:
            self.stdout.write(
                self.style.WARNING(
                    f'\n{disabled} source(s) are disabled. Enable them in the '
                    'admin before crawling — built-ins ship disabled on purpose.'
                )
            )

    def _report(self, outcome):
        job = outcome.job
        self.stdout.write(f'  job #{job.pk} — {job.get_status_display()}')
        for label, value in job.summary().items():
            self.stdout.write(f'    {label}: {value}')
        if job.duration_seconds() is not None:
            self.stdout.write(f'    duration: {job.duration_seconds():.1f}s')
        for item_id in outcome.item_ids:
            from heritage_crawl.models import CrawledItem

            item = CrawledItem.objects.filter(pk=item_id).first()
            if item and item.error_message:
                self.stdout.write(
                    self.style.ERROR(f'    ! {item.error_type}: {item.error_message[:120]}')
                )

    def _report_dry_run(self, source, outcome):
        """Dry run: say plainly that nothing was imported.

        Silent success here would be the worst outcome — an operator would
        reasonably believe a crawl had populated the corpus.
        """
        self.stdout.write(
            f'  job #{outcome.job.pk} (dry run) — pages visited: '
            f'{outcome.job.pages_processed}, relevant: {outcome.job.items_found}'
        )
        for item_id in outcome.item_ids:
            from heritage_crawl.models import CrawledItem

            item = CrawledItem.objects.filter(pk=item_id).first()
            if item and item.relevance_score:
                self.stdout.write(
                    f'    {item.relevance_score:.2f}  '
                    f'{(item.extracted_title or item.original_url)[:70]}'
                )
        self.stdout.write(
            self.style.WARNING(
                '    dry run — nothing was imported into the corpus.'
            )
        )
