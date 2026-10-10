"""Subscription and premium-feature domain models.

Two things, deliberately separate because they answer different questions:

* `PremiumFeature` — *which features are premium*. The set of paid keys is
  fixed in `settings.PREMIUM_FEATURES` so a missing row can never silently
  un-gate a paid feature; the `enabled` flag is an operational kill switch an
  operator can flip from the Django admin to take a feature out of the build
  (or to stop charging for it) without a deploy.
* `Subscription` — *whether this account paid*. One row per user, written
  from the RevenueCat webhook (or granted manually by an admin), carrying the
  store's notion of the current period.

The boundary between the two is the rule "the gate list lives in settings,
the store's verdict lives in data". A reader-facing feature never reads a
gate from the database alone; `stories.services`-style code calls
`subscriptions.services.has_feature_access` and gets a single answer.
"""

from django.conf import settings
from django.db import models
from django.utils import timezone
from django.utils.translation import gettext_lazy as _

from users.models import User


class PremiumFeature(models.Model):
    """One administrable premium-feature switch.

    `key` must exist in `settings.PREMIUM_FEATURES`; rows for keys the code
    does not configure are harmless but are never consulted. The feature is
    *charged for* because its key is in the settings table; this row only
    decides whether it is currently live and how an operator labels it.
    """

    key = models.SlugField(
        max_length=64,
        unique=True,
        help_text='Must match a key in settings.PREMIUM_FEATURES.',
    )
    label = models.CharField(max_length=120, help_text='Name shown to readers.')
    description = models.TextField(
        blank=True,
        default='',
        help_text='What the feature includes, for the paywall and admin.',
    )
    enabled = models.BooleanField(
        default=True,
        help_text=(
            'Live flag. Disabling a premium feature takes it out of service '
            'for everyone — entitled readers included — until re-enabled.'
        ),
    )
    display_order = models.PositiveSmallIntegerField(
        default=0,
        help_text='Order on the paywall. Lower first.',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('display_order', 'key')

    def __str__(self) -> str:
        return f'{self.label} ({self.key})'


class SubscriptionPlan(models.Model):
    """A purchasable plan: what the store bills and how long it lasts.

    Data, not code — prices and durations are an operator edit away, seeded
    from `settings.SUBSCRIPTION_PLANS`. The plan row is what a `Payment` and
    a `Subscription` point at, so "which plan was this" survives even when
    the store's own product id means nothing to us.
    """

    class Interval(models.TextChoices):
        WEEK = 'week', _('Weekly')
        MONTH = 'month', _('Monthly')
        YEAR = 'year', _('Yearly')

    key = models.SlugField(
        max_length=64,
        unique=True,
        help_text='Stable identifier (e.g. `premium_monthly`).',
    )
    name = models.CharField(max_length=120, help_text='Shown on the paywall.')
    description = models.TextField(blank=True, default='')
    price = models.DecimalField(
        max_digits=8,
        decimal_places=2,
        help_text='Price per interval in `currency`.',
    )
    currency = models.CharField(max_length=8, default='USD')
    interval = models.CharField(
        max_length=8,
        choices=Interval.choices,
        default=Interval.MONTH,
    )
    duration_days = models.PositiveIntegerField(
        default=30,
        help_text='Entitlement length granted per paid period.',
    )
    is_active = models.BooleanField(
        default=True,
        help_text='Inactive plans stay on old receipts but cannot be bought.',
    )
    display_order = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('display_order', 'key')

    def __str__(self) -> str:
        return f'{self.name} ({self.key})'


class Subscription(models.Model):
    """An account's purchase record, mirroring the store's current period.

    Written from the RevenueCat webhook (`subscriptions.views.RevenueCatWebhookView`),
    from a development checkout, or granted manually by an administrator.
    `status` carries the store's verdict; `is_entitled` folds in time so one
    property answers "does this account currently have the entitlement"
    without callers re-implementing date math. `expired` rows are kept rather
    than deleted: the audit trail of who paid and for how long is part of the
    record a subscription creates.
    """

    class Status(models.TextChoices):
        ACTIVE = 'active', _('Active')
        TRIAL = 'trial', _('Trial / intro offer')
        PENDING = 'pending', _('Pending (awaiting provider confirmation)')
        CANCELLED = 'cancelled', _('Cancelled (until period end)')
        EXPIRED = 'expired', _('Expired')

    class Provider(models.TextChoices):
        REVENUECAT = 'revenuecat', _('RevenueCat')
        MANUAL = 'manual', _('Manual grant')
        DEV = 'dev', _('Development checkout')

    # One subscription per account: the app has a single premium tier, and the
    # RevenueCat SDK maps one app user id to one customer.
    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name='subscription',
    )
    plan = models.ForeignKey(
        SubscriptionPlan,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='subscriptions',
        help_text='The plan behind this period; null after a plan is retired.',
    )
    entitlement_id = models.CharField(
        max_length=64,
        default='premium',
        help_text='The purchased entitlement; the premium tier is `premium`.',
    )
    provider = models.CharField(
        max_length=24,
        choices=Provider.choices,
        default=Provider.MANUAL,
    )
    # RevenueCat app_user_id. Empty for manually granted rows.
    provider_customer_id = models.CharField(max_length=255, blank=True, default='')
    provider_subscription_id = models.CharField(
        max_length=255,
        blank=True,
        default='',
        help_text='Store subscription/product identifier from the webhook.',
    )
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.ACTIVE,
    )
    current_period_start = models.DateTimeField(null=True, blank=True)
    current_period_end = models.DateTimeField(
        null=True,
        blank=True,
        help_text='Null on grants/intro offers without an expiry.',
    )
    purchased_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-updated_at',)

    def __str__(self) -> str:
        return f'{self.user.username}: {self.get_status_display()}'

    @property
    def is_entitled(self) -> bool:
        """Whether the account currently holds the paid entitlement.

        An active or trial row is entitled throughout its period even after a
        cancellation — the reader paid until `current_period_end`. A pending
        row is *awaiting* the provider's confirmation, so it grants nothing:
        entitlement on a promise is how a chargeback becomes a free premium
        account. An expired row is not entitled no matter what its dates say.
        """
        if self.status == self.Status.EXPIRED:
            return False
        if self.status == self.Status.PENDING:
            return False
        if self.status == self.Status.CANCELLED:
            if self.current_period_end is None:
                return False
            return self.current_period_end > timezone.now()
        # ACTIVE / TRIAL: a missing period end (manual grant, intro offer)
        # means "until told otherwise".
        if self.current_period_end is None:
            return True
        return self.current_period_end > timezone.now()


