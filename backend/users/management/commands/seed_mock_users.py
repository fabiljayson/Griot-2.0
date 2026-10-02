"""Seed synthetic visitor and contributor accounts for local development."""

from datetime import timedelta
from random import Random

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import connections, transaction
from django.db.models import F
from django.utils import timezone

from config.safety import assert_safe_environment
from gamification.models import UserProfile
from stories.models import Story, StoryLike

User = get_user_model()

FIRST_NAMES = (
    'Abena', 'Aicha', 'Aissatou', 'Amina', 'Ama', 'Amadou', 'Amara', 'Andre',
    'Armand', 'Awa', 'Binta', 'Blaise', 'Brice', 'Carine', 'Cedric',
    'Chantal', 'Daniel', 'Djenabou', 'Didier', 'Doreen', 'Eboa', 'Elie',
    'Emmanuel', 'Esther', 'Fabrice', 'Fatou', 'Fatoumata', 'Flore', 'Grace',
    'Hadja', 'Hawa', 'Ibrahim', 'Imane', 'Imani', 'Ismael', 'Jean', 'Josiane',
    'Jules', 'Kadiatou', 'Kemi', 'Khadija', 'Koffi', 'Landry', 'Maimouna',
    'Mahamat', 'Mariam', 'Mireille', 'Moussa', 'Nadege', 'Nabil', 'Noura',
    'Odette', 'Olivier', 'Pascal', 'Prisca', 'Safia', 'Salome', 'Sandrine',
    'Serge', 'Sira', 'Solange', 'Suzanne', 'Ulrich', 'Yaa', 'Youssoufa',
    'Zainab',
)
LAST_NAMES = (
    'Abanda', 'Adebayo', 'Adeyemi', 'Atangana', 'Awono', 'Banda', 'Bate',
    'Bell', 'Biloa', 'Boateng', 'Dibango', 'Diallo', 'Djoumessi', 'Dlamini',
    'Eboa', 'Ekani', 'Eloundou', 'Essomba', 'Etoa', 'Etoga', 'Etoundi',
    'Fofana', 'Fokam', 'Fotso', 'Fotsing', 'Fouda', 'Jalloh', 'Kamara',
    'Kamga', 'Kameni', 'Keita', 'Kenfack', 'Konate', 'Kone', 'Mballa',
    'Mbarga', 'Mbang', 'Mbonjo', 'Meka', 'Mokoena', 'Momo', 'Moukoko',
    'Muna', 'Mvogo', 'Mvondo', 'Nanga', 'Ndam', 'Ndiaye', 'Ndlovu', 'Nganou',
    'Ngu', 'Nguema', 'Nguimfack', 'Ngono', 'Njoya', 'Nkem', 'Nkomo', 'Nkosi',
    'Nwosu', 'Ondoa', 'Osei', 'Owusu', 'Owona', 'Sarr', 'Takam', 'Talla',
    'Tchana', 'Tchinda', 'Tchoumi', 'Traore', 'Wamba', 'Yana', 'Moyo',
)


def _mock_name_pairs():
    pairs = [
        (first_name, last_name)
        for first_name in FIRST_NAMES
        for last_name in LAST_NAMES
    ]
    Random('griot-mock-names-v1').shuffle(pairs)
    return pairs


MOCK_NAME_PAIRS = _mock_name_pairs()


