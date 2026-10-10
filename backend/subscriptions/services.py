"""Subscription and premium-feature access logic.

Single source of truth for "can this reader use feature X". The rule the whole
module enforces:

* a feature is *paid* because its key exists in `settings.PREMIUM_FEATURES`,
  never because the database happens to contain a row;
* an operator can switch a paid feature off (kill switch) from the admin
  without a deploy;
* an account is *entitled* from `Subscription.is_entitled`, which folds the
  store's status together with the current period;
* platform staff and superusers always get premium access — they operate the
  platform and must be able to exercise the build's paid surfaces.
"""

import uuid
from datetime import UTC, datetime, timedelta

from django.conf import settings
from django.utils import timezone

from users.models import User

from .models import (
    Payment,
    PremiumFeature,
    Subscription,
    SubscriptionPlan,
    configured_premium_features,
)


def revenuecat_app_user_id(user) -> str:
    """The stable RevenueCat app-user id for an account.

    Reused by the mobile SDK when it identifies the customer, so the webhook
    can find the same row the SDK is billing against. Derived from the
    database id because nothing else on `User` is guaranteed immutable.
    """
    return str(user.id)


def feature_metadata() -> list:
    """The configured premium features, in paywall order, with live flags.

    `enabled` reads the admin-controllable `PremiumFeature` row; a configured
    key that has not been seeded yet defaults to enabled so that an unseeded
    database can never silently give a paid feature away.
    """
    configured = configured_premium_features()
    seeded = {
        row.key: row
        for row in PremiumFeature.objects.filter(key__in=configured.keys())
    }
    ordered_keys = sorted(
        configured.keys(),
        key=lambda key: (
            seeded[key].display_order if key in seeded else 0,
            key,
        ),
    )
    return [
        {
            'key': key,
            'label': (seeded.get(key).label if key in seeded else None)
            or configured[key].get('label', key.replace('_', ' ').title()),
            'description': (seeded.get(key).description if key in seeded else '')
            or configured[key].get('description', ''),
            'enabled': seeded[key].enabled if key in seeded else True,
        }
        for key in ordered_keys
    ]


def is_feature_live(feature_key: str) -> bool:
    """Whether a premium feature is currently switched on for *anyone*.

    A key not in `settings.PREMIUM_FEATURES` is not a paid feature at all
    (free content is not "live or dead"; it is simply available). A configured
    key with no row or with `enabled=True` is live.
    """
    if feature_key not in configured_premium_features():
        return False
    try:
        return PremiumFeature.objects.get(key=feature_key).enabled
    except PremiumFeature.DoesNotExist:
        return True


def active_subscription(user) -> Subscription | None:
    """The account's subscription, when it currently grants premium access."""
    if not user or not user.is_authenticated:
        return None
    subscription = getattr(user, 'subscription', None)
    if subscription is not None and subscription.is_entitled:
        return subscription
    return None


def has_feature_access(user, feature_key: str) -> bool:
    """Whether `user` may use `feature_key` right now.

    The only predicate the rest of the backend calls. Free features (not in
    `settings.PREMIUM_FEATURES`) always return True; premium features require
    a live entitlement (or platform staff/superuser), and a kill-switched
    feature returns False for everyone.
    """
    configured = configured_premium_features()
    if feature_key not in configured:
        # Free feature. The absence of a gate is the product decision: the
        # whole feature list beats any per-feature debug flag.
        return True
    if not is_feature_live(feature_key):
        return False
    if not user or not user.is_authenticated:
        return False
    if getattr(user, 'is_staff', False) or getattr(user, 'is_superuser', False):
        return True
    return active_subscription(user) is not None