class Payment(models.Model):
    """A payment record — a reference to money, never the money's details.

    Deliberately stores **no card data**: no PAN, no expiry, no CVV, no
    wallet tokens. A legitimate payment provider (RevenueCat) processes the
    charge and tells us only `provider_reference`; this row exists so an
    operator can answer "who paid, for which plan, when, and did it settle"
    without ever touching a cardholder data surface (PCI scope stays with
    the provider). The `dev` provider marks the development checkout, which
    performs no real charge and says so in `note`.
    """

    class Status(models.TextChoices):
        PENDING = 'pending', _('Pending')
        COMPLETED = 'completed', _('Completed')
        FAILED = 'failed', _('Failed')
        REFUNDED = 'refunded', _('Refunded')

    class Provider(models.TextChoices):
        REVENUECAT = 'revenuecat', _('RevenueCat')
        MANUAL = 'manual', _('Manual (admin-recorded)')
        DEV = 'dev', _('Development checkout')

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='payments',
    )
    plan = models.ForeignKey(
        SubscriptionPlan,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='payments',
    )
    subscription = models.ForeignKey(
        Subscription,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='payments',
    )
    provider = models.CharField(
        max_length=24,
        choices=Provider.choices,
        default=Provider.MANUAL,
    )
    provider_reference = models.CharField(
        max_length=255,
        blank=True,
        default='',
        db_index=True,
        help_text='Store transaction id; empty for manual/dev records.',
    )
    amount = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    currency = models.CharField(max_length=8, default='USD')
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.PENDING,
    )
    note = models.TextField(
        blank=True,
        default='',
        help_text='Human context (e.g. "Development checkout — no charge").',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-created_at',)

    def __str__(self) -> str:
        return (
            f'{self.user.username}: {self.amount} {self.currency} '
            f'({self.get_status_display()})'
        )


def configured_premium_features() -> dict:
    """`settings.PREMIUM_FEATURES` as key -> metadata, or empty dict."""
    configured = getattr(settings, 'PREMIUM_FEATURES', None)
    if not isinstance(configured, dict):
        return {}
    return configured


# ---------------------------------------------------------------------------
# Module-level choice aliases
# ---------------------------------------------------------------------------
# drf-spectacular derives schema component names from a field's choice class;
# nested TextChoices produce unstable hash-suffixed names. `ENUM_NAME_OVERRIDES`
# in settings pins them, but resolves each value with `import_string`, which
# cannot walk *into* a class. Re-exporting the nested enums at module level
# gives those overrides a path that actually resolves (same pattern as
# `stories.models`).
#
# The alias, not the nested class, is the canonical name; keep them together.
SubscriptionStatusChoices = Subscription.Status
SubscriptionProviderChoices = Subscription.Provider
PaymentStatusChoices = Payment.Status
PaymentProviderChoices = Payment.Provider
SubscriptionPlanIntervalChoices = SubscriptionPlan.Interval