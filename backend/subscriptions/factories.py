"""Factories shared by the test modules that need an entitlement.

Deliberately not a `test*.py` module: its name keeps unittest discovery from
importing it as a suite, while the tests import it explicitly. Nothing here has
side effects beyond the rows it creates.

`grant_premium` writes the same row the RevenueCat webhook would write, with
`provider='manual'` — an administrator granting access from the Django admin
takes this path today, so tests exercising entitlement are not coupled to a
store sandbox.
"""

from .models import Subscription


def grant_premium(user, *, status=Subscription.Status.ACTIVE, period_end=None):
    """Give `user` an entitled subscription row (idempotent).

    `period_end=None` means "until told otherwise", which `is_entitled` treats
    as active for ACTIVE rows — the same shape as a manual admin grant.
    """
    subscription, _ = Subscription.objects.update_or_create(
        user=user,
        defaults={
            'status': status,
            'provider': Subscription.Provider.MANUAL,
            'current_period_end': period_end,
        },
    )
    return subscription


def revoke_premium(user):
    """Expire the account's subscription, if it has one."""
    Subscription.objects.filter(user=user).update(
        status=Subscription.Status.EXPIRED,
    )
