import json

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.db import IntegrityError, connection, transaction
from django.test import TransactionTestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .models import UserRole

User = get_user_model()


class CacheIsolatedTestCase(APITestCase):
    """APITestCase that starts each test method with a clean cache.

    DRF throttle counters live in the process-wide default cache, which Django
    never clears between tests. Without this, the strict 5/min auth budget is
    shared by every auth request in the whole suite — test classes run in
    alphabetical order, so whichever runs first exhausts the budget and
    throttles the rest (and LocMemCache culling past 300 keys can randomly
    evict the throttle key mid-test).
    """

    def setUp(self):
        super().setUp()
        cache.clear()

REGISTER_URL = reverse('users:register')
TOKEN_URL = reverse('users:token_obtain_pair')
REFRESH_URL = reverse('users:token_refresh')
ME_URL = reverse('me')


class RegisterTests(CacheIsolatedTestCase):
    def test_register_default_role_is_visitor(self):
        resp = self.client.post(REGISTER_URL, {
            'username': 'explorer',
            'email': 'explorer@example.com',
            'password': 'hunter2secure',
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['user']['role'], UserRole.VISITOR)
        self.assertTrue(User.objects.filter(username='explorer').exists())

    def test_register_as_contributor(self):
        resp = self.client.post(REGISTER_URL, {
            'username': 'author',
            'email': 'author@example.com',
            'password': 'hunter2secure',
            'role': UserRole.CONTRIBUTOR,
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['user']['role'], UserRole.CONTRIBUTOR)

    def test_cannot_self_assign_institution_manager_or_admin(self):
        for forbidden in (UserRole.INSTITUTION_MANAGER, UserRole.ADMIN):
            resp = self.client.post(REGISTER_URL, {
                'username': f'user_{forbidden}',
                'email': f'user_{forbidden}@example.com',
                'password': 'hunter2secure',
                'role': forbidden,
            })
            self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_duplicate_email_rejected(self):
        User.objects.create_user('first', email='dup@example.com', password='hunter2secure')
        resp = self.client.post(REGISTER_URL, {
            'username': 'second',
            'email': 'DUP@example.com',
            'password': 'hunter2secure',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_replay_of_committed_registration_is_idempotent(self):
        """A client that re-sends an identical register must not get a 400.

        The hosted backend sleeps on Render's free tier. When it cold-starts
        mid-request the response can outlast the client's timeout, so the
        client re-POSTs the same body. The first POST already committed the
        user, so the replay has to resolve to the existing account instead of
        'A user with this email already exists.'
        """
        payload = {
            'username': 'replay',
            'email': 'replay@example.com',
            'password': 'hunter2secure',
        }
        first = self.client.post(REGISTER_URL, payload)
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)

        replay = self.client.post(REGISTER_URL, payload)

        self.assertEqual(replay.status_code, status.HTTP_200_OK)
        self.assertEqual(replay.data['user']['id'], first.data['user']['id'])
        self.assertEqual(
            User.objects.filter(email__iexact='replay@example.com').count(), 1
        )

    def test_replay_with_different_password_is_rejected(self):
        """Idempotency must not become an account-takeover oracle."""
        payload = {
            'username': 'replay',
            'email': 'replay@example.com',
            'password': 'hunter2secure',
        }
        self.client.post(REGISTER_URL, payload)

        resp = self.client.post(REGISTER_URL, {**payload, 'password': 'other-secret'})

        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        # Still refused, but the response must not name the colliding field:
        # identifying "email" turns this endpoint into a membership oracle
        # (F-03). A generic refusal is enough to reject the replay.
        self.assertIn('detail', resp.data)
        self.assertNotIn('email', resp.data)

    def test_weak_password_rejected(self):
        resp = self.client.post(REGISTER_URL, {
            'username': 'weak',
            'email': 'weak@example.com',
            'password': 'short',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_long_but_common_password_rejected(self):
        """F-04: `min_length=8` on the field was the only check in force, so a
        password long enough to clear the length rule was still accepted even
        though AUTH_PASSWORD_VALIDATORS configures CommonPasswordValidator.
        These pass the length rule and must still be refused."""
        for password in ('password1', 'qwerty123', 'letmein1'):
            with self.subTest(password=password):
                resp = self.client.post(REGISTER_URL, {
                    'username': f'weak_{password}',
                    'email': f'{password}@example.com',
                    'password': password,
                })
                self.assertEqual(
                    resp.status_code, status.HTTP_400_BAD_REQUEST,
                    f'API accepted {password!r}, which the configured '
                    f'password validators reject',
                )

    def test_strong_password_accepted(self):
        """A compliant password still registers (guards against over-blocking)."""
        resp = self.client.post(REGISTER_URL, {
            'username': 'stronguser',
            'email': 'strong@example.com',
            'password': 'Correct-Horse-9',
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)


class RegistrationDoesNotLeakPII(CacheIsolatedTestCase):
    """The registration endpoint must not become a directory lookup.

    `RegisterView` re-resolves an existing account on an exact replay, which
    means a request carrying a known email can hit a branch that serializes that
    account. The branch is gated on the correct username *and* password, so the
    response is only ever available to someone who already holds the credential
    — but the gate is the whole control, and a regression here would republish
    first name, last name, role, institution and join date to an anonymous
    caller who guessed an address. These tests pin the gate shut.
    """

    def setUp(self):
        super().setUp()
        self.victim = User.objects.create_user(
            'victim',
            email='victim@example.com',
            password='hunter2secure',
            first_name='Amara',
            last_name='Okonkwo',
        )
        self.victim.institution = 'Museum of the Delta'
        self.victim.save()

    def _assert_no_pii(self, payload):
        resp = self.client.post(REGISTER_URL, payload)
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        body = json.dumps(resp.data)
        for leak in ('Amara', 'Okonkwo', 'Museum of the Delta', 'date_joined'):
            self.assertNotIn(leak, body)

    def test_known_email_with_wrong_password_leaks_nothing(self):
        self._assert_no_pii({
            'username': 'victim',
            'email': 'victim@example.com',
            'password': 'guessing',
        })

    def test_known_email_with_known_username_but_wrong_password_leaks_nothing(self):
        # The closest an attacker gets: the username is public, the password is
        # not. This is the case that must still return nothing.
        self._assert_no_pii({
            'username': 'victim',
            'email': 'victim@example.com',
            'password': 'hunter2secureX',
        })

    def test_known_email_with_a_different_username_leaks_nothing(self):
        self._assert_no_pii({
            'username': 'attacker',
            'email': 'victim@example.com',
            'password': 'hunter2secure',
        })


class RegistrationRejectsMalformedEmailWithoutCrashing(CacheIsolatedTestCase):
    """A non-string `email` must be a 400, not a 500.

    The view used to run its replay lookup on raw `request.data` before calling
    `is_valid()`, and the lookup normalizes with `.strip()`. A JSON body
    carrying `email` as a list or a number therefore reached `.strip()` as a
    list/int and raised AttributeError — an unauthenticated 500 that also skips
    the serializer's own field validation entirely.
    """

    def _post_json(self, payload):
        return self.client.post(
            REGISTER_URL,
            data=json.dumps(payload),
            content_type='application/json',
        )

    def test_email_as_list_is_rejected_cleanly(self):
        resp = self._post_json({
            'username': 'listy',
            'email': ['a@example.com', 'b@example.com'],
            'password': 'hunter2secure',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('email', resp.data)
        self.assertFalse(User.objects.filter(username='listy').exists())

    def test_email_as_number_is_rejected_cleanly(self):
        resp = self._post_json({
            'username': 'numeric',
            'email': 5,
            'password': 'hunter2secure',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('email', resp.data)
        self.assertFalse(User.objects.filter(username='numeric').exists())

    def test_malformed_email_does_not_bypass_password_policy(self):
        """A body that fails email validation must not create an account."""
        resp = self._post_json({
            'username': 'sneaky',
            'email': ['a@example.com'],
            'password': 'short',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(User.objects.filter(username='sneaky').exists())

    def test_replay_path_still_works_after_validation_reorder(self):
        """Idempotent replay must survive validating first.

        The credential in the replay body is validated (min length 8) exactly as
        in a fresh registration, so reordering the checks cannot have made a
        legitimate replay start failing.
        """
        payload = {
            'username': 'reorder',
            'email': 'reorder@example.com',
            'password': 'hunter2secure',
        }
        first = self.client.post(REGISTER_URL, payload)
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)

        replay = self.client.post(REGISTER_URL, payload)
        self.assertEqual(replay.status_code, status.HTTP_200_OK)
        self.assertEqual(replay.data['user']['id'], first.data['user']['id'])


class EmailUniquenessTests(CacheIsolatedTestCase):
    """The database, not just the serializer, must reject a duplicate email.

    `validate_email` is a check-then-act guard, so two concurrent requests can
    both pass it. Without a unique constraint both rows land and the email is
    permanently unusable. Case variants must collide too, because every lookup
    in the codebase uses `email__iexact`.
    """

    def test_case_insensitive_duplicate_email_cannot_be_inserted(self):
        User.objects.create_user('first', email='dupe@example.com', password='hunter2secure')

        with self.assertRaises(IntegrityError), transaction.atomic():
            User.objects.create_user('second', email='DUPE@example.com', password='hunter2secure')

        self.assertEqual(
            User.objects.filter(email__iexact='dupe@example.com').count(), 1
        )

    def test_blank_emails_are_not_conflicting(self):
        """`email` is blank=True, so several users may legitimately have none."""
        User.objects.create_user('noemail1', email='', password='hunter2secure')
        User.objects.create_user('noemail2', email='', password='hunter2secure')

        self.assertEqual(User.objects.filter(email='').count(), 2)

    def test_unique_violation_is_mapped_to_400_by_the_exception_handler(self):
        """The handler is the last line of defence for a racing duplicate.

        The endpoint cannot reach it — `validate_email` and the view's
        `find_by_email` both reject a known address first — so the handler is
        exercised directly here.
        """
        from config.exception_handler import api_exception_handler

        User.objects.create_user('first', email='race@example.com', password='hunter2secure')

        try:
            with transaction.atomic():
                User.objects.create_user(
                    'second', email='RACE@example.com', password='hunter2secure'
                )
        except IntegrityError as exc:
            response = api_exception_handler(exc, {})
        else:  # pragma: no cover - the insert above must fail
            self.fail('expected an IntegrityError')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        body = json.dumps(response.data)
        self.assertNotIn('SELECT', body)
        self.assertNotIn('INSERT', body)
        self.assertNotIn('Traceback', body)


class DuplicateEmailDedupeTests(TransactionTestCase):
    """The data step that runs before the constraint is added.

    Production may already hold duplicate addresses created by the retried
    registration bug. If the dedupe is wrong the migration fails outright and
    the deploy halts, so its behaviour is pinned here.

    `TransactionTestCase` rather than the `APITestCase` base: SQLite refuses to
    run its schema editor inside the transaction that `APITestCase` wraps each
    test in, and this test has to add and drop the constraint. No HTTP is
    involved, so nothing is lost by leaving the DRF client behind.
    """

    CONSTRAINT = 'uniq_user_email_case_insensitive'

    def setUp(self):
        super().setUp()
        cache.clear()
        self._drop_constraint()

    def tearDown(self):
        # Only restore what a test left dropped; a test that re-added the
        # constraint itself has already put the schema back.
        if not self._constraint_present:
            self._add_constraint()
        super().tearDown()

    def _drop_constraint(self):
        constraint = next(
            c for c in User._meta.constraints if c.name == self.CONSTRAINT
        )
        with connection.schema_editor() as editor:
            editor.remove_constraint(User, constraint)
        self._constraint_present = False

    def _add_constraint(self):
        constraint = next(
            c for c in User._meta.constraints if c.name == self.CONSTRAINT
        )
        with connection.schema_editor() as editor:
            editor.add_constraint(User, constraint)
        self._constraint_present = True

    def _resolve(self):
        from importlib import import_module

        from django.apps import apps as global_apps

        module = import_module(
            'users.migrations.0002_user_uniq_user_email_case_insensitive'
        )

        class _SchemaEditor:
            connection = connection

        module.resolve_duplicate_emails(global_apps, _SchemaEditor())

    def test_keeps_earliest_account_and_clears_the_duplicate_email(self):
        older = User.objects.create_user(
            'older', email='shared@example.com', password='hunter2secure'
        )
        newer = User.objects.create_user(
            'newer', email='SHARED@example.com', password='hunter2secure'
        )

        self._resolve()

        older.refresh_from_db()
        newer.refresh_from_db()
        self.assertEqual(older.email, 'shared@example.com')
        self.assertEqual(newer.email, '')
        # Both accounts survive, so neither is locked out of signing in.
        self.assertEqual(User.objects.filter(username__in=['older', 'newer']).count(), 2)

    def test_constraint_applies_cleanly_after_dedupe(self):
        """The whole migration sequence: duplicates in, constraint lands."""
        User.objects.create_user(
            'older', email='shared@example.com', password='hunter2secure'
        )
        User.objects.create_user(
            'newer', email='SHARED@example.com', password='hunter2secure'
        )

        self._resolve()
        self._add_constraint()

        with self.assertRaises(IntegrityError), transaction.atomic():
            User.objects.create_user(
                'third', email='ShArEd@example.com', password='hunter2secure'
            )

    def test_is_idempotent(self):
        User.objects.create_user('solo', email='solo@example.com', password='hunter2secure')

        self._resolve()
        self._resolve()

        self.assertEqual(
            User.objects.get(username='solo').email, 'solo@example.com'
        )

    def test_blank_emails_are_left_alone(self):
        User.objects.create_user('blank1', email='', password='hunter2secure')
        User.objects.create_user('blank2', email='', password='hunter2secure')

        self._resolve()

        self.assertEqual(User.objects.filter(email='').count(), 2)


class TokenTests(CacheIsolatedTestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            'griot', email='griot@example.com', password='hunter2secure'
        )
        self.user.role = UserRole.CONTRIBUTOR
        self.user.save()

    def test_token_obtain_returns_jwt_pair_with_role_claim(self):
        resp = self.client.post(TOKEN_URL, {
            'username': 'griot',
            'password': 'hunter2secure',
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('access', resp.data)
        self.assertIn('refresh', resp.data)
        # Decode the access token and assert the role claim is embedded.
        from rest_framework_simplejwt.tokens import AccessToken
        token = AccessToken(resp.data['access'])
        self.assertEqual(token['role'], UserRole.CONTRIBUTOR)
        self.assertEqual(token['username'], 'griot')

    def test_token_obtain_wrong_password(self):
        resp = self.client.post(TOKEN_URL, {
            'username': 'griot',
            'password': 'wrong-password',
        })
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_refresh_rotates_tokens(self):
        obtain = self.client.post(TOKEN_URL, {
            'username': 'griot',
            'password': 'hunter2secure',
        })
        refresh = obtain.data['refresh']
        resp = self.client.post(REFRESH_URL, {'refresh': refresh})
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('access', resp.data)
        self.assertIn('refresh', resp.data)


class MeTests(CacheIsolatedTestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            'curator', email='curator@example.com', password='hunter2secure'
        )

    def _auth(self):
        self.client.force_authenticate(self.user)

    def test_me_requires_authentication(self):
        resp = self.client.get(ME_URL)
        self.assertEqual(resp.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_me_returns_profile(self):
        self._auth()
        resp = self.client.get(ME_URL)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['username'], 'curator')
        self.assertIn('role', resp.data)

    def test_me_rejects_role_self_elevation(self):
        self._auth()
        resp = self.client.patch(ME_URL, {'role': UserRole.ADMIN})
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.user.refresh_from_db()
        self.assertEqual(self.user.role, UserRole.VISITOR)

    def test_me_allows_profile_field_update(self):
        self._auth()
        resp = self.client.patch(ME_URL, {'first_name': 'Amina'})
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.user.refresh_from_db()
        self.assertEqual(self.user.first_name, 'Amina')

    def test_delete_account_removes_user(self):
        self._auth()
        resp = self.client.delete(ME_URL)
        self.assertEqual(resp.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(User.objects.filter(username='curator').exists())


class AuthThrottleTests(CacheIsolatedTestCase):
    """Strict auth throttling: 5 requests/minute (Task 2.1).

    These tests verify throttling behavior. They run only when the 'auth'
    throttle rate is actually strict (5/min, the dev/prod default) and are
    skipped under config.settings.test, which raises the rates to 10000/min
    so ordinary unit tests never hit rate limits.
    """

    def _auth_throttle_is_strict(self):
        from rest_framework.settings import api_settings
        rates = api_settings.DEFAULT_THROTTLE_RATES or {}
        auth_rate = rates.get('auth', '')
        try:
            num = int(auth_rate.split('/')[0])
        except (ValueError, IndexError):
            return False
        return 0 < num <= 5

    def test_auth_endpoint_throttled_after_5_requests(self):
        if not self._auth_throttle_is_strict():
            self.skipTest('Auth throttling not strict in these settings')
        
        User.objects.create_user('throttle', password='hunter2secure')
        for _ in range(5):
            resp = self.client.post(TOKEN_URL, {
                'username': 'throttle',
                'password': 'wrong-password',
            })
            self.assertNotEqual(resp.status_code, status.HTTP_429_TOO_MANY_REQUESTS)

        # The 6th request within the minute window is throttled.
        resp = self.client.post(TOKEN_URL, {
            'username': 'throttle',
            'password': 'wrong-password',
        })
        self.assertEqual(resp.status_code, status.HTTP_429_TOO_MANY_REQUESTS)

    def test_register_endpoint_throttled(self):
        if not self._auth_throttle_is_strict():
            self.skipTest('Auth throttling not strict in these settings')
        
        for i in range(5):
            self.client.post(REGISTER_URL, {
                'username': f'user{i}',
                'email': f'user{i}@example.com',
                'password': 'hunter2secure',
            })
        resp = self.client.post(REGISTER_URL, {
            'username': 'blocked',
            'email': 'blocked@example.com',
            'password': 'hunter2secure',
        })
        self.assertEqual(resp.status_code, status.HTTP_429_TOO_MANY_REQUESTS)
