from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from .models import Payment, PremiumFeature, Subscription, SubscriptionPlan
from .services import has_feature_access, subscription_status

User = get_user_model()

PREMIUM_KEY = 'ai_video_generation'
FREE_KEY = 'consistency_confirmed'  # not in PREMIUM_FEATURES → free


def utc(offset_days):
    return timezone.now() + timedelta(days=offset_days)


class FeatureAccessTests(TestCase):
    """The gate: settings decide what is paid, the subscription decides who
    paid, and the kill switch decides what is live."""

    def setUp(self):
        self.reader = User.objects.create_user(
            username='reader', password='pw', role='visitor',
        )
        self.staff = User.objects.create_user(
            username='staff', password='pw', is_staff=True,
        )
        # The real server seeds these rows with `seed_premium_features`; the
        # test database starts empty, so create the same rows the gate reads.
        PremiumFeature.objects.get_or_create(
            key=PREMIUM_KEY,
            defaults={'label': 'AI video generation'},
        )
        PremiumFeature.objects.get_or_create(
            key='advanced_ai',
            defaults={'label': 'Advanced AI assistant'},
        )

    def test_free_feature_is_open_to_everyone(self):
        self.assertTrue(has_feature_access(None, FREE_KEY))
        self.assertTrue(has_feature_access(self.reader, FREE_KEY))

    def test_premium_feature_is_closed_to_anonymous(self):
        self.assertFalse(has_feature_access(None, PREMIUM_KEY))

    def test_premium_feature_is_closed_to_free_readers(self):
        self.assertFalse(has_feature_access(self.reader, PREMIUM_KEY))

    def test_active_subscription_unlocks_premium(self):
        Subscription.objects.create(
            user=self.reader,
            provider=Subscription.Provider.MANUAL,
            status=Subscription.Status.ACTIVE,
            current_period_end=utc(30),
        )
        self.assertTrue(has_feature_access(self.reader, PREMIUM_KEY))

    def test_trial_unlocks_premium(self):
        Subscription.objects.create(
            user=self.reader,
            status=Subscription.Status.TRIAL,
            current_period_end=utc(7),
        )
        self.assertTrue(has_feature_access(self.reader, PREMIUM_KEY))

    def test_cancelled_with_future_period_keeps_access(self):
        # "Won't renew" is not "no longer paid": the reader bought the period.
        Subscription.objects.create(
            user=self.reader,
            status=Subscription.Status.CANCELLED,
            current_period_end=utc(14),
        )
        self.assertTrue(has_feature_access(self.reader, PREMIUM_KEY))

    def test_cancelled_without_period_end_loses_access(self):
        Subscription.objects.create(
            user=self.reader,
            status=Subscription.Status.CANCELLED,
            current_period_end=None,
        )
        self.assertFalse(has_feature_access(self.reader, PREMIUM_KEY))

    def test_expired_subscription_loses_access(self):
        Subscription.objects.create(
            user=self.reader,
            status=Subscription.Status.EXPIRED,
            current_period_end=utc(-1),
        )
        self.assertFalse(has_feature_access(self.reader, PREMIUM_KEY))

    def test_active_subscription_past_period_end_loses_access(self):
        Subscription.objects.create(
            user=self.reader,
            status=Subscription.Status.ACTIVE,
            current_period_end=utc(-1),
        )
        self.assertFalse(has_feature_access(self.reader, PREMIUM_KEY))

    def test_staff_always_have_premium_access(self):
        self.assertTrue(has_feature_access(self.staff, PREMIUM_KEY))

    def test_kill_switched_feature_is_closed_even_to_subscribers(self):
        Subscription.objects.create(
            user=self.reader,
            status=Subscription.Status.ACTIVE,
            current_period_end=utc(30),
        )
        PremiumFeature.objects.filter(key=PREMIUM_KEY).update(enabled=False)
        self.assertFalse(has_feature_access(self.reader, PREMIUM_KEY))
        # Even staff lose a killed feature: it is off, not merely paid.
        self.assertFalse(has_feature_access(self.staff, PREMIUM_KEY))

    def test_configured_key_without_a_row_stays_gated(self):
        # Delete the seeded row: the key is still in settings, so it must
        # still be paid (a missing row defaults it to live, not to free).
        PremiumFeature.objects.filter(key=PREMIUM_KEY).delete()
        self.assertFalse(has_feature_access(self.reader, PREMIUM_KEY))


