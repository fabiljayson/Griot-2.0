from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .models import UserRole

User = get_user_model()

REGISTER_URL = reverse('users:register')
TOKEN_URL = reverse('users:token_obtain_pair')
REFRESH_URL = reverse('users:token_refresh')
ME_URL = reverse('me')


class RegisterTests(APITestCase):
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

    def test_weak_password_rejected(self):
        resp = self.client.post(REGISTER_URL, {
            'username': 'weak',
            'email': 'weak@example.com',
            'password': 'short',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)


class TokenTests(APITestCase):
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


class MeTests(APITestCase):
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


class AuthThrottleTests(APITestCase):
    """Strict auth throttling: 5 requests/minute (Task 2.1).

    These tests verify throttling behavior. They are skipped when throttling
    is disabled in test settings (DJANGO_SETTINGS_MODULE=config.settings.test).
    """

    def _is_throttling_enabled(self):
        from django.conf import settings
        from rest_framework.settings import api_settings
        return bool(api_settings.DEFAULT_THROTTLE_RATES)

    def test_auth_endpoint_throttled_after_5_requests(self):
        if not self._is_throttling_enabled():
            self.skipTest('Throttling disabled in test settings')
        
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
        if not self._is_throttling_enabled():
            self.skipTest('Throttling disabled in test settings')
        
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
