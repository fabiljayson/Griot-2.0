"""Send the recurring reader messages to everyone at once.

Runs the two recurring jobs — the weekly trending digest and the daily streak
nudge — and is safe to run as often as the scheduler likes: both sends are keyed,
so a repeat within the same week or day does nothing.

Normally unnecessary. The same two sends also run per reader from
[notifications.services.sync_for_user] when they open the app, which is what
makes the feature work on Render's free tier (no cron). This command exists for
the case where a send has to happen without anyone opening the app — an
announcement you want in inboxes before the weekend, or a backfill after fixing
a bug in the fan-out.

Trigger it from a shell:

    python manage.py send_scheduled_notifications
"""

from django.core.management.base import BaseCommand

from notifications import services


class Command(BaseCommand):
    help = 'Send the weekly trending digest and the daily streak reminders.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--skip-digest',
            action='store_true',
            help='Only send streak reminders.',
        )
        parser.add_argument(
            '--skip-streaks',
            action='store_true',
            help='Only send the weekly trending digest.',
        )

    def handle(self, *args, **options):
        if not options['skip_digest']:
            created = services.send_trending_digest()
            self.stdout.write(
                self.style.SUCCESS(
                    f'Trending digest: {created} new message(s).'
                    if created
                    else 'Trending digest: already sent this week.'
                )
            )

        if not options['skip_streaks']:
            reminded = services.send_streak_reminders()
            if reminded:
                self.stdout.write(
                    self.style.SUCCESS(
                        f'Streak reminders: {reminded} new message(s).'
                    )
                )
            else:
                self.stdout.write('Streak reminders: nobody to remind.')