class Command(BaseCommand):
    help = 'Create mock visitors and contributors with story engagement and XP.'

    def add_arguments(self, parser):
        parser.add_argument('--visitors', type=int, default=400)
        parser.add_argument('--contributors', type=int, default=100)
        parser.add_argument(
            '--database',
            default='local',
            help='Database alias (must use SQLite; defaults to local).',
        )

    def handle(self, *args, **options):
        database = options['database']
        visitor_count = options['visitors']
        contributor_count = options['contributors']

        assert_safe_environment(
            'seed_mock_users',
            reason='it creates synthetic user accounts and engagement data.',
        )
        if connections[database].vendor != 'sqlite':
            raise CommandError('seed_mock_users only writes to SQLite databases.')
        if min(visitor_count, contributor_count) < 0:
            raise CommandError('Visitor and contributor counts cannot be negative.')
        if visitor_count + contributor_count > 500:
            raise CommandError('The combined mock user count cannot exceed 500.')

        stories = list(
            Story.objects.using(database)
            .filter(status=Story.Status.PUBLISHED)
            .order_by('pk')
        )
        if not stories:
            raise CommandError('Seed at least one published story first.')

        mock_email_prefixes = (
            'mock_visitor_',
            'mock_contributor_',
        )
        existing_usernames = set(
            User.objects.using(database)
            .exclude(email__startswith=mock_email_prefixes[0])
            .exclude(email__startswith=mock_email_prefixes[1])
            .values_list('username', flat=True)
        )
        created_users = 0
        created_likes = 0
        mock_users = []
        view_targets = {story.pk: 0 for story in stories}

        with transaction.atomic(using=database):
            for role, count, prefix, xp_base, xp_span in (
                ('visitor', visitor_count, 'mock_visitor', 100, 400),
                ('contributor', contributor_count, 'mock_contributor', 500, 1500),
            ):
                for index in range(1, count + 1):
                    identity_index = len(mock_users)
                    first_name, last_name = MOCK_NAME_PAIRS[identity_index]
                    username_base = f'{first_name}_{last_name}'.lower()
                    username = username_base
                    suffix = 2
                    while username in existing_usernames:
                        username = f'{username_base}_{suffix}'
                        suffix += 1
                    existing_usernames.add(username)
                    email = f'{prefix}_{index:04d}@example.invalid'
                    signup_date = timezone.now().replace(
                        hour=12, minute=0, second=0, microsecond=0
                    ) - timedelta(days=Random(username).randrange(30))
                    user, created = User.objects.db_manager(database).get_or_create(
                        email=email,
                        defaults={
                            'username': username,
                            'first_name': first_name,
                            'last_name': last_name,
                            'role': role,
                            'date_joined': signup_date,
                        },
                    )
                    if user.role != role:
                        raise CommandError(
                            f'Existing account {username} has role {user.role}, '
                            f'expected {role}.'
                        )
                    changed_fields = []
                    for field, value in (
                        ('username', username),
                        ('first_name', first_name),
                        ('last_name', last_name),
                        ('date_joined', signup_date),
                    ):
                        if getattr(user, field) != value:
                            setattr(user, field, value)
                            changed_fields.append(field)
                    if changed_fields:
                        user.save(using=database, update_fields=changed_fields)
                    if created:
                        user.set_unusable_password()
                        user.save(using=database, update_fields=['password'])
                        created_users += 1

                    sequence = len(mock_users)
                    like_story = stories[sequence % len(stories)]
                    xp = xp_base + (index * 37 % xp_span)
                    stories_read = 1 + (sequence * 7 % len(stories))
                    current_streak = sequence % 8
                    longest_streak = max(current_streak, sequence % 15)
                    UserProfile.objects.using(database).update_or_create(
                        user=user,
                        defaults={
                            'total_xp': xp,
                            'level': xp // 100 + 1,
                            'stories_read': stories_read,
                            'stories_completed': stories_read,
                            'quizzes_passed': sequence % 4,
                            'current_streak': current_streak,
                            'longest_streak': longest_streak,
                        },
                    )
                    mock_users.append((user, like_story))

                    for view_index in range(3):
                        view_story = stories[
                            (sequence * 5 + view_index * 3) % len(stories)
                        ]
                        view_targets[view_story.pk] += 1

            user_ids = [user.pk for user, _ in mock_users]
            existing_likes = set(
                StoryLike.objects.using(database)
                .filter(user_id__in=user_ids)
                .values_list('user_id', 'story_id')
            )
            new_likes = [
                StoryLike(user=user, story=story)
                for user, story in mock_users
                if (user.pk, story.pk) not in existing_likes
            ]
            StoryLike.objects.using(database).bulk_create(new_likes)
            created_likes = len(new_likes)

            like_increments = {}
            for like in new_likes:
                like_increments[like.story_id] = (
                    like_increments.get(like.story_id, 0) + 1
                )
            for story_id, increment in like_increments.items():
                Story.objects.using(database).filter(pk=story_id).update(
                    like_count=F('like_count') + increment
                )

            for story in stories:
                target_views = view_targets[story.pk]
                if story.view_count < target_views:
                    Story.objects.using(database).filter(pk=story.pk).update(
                        view_count=target_views
                    )

        self.stdout.write(
            self.style.SUCCESS(
                f'Processed {visitor_count} visitors and {contributor_count} '
                f'contributors; created {created_users} users and '
                f'{created_likes} likes, with leaderboard profiles and mock views.'
            )
        )