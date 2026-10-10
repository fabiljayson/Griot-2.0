"""Seed `PremiumFeature` rows from `settings.PREMIUM_FEATURES`.

Idempotent: re-running it updates labels/descriptions and never touches the
operator-edited `enabled` flag — a kill-switched feature must not come back
on just because a reseed ran. Rows for keys an operator later removes from
settings are left alone too, so hardening an installment does not surprise
whoever turned a feature on or off.
"""

from django.conf import settings
from django.core.management.base import BaseCommand

from subscriptions.models import PremiumFeature


class Command(BaseCommand):
    help = 'Create or refresh PremiumFeature rows from settings.PREMIUM_FEATURES.'

    def handle(self, *args, **options):
        configured = getattr(settings, 'PREMIUM_FEATURES', None)
        if not isinstance(configured, dict) or not configured:
            self.stdout.write('No PREMIUM_FEATURES configured; nothing to seed.')
            return

        created = updated = 0
        for display_order, (key, meta) in enumerate(configured.items()):
            feature, was_created = PremiumFeature.objects.get_or_create(
                key=key,
                defaults={
                    'label': meta.get('label', key.replace('_', ' ').title()),
                    'description': meta.get('description', ''),
                    'display_order': display_order,
                },
            )
            if was_created:
                created += 1
                continue
            feature.label = meta.get('label', feature.label)
            feature.description = meta.get('description', feature.description)
            feature.display_order = display_order
            feature.save(update_fields=['label', 'description', 'display_order'])
            updated += 1
        self.stdout.write(
            self.style.SUCCESS(
                f'Seeded premium features: {created} created, {updated} updated.',
            ),
        )