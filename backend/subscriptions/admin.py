from django.contrib import admin

from .models import Payment, PremiumFeature, Subscription, SubscriptionPlan


@admin.register(PremiumFeature)
class PremiumFeatureAdmin(admin.ModelAdmin):
    """The operator-facing feature switches.

    Editing `enabled` here is the kill-switch path that requires no deploy:
    a paid feature switched off is out of service for everyone until switched
    back on.
    """

    list_display = ('label', 'key', 'enabled', 'display_order', 'updated_at')
    list_editable = ('enabled', 'display_order')
    list_filter = ('enabled',)
    search_fields = ('key', 'label')
    ordering = ('display_order', 'key')


@admin.register(Subscription)
class SubscriptionAdmin(admin.ModelAdmin):
    """Entitlement rows.

    Editable so an administrator can grant premium access manually (the
    `manual` provider) — the path institutions use before billing is wired
    up. Rows are kept after expiry: the payment record is part of the audit
    trail.
    """

    list_display = (
        'user',
        'status',
        'provider',
        'entitlement_id',
        'current_period_end',
        'updated_at',
    )
    list_filter = ('status', 'provider')
    search_fields = ('user__username', 'user__email', 'provider_customer_id')
    readonly_fields = ('updated_at',)
    raw_id_fields = ('user',)

@admin.register(SubscriptionPlan)
class SubscriptionPlanAdmin(admin.ModelAdmin):
    """The plan shelf.

    Prices and durations are data (seeded from `settings.SUBSCRIPTION_PLANS`),
    so a pricing change is an edit here rather than a migration. Deactivating
    a plan takes it off the paywall without breaking receipts that point at it.
    """

    list_display = (
        'name',
        'key',
        'price',
        'currency',
        'interval',
        'duration_days',
        'is_active',
        'display_order',
    )
    list_filter = ('is_active', 'interval', 'currency')
    search_fields = ('key', 'name')
    ordering = ('display_order', 'key')


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    """Payment references — read-mostly audit rows.

    There is no card data to edit here by design: `provider_reference` is the
    store's transaction id and nothing more (PCI scope stays with the
    provider). `dev` rows state in `note` that no charge happened.
    """

    list_display = (
        'user',
        'amount',
        'currency',
        'status',
        'provider',
        'plan',
        'created_at',
    )
    list_filter = ('status', 'provider', 'currency')
    search_fields = (
        'user__username',
        'user__email',
        'provider_reference',
    )
    readonly_fields = ('created_at', 'updated_at')
    raw_id_fields = ('user',)
    date_hierarchy = 'created_at'