def subscription_status(user) -> dict:
    """The status payload for `GET /api/subscriptions/status/`."""
    subscription = getattr(user, 'subscription', None)
    entitled = subscription is not None and subscription.is_entitled
    plan = getattr(subscription, 'plan', None) if subscription else None

    return {
        'subscribed': entitled,
        'entitled': entitled,
        'status': subscription.status if subscription else None,
        'provider': subscription.provider if subscription else None,
        'plan': plan.key if plan else None,
        'plan_name': plan.name if plan else None,
        'current_period_start': (
            subscription.current_period_start.isoformat()
            if subscription and subscription.current_period_start else None
        ),
        'current_period_end': (
            subscription.current_period_end.isoformat()
            if subscription and subscription.current_period_end else None
        ),
        'features': [
            {
                'key': feature['key'],
                'label': feature['label'],
                'enabled': feature['enabled'],
                # Access to a free feature is intrinsic; access to a premium
                # one is the entitlement answer above.
                'has_access': has_feature_access(user, feature['key']),
            }
            for feature in feature_metadata()
        ],
    }


# ---------------------------------------------------------------------------
# Plans and the development checkout
# ---------------------------------------------------------------------------

def plan_metadata() -> list:
    """The purchasable plans, in paywall order.

    Only active plans: a retired plan can still be *seen* on an old receipt
    through its `Subscription.plan` FK, but it is not on the shelf.
    """
    return [
        {
            'key': plan.key,
            'name': plan.name,
            'description': plan.description,
            'price': str(plan.price),
            'currency': plan.currency,
            'interval': plan.interval,
            'duration_days': plan.duration_days,
        }
        for plan in SubscriptionPlan.objects.filter(is_active=True)
    ]


def dev_checkout_enabled() -> bool:
    """Whether the development checkout is switched on for this server.

    Explicitly configured, never implied: the endpoint it guards performs no
    real charge, so production must set `SUBSCRIPTION_DEV_CHECKOUT=0` (the
    default outside DEBUG) and leave purchases to the payment provider.
    """
    return bool(getattr(settings, 'SUBSCRIPTION_DEV_CHECKOUT', False))


def perform_dev_checkout(user, plan: SubscriptionPlan) -> Payment:
    """Grant one paid period through the development checkout.

    Records the same shapes a real purchase would — a `Subscription` pointing
    at the plan with a period, and a `Payment` referencing it — but with
    `provider='dev'` and a note stating that no money moved. There is no
    provider to confirm anything, so the row is `completed` immediately and
    the account is entitled for `plan.duration_days`.
    """
    now = timezone.now()
    period_end = now + timedelta(days=plan.duration_days)

    subscription, _ = Subscription.objects.update_or_create(
        user=user,
        defaults={
            'plan': plan,
            'entitlement_id': 'premium',
            'provider': Subscription.Provider.DEV,
            'provider_customer_id': '',
            'provider_subscription_id': '',
            'status': Subscription.Status.ACTIVE,
            'current_period_start': now,
            'current_period_end': period_end,
        },
    )

    return Payment.objects.create(
        user=user,
        plan=plan,
        subscription=subscription,
        provider=Payment.Provider.DEV,
        provider_reference=f'dev-{uuid.uuid4().hex[:24]}',
        amount=plan.price,
        currency=plan.currency,
        status=Payment.Status.COMPLETED,
        note='Development checkout — no real payment was processed.',
    )


# ---------------------------------------------------------------------------
# Store sync (RevenueCat webhook)
# ---------------------------------------------------------------------------

def find_user_for_webhook(app_user_id: str) -> User | None:
    """Resolve the RevenueCat app_user_id to a platform account.

    Unknown ids are None, never an exception: by the time RevenueCat reports a
    purchase, a deleted account may have taken the id, and the webhook must
    not 500 because a row is gone.
    """
    try:
        return User.objects.get(pk=int(app_user_id))
    except (User.DoesNotExist, TypeError, ValueError):
        return None