class SubscriptionStatusApiTests(APITestCase):
    def setUp(self):
        self.reader = User.objects.create_user(
            username='reader', password='pw', role='visitor',
        )
        self.client.force_authenticate(user=self.reader)

    def test_status_requires_authentication(self):
        self.client.force_authenticate(user=None)
        resp = self.client.get(reverse('subscriptions:status'))
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_status_reports_free_account_without_access(self):
        resp = self.client.get(reverse('subscriptions:status'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertFalse(resp.data['subscribed'])
        self.assertFalse(resp.data['entitled'])
        by_key = {f['key']: f for f in resp.data['features']}
        self.assertIn(PREMIUM_KEY, by_key)
        self.assertFalse(by_key[PREMIUM_KEY]['has_access'])

    def test_status_reports_subscriber_has_access(self):
        Subscription.objects.create(
            user=self.reader,
            provider=Subscription.Provider.REVENUECAT,
            status=Subscription.Status.ACTIVE,
            current_period_end=utc(30),
        )
        resp = self.client.get(reverse('subscriptions:status'))
        self.assertTrue(resp.data['subscribed'])
        self.assertTrue(resp.data['entitled'])
        self.assertEqual(resp.data['provider'], 'revenuecat')
        self.assertEqual(resp.data['status'], 'active')
        self.assertTrue(
            all(f['has_access'] for f in resp.data['features']),
        )

    def test_status_lists_only_configured_premium_features(self):
        resp = self.client.get(reverse('subscriptions:status'))
        keys = {f['key'] for f in resp.data['features']}
        self.assertEqual(keys, {'ai_video_generation', 'advanced_ai'})


class RevenueCatWebhookTests(APITestCase):
    URL = '/api/subscriptions/webhook/'
    secret = 'test-secret'

    def setUp(self):
        self.reader = User.objects.create_user(
            username='reader', password='pw', role='visitor',
        )
        self.other = User.objects.create_user(
            username='other', password='pw', role='visitor',
        )
        self.entitlement = override_settings(
            REVENUECAT_WEBHOOK_AUTH_TOKEN=self.secret,
        )
        self.entitlement.enable()

    def tearDown(self):
        self.entitlement.disable()

    def _post(self, event, token=None):
        headers = {}
        if token is not None:
            headers['HTTP_AUTHORIZATION'] = f'Bearer {token}'
        return self.client.post(
            self.URL,
            {'event': event},
            format='json',
            **headers,
        )

    def _purchase_event(self, event_type, **overrides):
        base = {
            'type': event_type,
            'app_user_id': str(self.reader.id),
            'product_id': 'griot_premium_monthly',
            'entitlement_ids': ['premium'],
            'purchased_at_ms': int(utc(0).timestamp() * 1000),
            'expiration_at_ms': int(utc(30).timestamp() * 1000),
        }
        base.update(overrides)
        return base

    def test_unconfigured_server_refuses_every_webhook(self):
        with override_settings(REVENUECAT_WEBHOOK_AUTH_TOKEN=''):
            resp = self._post(self._purchase_event('INITIAL_PURCHASE'))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_wrong_token_is_rejected(self):
        resp = self._post(
            self._purchase_event('INITIAL_PURCHASE'), token='not-the-secret',
        )
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_missing_token_is_rejected(self):
        resp = self._post(self._purchase_event('INITIAL_PURCHASE'))
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_initial_purchase_creates_active_subscription(self):
        resp = self._post(
            self._purchase_event('INITIAL_PURCHASE'), token=self.secret,
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        sub = Subscription.objects.get(user=self.reader)
        self.assertEqual(sub.status, Subscription.Status.ACTIVE)
        self.assertEqual(sub.provider, Subscription.Provider.REVENUECAT)
        self.assertEqual(sub.provider_customer_id, str(self.reader.id))
        self.assertTrue(sub.is_entitled)

    def test_trial_period_lends_a_trial_status(self):
        self._post(
            self._purchase_event(
                'INITIAL_PURCHASE', period_type='TRIAL',
            ),
            token=self.secret,
        )
        sub = Subscription.objects.get(user=self.reader)
        self.assertEqual(sub.status, Subscription.Status.TRIAL)
        self.assertTrue(sub.is_entitled)

    def test_renewal_reactivates_a_cancelled_row(self):
        Subscription.objects.create(
            user=self.reader,
            status=Subscription.Status.CANCELLED,
            current_period_end=utc(5),
        )
        self._post(
            self._purchase_event('RENEWAL', period_type='NORMAL'),
            token=self.secret,
        )
        sub = Subscription.objects.get(user=self.reader)
        self.assertEqual(sub.status, Subscription.Status.ACTIVE)

    def test_cancellation_keeps_entitlement_until_period_end(self):
        self._post(
            self._purchase_event('CANCELLATION', expiration_at_ms=int(utc(10).timestamp() * 1000)),
            token=self.secret,
        )
        sub = Subscription.objects.get(user=self.reader)
        self.assertEqual(sub.status, Subscription.Status.CANCELLED)
        self.assertTrue(sub.is_entitled)

    def test_expiration_revokes_entitlement(self):
        self._post(self._purchase_event('INITIAL_PURCHASE'), token=self.secret)
        self._post(
            self._purchase_event('EXPIRATION', expiration_at_ms=int(utc(-1).timestamp() * 1000)),
            token=self.secret,
        )
        sub = Subscription.objects.get(user=self.reader)
        self.assertEqual(sub.status, Subscription.Status.EXPIRED)
        self.assertFalse(sub.is_entitled)
        self.assertFalse(has_feature_access(self.reader, PREMIUM_KEY))

    def test_unknown_app_user_id_is_ignored_not_an_error(self):
        resp = self._post(
            self._purchase_event('INITIAL_PURCHASE', app_user_id='999999'),
            token=self.secret,
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(
            resp.data['outcome'], 'ignored: unknown app_user_id',
        )
        self.assertEqual(Subscription.objects.count(), 0)

    def test_irrelevant_event_type_is_a_noop(self):
        resp = self._post(
            self._purchase_event('CAMPAIGN_EVENT'), token=self.secret,
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(Subscription.objects.count(), 0)

    def test_transfer_moves_the_entitlement_to_the_new_owner(self):
        self._post(self._purchase_event('INITIAL_PURCHASE'), token=self.secret)
        resp = self._post(
            self._purchase_event(
                'TRANSFER', app_user_id=str(self.other.id),
            ),
            token=self.secret,
        )
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(
            resp.data['outcome'], 'transfer: entitlement moved',
        )
        # The old owner's row is superseded (same user is now the other one).
        self.assertTrue(
            Subscription.objects.get(user=self.other).is_entitled,
        )


class SubscriptionStatusPayloadTests(TestCase):
    def test_unsubscribed_payload_shape(self):
        user = User.objects.create_user(
            username='reader', password='pw', role='visitor',
        )
        payload = subscription_status(user)
        self.assertFalse(payload['subscribed'])
        self.assertIsNone(payload['status'])
        self.assertEqual(len(payload['features']), 2)

    def test_expired_row_is_reported_as_not_subscribed(self):
        user = User.objects.create_user(
            username='reader', password='pw', role='visitor',
        )
        Subscription.objects.create(
            user=user,
            status=Subscription.Status.EXPIRED,
            current_period_end=utc(-1),
        )
        payload = subscription_status(user)
        self.assertFalse(payload['subscribed'])
        self.assertEqual(payload['status'], 'expired')

class PendingSubscriptionTests(TestCase):
    """A pending row awaits the provider — it must grant nothing."""

    def setUp(self):
        self.reader = User.objects.create_user(
            username='reader', password='pw', role='visitor',
        )

    def test_pending_subscription_is_not_entitled(self):
        subscription = Subscription.objects.create(
            user=self.reader,
            status=Subscription.Status.PENDING,
            current_period_start=timezone.now(),
            current_period_end=utc(30),
        )
        self.assertFalse(subscription.is_entitled)
        self.assertFalse(
            has_feature_access(self.reader, PREMIUM_KEY),
        )

    def test_pending_status_is_reported_without_entitlement(self):
        Subscription.objects.create(
            user=self.reader,
            status=Subscription.Status.PENDING,
            current_period_end=utc(30),
        )
        payload = subscription_status(self.reader)
        self.assertEqual(payload['status'], 'pending')
        self.assertFalse(payload['entitled'])


class PlanShelfApiTests(APITestCase):
    def setUp(self):
        self.reader = User.objects.create_user(
            username='reader', password='pw', role='visitor',
        )
        self.client.force_authenticate(user=self.reader)
        self.monthly = SubscriptionPlan.objects.create(
            key='premium_monthly',
            name='Premium Monthly',
            price='4.99',
            interval=SubscriptionPlan.Interval.MONTH,
            duration_days=30,
            display_order=0,
        )
        self.yearly = SubscriptionPlan.objects.create(
            key='premium_yearly',
            name='Premium Yearly',
            price='39.99',
            interval=SubscriptionPlan.Interval.YEAR,
            duration_days=365,
            display_order=1,
        )
        self.retired = SubscriptionPlan.objects.create(
            key='premium_legacy',
            name='Legacy Plan',
            price='9.99',
            is_active=False,
        )

    def test_plans_require_authentication(self):
        self.client.force_authenticate(user=None)
        resp = self.client.get(reverse('subscriptions:plans'))
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_plans_lists_active_plans_in_order(self):
        resp = self.client.get(reverse('subscriptions:plans'))
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        keys = [p['key'] for p in resp.data]
        self.assertEqual(keys, ['premium_monthly', 'premium_yearly'])
        self.assertEqual(resp.data[0]['price'], '4.99')
        self.assertEqual(resp.data[0]['duration_days'], 30)

    def test_retired_plans_stay_off_the_shelf(self):
        resp = self.client.get(reverse('subscriptions:plans'))
        self.assertNotIn('premium_legacy', {p['key'] for p in resp.data})

    def test_status_payload_names_the_current_plan(self):
        Subscription.objects.create(
            user=self.reader,
            plan=self.yearly,
            provider=Subscription.Provider.MANUAL,
            status=Subscription.Status.ACTIVE,
            current_period_end=utc(365),
        )
        resp = self.client.get(reverse('subscriptions:status'))
        self.assertEqual(resp.data['plan'], 'premium_yearly')
        self.assertEqual(resp.data['plan_name'], 'Premium Yearly')


class DevCheckoutApiTests(APITestCase):
    """POST /api/subscriptions/checkout/ — a labelled stand-in for billing."""

    def setUp(self):
        self.reader = User.objects.create_user(
            username='reader', password='pw', role='visitor',
        )
        self.client.force_authenticate(user=self.reader)
        self.plan = SubscriptionPlan.objects.create(
            key='premium_monthly',
            name='Premium Monthly',
            price='4.99',
            interval=SubscriptionPlan.Interval.MONTH,
            duration_days=30,
        )

    def test_checkout_requires_authentication(self):
        self.client.force_authenticate(user=None)
        resp = self.client.post(
            reverse('subscriptions:checkout'),
            {'plan': 'premium_monthly'},
        )
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    @override_settings(SUBSCRIPTION_DEV_CHECKOUT=False)
    def test_checkout_is_refused_when_the_server_has_not_opted_in(self):
        resp = self.client.post(
            reverse('subscriptions:checkout'),
            {'plan': 'premium_monthly'},
        )
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(resp.data['code'], 'dev_checkout_disabled')
        self.assertFalse(
            Subscription.objects.filter(user=self.reader).exists(),
        )
        self.assertFalse(Payment.objects.filter(user=self.reader).exists())

    def test_checkout_without_a_plan_key_is_a_bad_request(self):
        resp = self.client.post(reverse('subscriptions:checkout'), {})
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(resp.data['code'], 'plan_required')

    def test_checkout_for_an_unknown_plan_is_a_404(self):
        resp = self.client.post(
            reverse('subscriptions:checkout'),
            {'plan': 'nope'},
        )
        self.assertEqual(resp.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(resp.data['code'], 'plan_not_found')

    def test_checkout_grants_one_period_and_records_the_reference(self):
        before = timezone.now()
        resp = self.client.post(
            reverse('subscriptions:checkout'),
            {'plan': 'premium_monthly'},
        )
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)

        subscription = Subscription.objects.get(user=self.reader)
        self.assertEqual(subscription.plan, self.plan)
        self.assertEqual(subscription.provider, Subscription.Provider.DEV)
        self.assertEqual(subscription.status, Subscription.Status.ACTIVE)
        self.assertTrue(subscription.is_entitled)
        self.assertGreater(subscription.current_period_end, before)

        payment = Payment.objects.get(user=self.reader)
        self.assertEqual(payment.plan, self.plan)
        self.assertEqual(payment.subscription, subscription)
        self.assertEqual(payment.provider, Payment.Provider.DEV)
        self.assertEqual(payment.status, Payment.Status.COMPLETED)
        # Compare as text: the in-test instance still holds the raw constructor
        # string, while the stored value comes back as a Decimal.
        self.assertEqual(str(payment.amount), '4.99')
        self.assertIn('no real payment', payment.note)
        self.assertTrue(payment.provider_reference.startswith('dev-'))

        # The response is a normal status payload plus an honest label.
        self.assertTrue(resp.data['entitled'])
        self.assertEqual(resp.data['plan'], 'premium_monthly')
        self.assertEqual(
            resp.data['payment_reference'],
            payment.provider_reference,
        )
        self.assertIn('no real payment', resp.data['notice'])

        # The new entitlement actually opens the paid gate.
        self.assertTrue(has_feature_access(self.reader, PREMIUM_KEY))

    def test_checkout_is_idempotent_within_the_granted_period(self):
        first = self.client.post(
            reverse('subscriptions:checkout'),
            {'plan': 'premium_monthly'},
        )
        second = self.client.post(
            reverse('subscriptions:checkout'),
            {'plan': 'premium_monthly'},
        )
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertEqual(second.status_code, status.HTTP_201_CREATED)
        self.assertEqual(
            Subscription.objects.filter(user=self.reader).count(),
            1,
        )
        # Each attempt is its own recorded payment.
        self.assertEqual(Payment.objects.filter(user=self.reader).count(), 2)

    def test_checkout_stores_no_cardholder_data(self):
        resp = self.client.post(
            reverse('subscriptions:checkout'),
            {'plan': 'premium_monthly'},
        )
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        payment = Payment.objects.get(user=self.reader)
        forbidden = {
            'card_number', 'pan', 'cvv', 'cvc', 'expiry', 'card',
            'cardholder', 'iban', 'account_number',
        }
        self.assertTrue(forbidden.isdisjoint(payment.__dict__))
        model_fields = {f.name for f in Payment._meta.get_fields()}
        self.assertTrue(forbidden.isdisjoint(model_fields))


class PlanSeedingTests(TestCase):
    """`seed_subscription_plans` mirrors settings into the database."""

    def test_seeding_is_idempotent_and_keeps_admin_retirements(self):
        from io import StringIO

        from django.core.management import call_command

        call_command('seed_subscription_plans', stdout=StringIO())
        self.assertEqual(SubscriptionPlan.objects.count(), 2)

        # An operator retires a plan; a reseed must not resurrect it.
        SubscriptionPlan.objects.filter(key='premium_monthly').update(
            is_active=False,
        )
        call_command('seed_subscription_plans', stdout=StringIO())
        self.assertEqual(SubscriptionPlan.objects.count(), 2)
        self.assertFalse(
            SubscriptionPlan.objects.get(key='premium_monthly').is_active,
        )

        # Price changes in settings flow through on reseed.
        SubscriptionPlan.objects.filter(key='premium_yearly').update(
            price='29.99',
        )
        call_command('seed_subscription_plans', stdout=StringIO())
        expected = next(
            p for p in settings.SUBSCRIPTION_PLANS
            if p['key'] == 'premium_yearly'
        )
        self.assertEqual(
            str(
                SubscriptionPlan.objects.get(key='premium_yearly').price,
            ),
            expected['price'],
        )
