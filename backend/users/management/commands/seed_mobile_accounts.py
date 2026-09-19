"""
Management command to seed the demo accounts advertised by the mobile app.

Mirrors `frontend/lib/core/constants/pre_registered_accounts.dart` so the
credentials the app shows in its demo-account picker actually exist on the
backend. Keep the two lists in sync.

Existing usernames are never modified — only newly created accounts get the
advertised credentials.

Usage:
    python manage.py seed_mobile_accounts
"""

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand

User = get_user_model()

# Mirrors PreRegisteredAccounts.accounts in
# frontend/lib/core/constants/pre_registered_accounts.dart
MOBILE_ACCOUNTS = [
    # Visitor accounts
    {
        'username': 'visitor1',
        'email': 'visitor1@griot-ai.com',
        'password': 'Visitor123!',
        'first_name': 'Amara',
        'last_name': 'Nkomo',
        'role': 'visitor',
    },
    {
        'username': 'visitor2',
        'email': 'visitor2@griot-ai.com',
        'password': 'Visitor123!',
        'first_name': 'Kofi',
        'last_name': 'Asante',
        'role': 'visitor',
    },
    {
        'username': 'visitor3',
        'email': 'visitor3@griot-ai.com',
        'password': 'Visitor123!',
        'first_name': 'Fatima',
        'last_name': 'Diallo',
        'role': 'visitor',
    },
    # Contributor accounts
    {
        'username': 'contributor1',
        'email': 'contributor1@griot-ai.com',
        'password': 'Contributor123!',
        'first_name': 'Nana',
        'last_name': 'Yemo',
        'role': 'contributor',
    },
    {
        'username': 'contributor2',
        'email': 'contributor2@griot-ai.com',
        'password': 'Contributor123!',
        'first_name': 'Ama',
        'last_name': 'Ata',
        'role': 'contributor',
    },
    {
        'username': 'griot_ama',
        'email': 'griot@griot-ai.com',
        'password': 'Griot2024!',
        'first_name': 'Ama',
        'last_name': 'Ata',
        'role': 'contributor',
    },
    # Institution Manager accounts
    {
        'username': 'manager1',
        'email': 'manager1@griot-ai.com',
        'password': 'Manager123!',
        'first_name': 'Jean',
        'last_name': 'Moulin',
        'role': 'institution_manager',
        'institution': 'National Museum of Cameroon',
    },
    {
        'username': 'museum_bamoun',
        'email': 'bamoun@griot-ai.com',
        'password': 'Bamoun2024!',
        'first_name': 'Sultan',
        'last_name': 'Ibrahim',
        'role': 'institution_manager',
        'institution': 'Bamoun Palace Museum',
    },
    # Admin accounts — NOTE: 'admin' usually already exists as the platform
    # superuser (admin@africanteller.com). Existing usernames are skipped.
    {
        'username': 'admin',
        'email': 'admin@griot-ai.com',
        'password': 'Admin2024!',
        'first_name': 'Super',
        'last_name': 'Admin',
        'role': 'admin',
    },
    {
        'username': 'admin_test',
        'email': 'admin.test@griot-ai.com',
        'password': 'TestAdmin123!',
        'first_name': 'Test',
        'last_name': 'Administrator',
        'role': 'admin',
    },
]


class Command(BaseCommand):
    help = (
        'Create the demo accounts advertised by the mobile app '
        '(pre_registered_accounts.dart). Existing usernames are skipped.'
    )

    def handle(self, *args, **options):
        created_count = 0
        skipped_count = 0

        for fields in MOBILE_ACCOUNTS:
            username = fields['username']
            user, created = User.objects.get_or_create(
                username=username,
                defaults={
                    'email': fields['email'],
                    'first_name': fields['first_name'],
                    'last_name': fields['last_name'],
                    'role': fields['role'],
                    'institution': fields.get('institution', ''),
                },
            )
            if created:
                user.set_password(fields['password'])
                user.save(update_fields=['password'])
                created_count += 1
                self.stdout.write(f'  Created user: {username} ({fields["email"]})')
            else:
                skipped_count += 1
                self.stdout.write(
                    self.style.WARNING(
                        f'  Skipped existing user: {username} '
                        '(not modified)'
                    )
                )

        self.stdout.write(
            self.style.SUCCESS(
                f'Successfully seeded mobile accounts: '
                f'{created_count} created, {skipped_count} skipped.'
            )
        )
