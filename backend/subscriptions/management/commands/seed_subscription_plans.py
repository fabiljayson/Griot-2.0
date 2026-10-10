"""Seed `SubscriptionPlan` rows from `settings.SUBSCRIPTION_PLANS`.

Idempotent by `key`: re-running updates prices/durations from settings and
never deactivates a plan an operator turned off in the admin — a retired plan
stays on old receipts, and a reseed must not put it back on the shelf.
"""

from django.conf import settings
from django.core.management.base import BaseCommand

from subscriptions.models import SubscriptionPlan


class Command(BaseCommand):
    help = 'Create or refresh SubscriptionPlan rows from settings.SUBSCRIPTION_PLANS.'

    def handle(self, *args, **options):
        configured = getattr(settings, 'SUBSCRIPTION_PLANS', None)
        if not isinstance(configured, list) or not configured:
            self.stdout.write('No SUBSCRIPTION_PLANS configured; nothing to seed.')
            return

        created = updated = 0
        for meta in configured:
            key = meta['key']
            defaults = {
                'name': meta.get('name', key.replace('_', ' ').title()),
                'description': meta.get('description', ''),
                'price': meta.get('price', '0.00'),
                'currency': meta.get('currency', 'USD'),
                'interval': meta.get('interval', SubscriptionPlan.Interval.MONTH),
                'duration_days': meta.get('duration_days', 30),
                'display_order': meta.get('display_order', 0),
            }
            plan, was_created = SubscriptionPlan.objects.get_or_create(
                key=key,
                defaults=defaults,
            )
            if was_created:
                created += 1
                continue
            # `is_active` is deliberately absent: retiring a plan is an admin
            # decision, not something a reseed reverses.
            for field, value in defaults.items():
                setattr(plan, field, value)
            plan.save(update_fields=list(defaults.keys()) + ['updated_at'])
            updated += 1

        self.stdout.write(
            self.style.SUCCESS(
                f'Seeded subscription plans: {created} created, {updated} updated.',
            ),
        )