def apply_webhook_event(event: dict) -> str:
    """Apply one RevenueCat webhook event and describe what changed.

    Returns a short human-readable outcome the view can log. Events RevenueCat
    may send that are not lifecycle changes (`BC_CONFIRMED`, `SUBSCRIBED` …)
    are accepted with a no-op outcome rather than rejected, because a non-2xx
    reply makes RevenueCat re-deliver a message this backend deliberately
    ignores.
    """
    event_type = event.get('type')
    if not event_type:
        return 'ignored: no event type'

    customer_id = event.get('app_user_id') or ''
    subscription_id = event.get('product_id') or ''
    entitlement_ids = event.get('entitlement_ids') or []
    entitlement_id = entitlement_ids[0] if entitlement_ids else 'premium'

    def _ms_to_dt(ms):
        if not ms:
            return None
        try:
            return datetime.fromtimestamp(
                int(ms) / 1000, tz=UTC,
            )
        except (TypeError, ValueError, OSError):
            return None

    purchase_ms = event.get('purchased_at_ms') or event.get('purchase_date_ms')
    expire_ms = event.get('expiration_at_ms') or event.get('expires_date_ms')

    # Transfer finds the *new* owner on the receiving side.
    if event_type == 'TRANSFER':
        new_owner = find_user_for_webhook(customer_id)
        if new_owner is None:
            return 'transfer: no such user — ignored'
        Subscription.objects.update_or_create(
            user=new_owner,
            defaults={
                'entitlement_id': entitlement_id,
                'provider': Subscription.Provider.REVENUECAT,
                'provider_customer_id': customer_id,
                'provider_subscription_id': subscription_id,
                'status': Subscription.Status.ACTIVE,
                'current_period_start': _ms_to_dt(purchase_ms),
                'current_period_end': _ms_to_dt(expire_ms),
            },
        )
        return 'transfer: entitlement moved'

    user = find_user_for_webhook(customer_id)
    if user is None:
        return 'ignored: unknown app_user_id'

    period_type = (event.get('period_type') or '').upper()

    # Renewals reactivate a cancelled row; a fresh initial purchase restores an
    # expired one — both land in the same writer.
    if event_type in (
        'INITIAL_PURCHASE',
        'RENEWAL',
        'PRODUCT_CHANGE',
        'UNCANCELLATION',
    ):
        status = (
            Subscription.Status.TRIAL
            if period_type in ('TRIAL', 'INTRO')
            else Subscription.Status.ACTIVE
        )
        Subscription.objects.update_or_create(
            user=user,
            defaults={
                'entitlement_id': entitlement_id,
                'provider': Subscription.Provider.REVENUECAT,
                'provider_customer_id': customer_id,
                'provider_subscription_id': subscription_id,
                'status': status,
                'current_period_start': _ms_to_dt(purchase_ms),
                'current_period_end': _ms_to_dt(expire_ms),
            },
        )
        return f'{event_type}: subscription now {status}'

    if event_type == 'CANCELLATION':
        # "Won't renew" — the reader stays entitled until the period ends and
        # only `EXPIRATION`/`CUSTOMER_SUPPORT` actually revokes access.
        Subscription.objects.update_or_create(
            user=user,
            defaults={
                'entitlement_id': entitlement_id,
                'provider': Subscription.Provider.REVENUECAT,
                'provider_customer_id': customer_id,
                'provider_subscription_id': subscription_id,
                'status': Subscription.Status.CANCELLED,
                'current_period_start': _ms_to_dt(purchase_ms),
                'current_period_end': _ms_to_dt(expire_ms),
            },
        )
        return 'CANCELLATION: not renewing, entitled until period end'

    if event_type in ('EXPIRATION', 'CUSTOMER_SUPPORT', 'SUBSCRIPTION_EXPIRED'):
        Subscription.objects.update_or_create(
            user=user,
            defaults={
                'entitlement_id': entitlement_id,
                'provider': Subscription.Provider.REVENUECAT,
                'provider_customer_id': customer_id,
                'provider_subscription_id': subscription_id,
                'status': Subscription.Status.EXPIRED,
                'current_period_end': _ms_to_dt(expire_ms),
            },
        )
        return f'{event_type}: entitlement revoked'

    # RevenueCat may deliver other event types; deliberately no-op so it stops
    # retrying rather than treating an ignored event as an error.
    return f'ignored: {event_type}'