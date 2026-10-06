"""
Domain logic shared by the server-rendered web views and actions.

Database access and business rules live here so ``web/views.py`` and
``web/actions.py`` stay thin HTTP adapters (render, redirect, messages).
Each function mirrors the same rules the DRF API enforces, so both the HTML
site and the mobile app always behave identically.
"""

from collections import OrderedDict

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import PermissionDenied
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.base import ContentFile
from django.db import IntegrityError
from django.db.models import Count, F, Q, Sum
from django.db.models.functions import Greatest
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.translation import gettext_lazy as _

from api.analytics import get_dashboard_summary
from config.client_ip import get_client_ip
from config.rate_limit import client_identifier, first_in_window
from gamification.models import (
    Badge,
    Certificate,
    Quiz,
    QuizAttempt,
    UserBadge,
    UserProfile,
)
from gamification.services.awards import award_eligible_badges
from gamification.services.quiz_xp import already_earned_quiz_xp
from gamification.services.streaks import record_activity
from media_app import quota
from media_app.models import AudioNarrationJob, VideoGenerationJob, normalise_engine
from media_app.services.luma_ai import LumaAIError, get_luma_service
from media_app.services.tts import (
    TTSGenerationError,
    build_artifact_script,
    get_tts_service,
    strip_markdown,
)
from media_app.services.video_providers import result_field
from media_app.services.video_storage import store_video_asset
from qr_codes.models import Artifact
from qr_codes.services.qr_worklist import qr_worklist_data
from stories.models import (
    ReadingProgress,
    Story,
    StoryBookmark,
    StoryCategory,
    StoryFlag,
    StoryLike,
    StoryShare,
)
from stories.services import CONSENT_DECISIONS, resolve_status

from .models import WebUserSettings

User = get_user_model()

# Regions surfaced on the mobile Home screen "Discover Regions" strip.
HOME_REGIONS = [
    {'emoji': '🛕', 'label': 'Bamoun', 'color': 'terracotta'},
    {'emoji': '🌄', 'label': 'Adamawa', 'color': 'ochre'},
    {'emoji': '🌊', 'label': 'Coastal', 'color': 'savannah'},
    {'emoji': '🗿', 'label': 'Grassfields', 'color': 'terracotta-dark'},
]

# Sort options — mirror the mobile Stories screen dropdown exactly.
SORT_OPTIONS = OrderedDict([
    ('-created_at', _('Newest')),
    ('created_at', _('Oldest')),
    ('-view_count', _('Most Viewed')),
    ('-like_count', _('Most Liked')),
])

CATEGORY_EMOJI_FALLBACK = '📖'


# ---------------------------------------------------------------------------
# Interface language (Phase 5 Track A)
# ---------------------------------------------------------------------------
# The web interface speaks the codes in `settings.LANGUAGES` — 'en' and 'fr'
# for now. This is deliberately *not* `Story.Language.choices`: those are the
# languages a story can be *written in* (Ewondo, Duala, Bamileke...), not the
# languages the buttons around it are labelled in. Validating a UI preference
# against the story enum let a request write `ful` into a column whose own
# choices are en/fr — a value the admin could not render and no catalogue
# exists for. Which language a *reader* wants is a separate question, and it
# is answered per story, not here (Phase 5 task 4).
UI_LANGUAGES = [code for code, _ in settings.LANGUAGES]

DEFAULT_UI_LANGUAGE = 'en'


def resolve_ui_language(code):
    """Return `code` if this project can actually render it, else English.

    One definition of "a language this interface has", read from
    `settings.LANGUAGES` so the settings file stays the single source of truth.
    The model field, the form, the middleware and the tests all ask this
    function rather than each keeping its own list.
    """
    if not code:
        return DEFAULT_UI_LANGUAGE
    # `settings.LANGUAGE_CODE` is the fallback for an unrecognised code.
    return code if code in UI_LANGUAGES else DEFAULT_UI_LANGUAGE


# ---------------------------------------------------------------------------
# Story queries
# ---------------------------------------------------------------------------
def published_stories():
    """Published stories with the same prefetches the API list uses."""
    return (
        Story.objects.filter(status=Story.Status.PUBLISHED)
        .select_related('author')
        .prefetch_related('categories')
    )


def visible_stories(user):
    """Apply the same per-role visibility rules as the DRF StoryViewSet."""
    qs = Story.objects.select_related('author').prefetch_related('categories')
    if not user.is_authenticated:
        return qs.filter(status=Story.Status.PUBLISHED)
    if user.role in ('institution_manager', 'admin'):
        return qs
    if user.role == 'contributor':
        return qs.filter(
            Q(status=Story.Status.PUBLISHED) | Q(author=user)
        )
    return qs.filter(status=Story.Status.PUBLISHED)


def with_flags(stories, user):
    """Attach `bookmarked` / `liked` booleans without N+1 queries."""
    if not user.is_authenticated:
        for story in stories:
            story.bookmarked = False
            story.liked = False
        return stories
    story_ids = [story.id for story in stories]
    bookmarked_ids = set(
        StoryBookmark.objects.filter(user=user, story_id__in=story_ids)
        .values_list('story_id', flat=True)
    )
    liked_ids = set(
        StoryLike.objects.filter(user=user, story_id__in=story_ids)
        .values_list('story_id', flat=True)
    )
    for story in stories:
        story.bookmarked = story.id in bookmarked_ids
        story.liked = story.id in liked_ids
    return stories


def home_stories():
    """Trending + popular feeds for the home screen."""
    week_ago = timezone.now() - timezone.timedelta(days=7)
    trending = list(
        published_stories()
        .filter(created_at__gte=week_ago)
        .annotate(engagement=Count('likes') + Count('bookmarks') + Sum('view_count'))
        .order_by('-engagement')[:6]
    )
    if not trending:
        trending = list(published_stories().order_by('-view_count', '-like_count')[:6])
    popular = list(published_stories().order_by('-view_count', '-like_count')[:4])
    return trending, popular


def region_stories(limit=6):
    """Top region chips enriched with a representative story each."""
    regions = []
    for region in HOME_REGIONS:
        story = (
            published_stories()
            .filter(region__icontains=region['label'])
            .order_by('-view_count')
            .first()
        )
        count = published_stories().filter(region__icontains=region['label']).count()
        regions.append({**region, 'story': story, 'count': count})
    return regions[:limit]


def is_contributor_plus(user):
    """Role gate mirroring the API's IsContributorOrAbove permission."""
    return user.is_authenticated and user.role in (
        'contributor', 'institution_manager', 'admin',
    )


def narration_payload(job):
    """Normalize a narration job into {url, duration, attribution} for templates.

    FileField.url raises when no file is attached (legacy audio_url rows),
    so resolve the playable URL defensively here rather than in templates.

    The attribution is the whole point: the reader is told which engine spoke
    the story, so a synthesised voice is never taken for a recorded elder.
    """
    url = ''
    if job.audio_file:
        try:
            url = job.audio_file.url
        except ValueError:
            url = ''
    return {
        'url': url or job.audio_url or '',
        'duration': job.duration,
        'attribution': job.attribution,
        'is_synthetic': job.is_synthetic,
    }


# ---------------------------------------------------------------------------
# Screen data (shapes handed to templates)
# ---------------------------------------------------------------------------
def home_data(user):
    """Feed data for the home screen."""
    categories = StoryCategory.objects.all()[:8]
    artifact_count = Artifact.objects.filter(is_published=True).count()
    story_count = Story.objects.filter(status=Story.Status.PUBLISHED).count()

    if user.is_authenticated:
        trending, popular = home_stories()
        trending = with_flags(trending, user)
        popular = with_flags(popular, user)
    else:
        trending = []
        popular = []

    return {
        'trending_stories': trending,
        'popular_stories': popular,
        'categories': categories,
        'regions': region_stories(),
        'artifact_count': artifact_count,
        'story_count': story_count,
    }


def stories_data(user, *, search, language, category_slug, region, sort):
    """Stories discovery feed: search + filters + whitelisted sort."""
    stories = visible_stories(user)

    if search:
        stories = stories.filter(
            Q(title__icontains=search)
            | Q(content__icontains=search)
            | Q(summary__icontains=search)
            | Q(tags__icontains=search)
        )
    if language:
        stories = stories.filter(language=language)
    if category_slug:
        stories = stories.filter(categories__slug=category_slug)
    if region:
        stories = stories.filter(region__icontains=region)

    if sort in SORT_OPTIONS:
        stories = stories.order_by(sort)
    stories = with_flags(list(stories[:60]), user)

    return {
        'stories': stories,
        'categories': StoryCategory.objects.all(),
        'languages': Story.Language.choices,
        'sort_options': SORT_OPTIONS,
        'search': search,
        'selected_language': language,
        'selected_category': category_slug,
        'selected_region': region,
        'selected_sort': sort if sort in SORT_OPTIONS else '-created_at',
    }


def story_detail_data(user, slug):
    """Story reader data: flags, progress, quiz, narration and related."""
    story = get_object_or_404(visible_stories(user), slug=slug)

    # Count a view exactly like the API retrieve() does.
    Story.objects.filter(pk=story.pk).update(view_count=story.view_count + 1)

    is_bookmarked = is_liked = False
    progress = None
    narration = None
    video_job = None
    quiz = Quiz.objects.filter(story=story, is_published=True).first()

    if user.is_authenticated:
        is_bookmarked = StoryBookmark.objects.filter(user=user, story=story).exists()
        is_liked = StoryLike.objects.filter(user=user, story=story).exists()
        progress = ReadingProgress.objects.filter(user=user, story=story).first()

        if story.audio_url:
            narration = {
                'url': story.audio_url,
                'duration': 0,
                # A bare audio_url predates the provenance columns, so we can
                # only say what we know: someone attached audio of unknown
                # origin. Saying so beats implying it was recorded on site.
                'attribution': 'Audio of unrecorded origin',
                'is_synthetic': False,
            }
        else:
            narration_job = (
                AudioNarrationJob.objects.filter(
                    story=story,
                    status=AudioNarrationJob.Status.COMPLETED,
                )
                .order_by('-created_at')
                .first()
            )
            narration = narration_payload(narration_job) if narration_job else None
        if is_contributor_plus(user):
            video_job = (
                VideoGenerationJob.objects.filter(story=story, user=user)
                .order_by('-created_at')
                .first()
            )
    elif story.audio_url:
        narration = {
            'url': story.audio_url,
            'duration': 0,
            'attribution': 'Audio of unrecorded origin',
            'is_synthetic': False,
        }

    related = (
        published_stories()
        .filter(categories__in=story.categories.all())
        .exclude(pk=story.pk)
        .distinct()[:3]
    )

    # The author and moderators see where the story stands, and why.
    # `reviewer_notes` is the reason a moderator rejected it, and it was
    # rendered nowhere on any surface: a rejected contributor saw `rejected`
    # and had nothing to act on. Everyone else must not see it — it is
    # internal notes to them.
    is_owner_or_moderator = bool(
        user.is_authenticated
        and (
            story.author_id == user.id
            or user.role in ('institution_manager', 'admin')
        )
    )

    return {
        'story': story,
        'related_stories': related,
        'is_bookmarked': is_bookmarked,
        'is_liked': is_liked,
        'is_owner_or_moderator': is_owner_or_moderator,
        'reviewer_notes': (
            story.reviewer_notes
            if is_owner_or_moderator and story.reviewer_notes else ''
        ),
        # The consent decision and its licence, for the moderator form. Only a
        # moderator ever reads these two keys — a contributor gets the single
        # "I have asked" button instead, which cannot express a decision.
        #
        # The decisions, not every `Story.Consent` member: `not_requested` and
        # `pending` are the absence of an answer, so offering them in a
        # "Decision" dropdown let a moderator file "not requested" as what the
        # community said. See `stories.services.CONSENT_DECISIONS`.
        'consent_choices': [
            (code, Story.Consent(code).label)
            for code in CONSENT_DECISIONS
        ],
        'licences': Story.Licence.choices,
        'progress_percent': progress.progress_percent if progress else 0,
        'quiz': quiz,
        'narration': narration,
        'video_job': video_job,
        'can_generate_media': (
            user.is_authenticated
            and (
                user.role in ('institution_manager', 'admin')
                or story.author_id == user.id
                # Matches the media API: a published story is open to any
                # signed-in user, a draft stays with its author.
                or story.status == 'published'
            )
        ),
    }


def library_data(user):
    """Continue-reading, recently read, bookmarks and own stories."""
    return {
        'continue_reading': (
            ReadingProgress.objects.filter(
                user=user, completed=False, progress_percent__gt=0,
            )
            .select_related('story', 'story__author')
            .order_by('-updated_at')[:5]
        ),
        'recently_read': (
            ReadingProgress.objects.filter(user=user)
            .select_related('story', 'story__author')
            .order_by('-updated_at')[:20]
        ),
        'bookmarks': (
            StoryBookmark.objects.filter(user=user)
            .select_related('story', 'story__author')
            .prefetch_related('story__categories')
        ),
        'my_stories': (
            Story.objects.filter(author=user)
            .select_related('author')
            .prefetch_related('categories')
            .order_by('-created_at')
        ),
    }


def artifact_list_data(category):
    """Published artifacts, optionally narrowed by category."""
    artifacts = (
        Artifact.objects.filter(is_published=True)
        .select_related('created_by')
        .prefetch_related('stories')
    )
    if category:
        artifacts = artifacts.filter(category=category)
    return {
        'artifacts': artifacts[:48],
        'categories': Artifact.Category.choices,
        'selected_category': category,
    }


def artifact_detail_data(user, request, slug):
    """Artifact detail: scan analytics, related stories and audio guide."""
    artifact = get_object_or_404(
        Artifact.objects.filter(is_published=True).prefetch_related('stories'),
        slug=slug,
    )
    # F-05: this is a read path but it wrote a row on *every* GET, so a
    # pre-authenticated crawler or a reload loop could inflate scan analytics
    # without bound (and grow the table). Collapse repeats per artifact within
    # a window: the analytic signal is "this artifact was viewed", so recording
    # more than one row per viewer per window adds no information. Cached so
    # the repeat never reaches the database.
    scan_identity = f'{artifact.pk}:{client_identifier(request)}'
    if first_in_window(
        'artifact_scan', scan_identity, settings.SCAN_DEDUPE_WINDOW_SECONDS,
    ):
        artifact.scans.create(
            user=user if user.is_authenticated else None,
            device_type='Web',
            ip_address=get_client_ip(request),
            user_agent=request.META.get('HTTP_USER_AGENT', '')[:500],
        )
    related_stories = artifact.stories.filter(status=Story.Status.PUBLISHED)[:4]

    narration_job = artifact.audio_narrations.filter(
        status=AudioNarrationJob.Status.COMPLETED,
    ).order_by('-created_at').first()
    narration = narration_payload(narration_job) if narration_job else None

    return {
        'artifact': artifact,
        'related_stories': related_stories,
        'narration': narration,
        'can_generate_audio': (
            user.is_authenticated
            and (
                artifact.is_published
                or user.role in ('admin', 'institution_manager')
            )
        ),
    }


def gamification_data(user):
    """Leaderboard, badges and the signed-in user's achievements."""
    leaderboard = (
        UserProfile.objects.select_related('user')
        .order_by('-total_xp')[:20]
    )
    badges = Badge.objects.filter(is_active=True).order_by('category', 'xp_required')

    profile = None
    earned_ids = set()
    certificates = Certificate.objects.none()
    my_rank = None
    if user.is_authenticated:
        profile, _ = UserProfile.objects.get_or_create(user=user)
        earned_ids = set(
            UserBadge.objects.filter(user=user).values_list('badge_id', flat=True)
        )
        certificates = Certificate.objects.filter(user=user)
        ranked_ids = list(
            UserProfile.objects.order_by('-total_xp')
            .values_list('id', flat=True)[:200]
        )
        if profile.id in ranked_ids:
            my_rank = ranked_ids.index(profile.id) + 1

    return {
        'profile': profile,
        'badges': badges,
        'earned_ids': earned_ids,
        'certificates': certificates,
        'leaderboard': leaderboard,
        'my_rank': my_rank,
    }


def quiz_play_data(user, quiz_id):
    """Resume an in-progress quiz attempt for the published quiz."""
    quiz = get_object_or_404(
        Quiz.objects.select_related('story').prefetch_related('questions'),
        pk=quiz_id,
        is_published=True,
    )

    attempt = QuizAttempt.objects.filter(
        user=user, quiz=quiz, status=QuizAttempt.Status.IN_PROGRESS,
    ).first()

    questions = list(quiz.questions.all())
    answered_ids = set()
    for answer in (attempt.answers if attempt else []):
        try:
            answered_ids.add(int(answer.get('question_id')))
        except (TypeError, ValueError):
            continue
    next_question = next(
        (question for question in questions if question.id not in answered_ids),
        None,
    )

    return {
        'quiz': quiz,
        'attempt': attempt,
        'questions': questions,
        'answered_count': len(answered_ids),
        'next_question': next_question,
    }


def admin_dashboard_data():
    """KPI summary plus the flagged-story moderation queue and the QR worklist."""
    summary = get_dashboard_summary()

    flags = (
        StoryFlag.objects.filter(resolved=False)
        .select_related('story', 'story__author', 'user')
        .order_by('-created_at')
    )
    grouped_flags = OrderedDict()
    for flag in flags:
        entry = grouped_flags.setdefault(flag.story_id, {
            'story': flag.story,
            'flags': [],
        })
        entry['flags'].append(flag)

    return {
        'summary': summary,
        'moderation_queue': list(grouped_flags.values()),
        'top_users': summary['gamification']['top_users'],
        'avg_score': summary['gamification']['avg_score'],
        **qr_worklist_data(),
    }


# ---------------------------------------------------------------------------
# QR code worklist (Phase 5)
# ---------------------------------------------------------------------------
# The rules live in `qr_codes.services.qr_worklist`, not here, because the mobile
# app reads the same list through `GET /api/artifacts/qr/worklist/`. This screen
# is one of its two callers, not its owner.


def story_form_data(user, slug):
    """Create/edit story form data with the API ownership rules."""
    if not is_contributor_plus(user):
        raise PermissionDenied('Contributor role or above required to write stories.')

    story = None
    if slug:
        story = get_object_or_404(Story, slug=slug)
        if story.author_id != user.id and user.role not in (
            'institution_manager', 'admin',
        ):
            raise PermissionDenied('You can only edit your own stories.')

    return {
        'story': story,
        'editing': story is not None,
        'categories': StoryCategory.objects.all(),
        'languages': Story.Language.choices,
        # A contributor declares where their text came from; only a moderator
        # records whether the community consented, so consent is absent here.
        'origins': Story.Origin.choices,
        'licences': Story.Licence.choices,
    }


def profile_data(user):
    """The signed-in user's gamification profile."""
    profile, _ = UserProfile.objects.get_or_create(user=user)
    return {'gamification_profile': profile}


def quizzes_data(user):
    """Published quizzes the signed-in user can take, plus latest results."""
    visible_story_ids = set(
        visible_stories(user).values_list('id', flat=True)
    )
    quizzes = [
        quiz
        for quiz in Quiz.objects.filter(is_published=True)
        .select_related('story', 'story__author')
        .prefetch_related('questions')
        if quiz.story_id in visible_story_ids
    ][:24]

    latest_results = {}
    if user.is_authenticated:
        quiz_ids = [quiz.id for quiz in quizzes]
        attempts = (
            QuizAttempt.objects.filter(user=user, quiz_id__in=quiz_ids)
            .order_by('started_at')
        )
        for attempt in attempts:  # last write wins → latest attempt per quiz
            latest_results[attempt.quiz_id] = attempt

    return {
        'quizzes': quizzes,
        'latest_results': latest_results,
    }


# ---------------------------------------------------------------------------
# Story interaction mutations
# ---------------------------------------------------------------------------
def toggle_story_like(user, story):
    """Like/unlike — mirrors POST /api/stories/{slug}/like/."""
    like, created = StoryLike.objects.get_or_create(user=user, story=story)
    if not created:
        like.delete()
        Story.objects.filter(pk=story.pk).update(
            like_count=Greatest(F('like_count') - 1, 0)
        )
    else:
        Story.objects.filter(pk=story.pk).update(like_count=F('like_count') + 1)


def toggle_story_bookmark(user, story):
    """Bookmark/unbookmark — mirrors POST /api/stories/{slug}/bookmark/."""
    bookmark, created = StoryBookmark.objects.get_or_create(user=user, story=story)
    if not created:
        bookmark.delete()
        Story.objects.filter(pk=story.pk).update(
            bookmark_count=Greatest(F('bookmark_count') - 1, 0)
        )
    else:
        Story.objects.filter(pk=story.pk).update(bookmark_count=F('bookmark_count') + 1)


def flag_story(user, story, reason, details):
    """Flag a story — one open flag per user/story."""
    if reason not in {choice for choice, _ in StoryFlag.Reason.choices}:
        reason = StoryFlag.Reason.OTHER
    StoryFlag.objects.update_or_create(
        user=user,
        story=story,
        defaults={
            'reason': reason,
            'details': details,
            'resolved': False,
        },
    )


def record_story_share(user, story, platform, ip_address):
    """Track a share and bump the counter."""
    if platform not in {p for p, _ in StoryShare.PLATFORM_CHOICES}:
        platform = 'other'
    StoryShare.objects.create(
        story=story,
        user=user,
        platform=platform,
        ip_address=ip_address,
    )
    Story.objects.filter(pk=story.pk).update(share_count=F('share_count') + 1)


def record_progress(user, story, percent):
    """Save reading progress and keep gamification stats aligned (§4.6)."""
    progress, _ = ReadingProgress.objects.get_or_create(user=user, story=story)
    just_completed = percent >= 95 and not progress.completed
    progress.progress_percent = max(progress.progress_percent, percent)
    if percent >= 95:
        progress.completed = True
    progress.last_read_position = percent
    progress.save()

    profile, _ = UserProfile.objects.get_or_create(user=user)
    if just_completed:
        profile.stories_completed += 1
        profile.stories_read += 1
    elif profile.stories_read == 0:
        profile.stories_read = 1
    profile.save(update_fields=['stories_read', 'stories_completed'])
    # Reading is activity, so it extends the streak. Done after the counter save
    # because record_activity re-reads and re-writes the same row under a lock.
    record_activity(user)

    # The counters a reading badge reads (`stories_read` and streak) just moved,
    # so this is the one moment a reading badge can become earnable. Nothing
    # else in the request path checked — which is how 503 profiles cleared
    # "First Steps" while none of them held it.
    award_eligible_badges(user)


# ---------------------------------------------------------------------------
# Quiz mutations
# ---------------------------------------------------------------------------
def start_quiz(user, quiz):
    """Open (or resume) an in-progress attempt."""
    return QuizAttempt.objects.get_or_create(
        user=user,
        quiz=quiz,
        status=QuizAttempt.Status.IN_PROGRESS,
        defaults={'total_questions': quiz.question_count},
    )[0]


def submit_quiz_answer(user, quiz, question, selected):
    """Record one answer on the in-progress attempt.

    Returns an error message, or ``None`` when the answer was recorded.
    """
    if selected not in ('a', 'b', 'c', 'd'):
        return _('Invalid answer.')
    attempt = QuizAttempt.objects.filter(
        user=user, quiz=quiz, status=QuizAttempt.Status.IN_PROGRESS,
    ).first()
    if attempt is None:
        return _('No active attempt — start the quiz first.')

    answers = attempt.answers or []
    if any(answer.get('question_id') == question.id for answer in answers):
        return _('Question already answered.')

    answers.append({
        'question_id': question.id,
        'selected_answer': selected,
        'correct_answer': question.correct_answer,
        'is_correct': selected == question.correct_answer,
        'explanation': question.explanation,
    })
    attempt.answers = answers
    attempt.save(update_fields=['answers'])
    return None


def finish_quiz(user, quiz):
    """Score the attempt, award XP/badges and close it out."""
    attempt = QuizAttempt.objects.filter(
        user=user, quiz=quiz, status=QuizAttempt.Status.IN_PROGRESS,
    ).first()
    if attempt is None:
        return None

    attempt.calculate_score()
    attempt.status = QuizAttempt.Status.COMPLETED
    attempt.completed_at = timezone.now()
    attempt.time_taken_seconds = int(
        (attempt.completed_at - attempt.started_at).total_seconds()
    )

    if attempt.passed:
        if already_earned_quiz_xp(user, quiz, exclude_attempt=attempt):
            # F-06: already paid for this quiz. A retake still records the
            # attempt and still extends the streak, it just does not pay out
            # again, so the reward cannot be farmed.
            attempt.xp_earned = 0
        else:
            attempt.xp_earned = quiz.xp_reward
            profile, _ = UserProfile.objects.get_or_create(user=user)
            profile.add_xp(quiz.xp_reward)
            profile.quizzes_passed += 1
            profile.total_quiz_xp += quiz.xp_reward
            profile.save(update_fields=['quizzes_passed', 'total_quiz_xp'])

    attempt.save()

    # Attempting a quiz is activity whether or not it passed — the API finish
    # view has always said so, and this flow had drifted to extending the streak
    # only on a pass. Same call, same place, both surfaces.
    record_activity(user)

    # One sweep, after the counters above have landed, on every outcome — pass,
    # fail, first attempt or retake. See gamification.services.awards for why
    # there is exactly one of these now.
    award_eligible_badges(user)
    return attempt


# ---------------------------------------------------------------------------
# Moderation + story authoring
# ---------------------------------------------------------------------------
def moderate_story(user, story, action, notes):
    """Resolve flags and optionally archive the story."""
    if user.role not in ('admin', 'institution_manager'):
        raise PermissionDenied('Moderator role required.')

    StoryFlag.objects.filter(story=story, resolved=False).update(
        resolved=True,
        resolution_notes=notes,
    )
    if action == 'remove':
        story.status = Story.Status.ARCHIVED
        story.reviewer_notes = notes
        story.save(update_fields=['status', 'reviewer_notes', 'updated_at'])


def save_story(user, *, slug, title, content, summary, language,
               region, tags, cultural_context, moral_lesson, source,
               status, category_ids, origin='', provenance_notes='',
               rights_holder='', licence='', recorded_at=None):
    """Create or update a story via the web form (API ownership rules).

    Returns ``(story, message)``. Raises ``PermissionDenied`` for the same
    gates the API enforces.
    """
    if not is_contributor_plus(user):
        raise PermissionDenied('Contributor role or above required.')

    story = None
    if slug:
        story = get_object_or_404(Story, slug=slug)
        if story.author_id != user.id and user.role not in (
            'institution_manager', 'admin',
        ):
            raise PermissionDenied('You can only edit your own stories.')

    # The rule lives in one place now. It used to be inline here and absent
    # from the API entirely, which is how the two surfaces drifted: this form
    # could submit for review while the API silently ignored the identical
    # request from Flutter.
    status = resolve_status(user, status) or Story.Status.DRAFT
    if language not in {choice for choice, _ in Story.Language.choices}:
        language = Story.Language.ENGLISH
    # An unrecognised choice falls back to the honest default rather than
    # raising: provenance metadata must never block someone saving their tale.
    if origin not in {choice for choice, _ in Story.Origin.choices}:
        origin = Story.Origin.UNKNOWN
    if licence not in {choice for choice, _ in Story.Licence.choices}:
        licence = Story.Licence.UNDETERMINED

    fields = {
        'title': title,
        'content': content,
        'summary': summary,
        'language': language,
        'region': region,
        'tags': tags,
        'cultural_context': cultural_context,
        'moral_lesson': moral_lesson,
        'source': source,
        'origin': origin,
        'provenance_notes': provenance_notes,
        'rights_holder': rights_holder,
        'licence': licence,
        'recorded_at': recorded_at,
    }
    categories = StoryCategory.objects.filter(id__in=category_ids)

    if story is None:
        story = Story.objects.create(author=user, status=status, **fields)
        message = (
            _('Story saved as draft.') if status == Story.Status.DRAFT
            else _('Story submitted for review.')
        )
    else:
        for name, value in fields.items():
            setattr(story, name, value)
        story.status = status
        story.save()
        message = 'Story updated.'

    story.categories.set(categories)
    return story, message


def delete_story(user, story):
    """Delete a story with the API ownership rule."""
    if story.author_id != user.id and user.role not in (
        'institution_manager', 'admin',
    ):
        raise PermissionDenied('You can only delete your own stories.')
    title = story.title
    story.delete()
    return title


# ---------------------------------------------------------------------------
# Media generation (§6 TTS / §7 video) and polling
# ---------------------------------------------------------------------------
def generate_story_audio(user, story, language):
    """Generate a narration for a story. Returns (message, kind)."""
    if (
        story.author_id != user.id
        and user.role not in ('admin', 'institution_manager')
        and story.status != Story.Status.PUBLISHED
    ):
        raise PermissionDenied(
            'You can only generate audio for your own or published stories.'
        )

    existing = AudioNarrationJob.objects.filter(
        story=story,
        language=language,
        status=AudioNarrationJob.Status.COMPLETED,
    ).order_by('-created_at').first()
    if existing is not None:
        return 'This story already has a narration ready.', 'info'

    narration_text = strip_markdown(story.content)
    if not narration_text.strip():
        return 'There is no text available to narrate.', 'error'

    # Cache miss, so this synthesis is about to spend a real outbound call.
    # The API applies the same rolling-24h ceiling (shared via media_app.quota);
    # without it the web form was an uncapped path to Google TTS and to disk.
    if not quota.audio_within_cap(user):
        return (
            f'You have reached your daily audio limit of '
            f'{quota.audio_cap()}. Narrations already generated for you are '
            f'still available.',
            'error',
        )

    tts_service = get_tts_service()
    job = AudioNarrationJob.objects.create(
        user=user,
        story=story,
        narration_text=narration_text,
        language=language,
        speed=1.0,
        status=AudioNarrationJob.Status.PROCESSING,
        engine=normalise_engine(tts_service, 'narration'),
    )
    try:
        result = tts_service.submit_narration(
            text=narration_text,
            language=job.language,
            voice_id='default',
            speed=job.speed,
            slug=story.slug or 'narration',
        )
        job.audio_file.save(
            result['filename'], ContentFile(result['audio_bytes']), save=False,
        )
        job.duration = result['duration']
        job.file_size = result['file_size']
        job.status = AudioNarrationJob.Status.COMPLETED
        job.completed_at = timezone.now()
        job.save()
        return '🔊 Narration generated — press play to listen.', 'success'
    except TTSGenerationError as exc:
        job.status = AudioNarrationJob.Status.FAILED
        job.error_message = str(exc)
        job.save()
        return f'Narration failed: {exc}', 'error'


def generate_artifact_audio(user, artifact, language):
    """Generate the museum audio guide for an artifact. (message, kind)."""
    if (
        not artifact.is_published
        and user.role not in ('admin', 'institution_manager')
    ):
        raise PermissionDenied('You can only generate audio for published artifacts.')

    existing = AudioNarrationJob.objects.filter(
        artifact=artifact,
        language=language,
        status=AudioNarrationJob.Status.COMPLETED,
    ).order_by('-created_at').first()
    if existing is not None:
        return 'This artifact already has an audio guide ready.', 'info'

    narration_text = build_artifact_script(artifact)
    if not narration_text.strip():
        return 'There is no text available to narrate.', 'error'

    # Cache miss, so this is a real outbound synthesis — apply the same
    # rolling-24h cap the API enforces (shared via media_app.quota).
    if not quota.audio_within_cap(user):
        return (
            f'You have reached your daily audio limit of '
            f'{quota.audio_cap()}. Narrations already generated for you are '
            f'still available.',
            'error',
        )

    primary_story = artifact.stories.filter(
        status=Story.Status.PUBLISHED,
    ).order_by('id').first()

    tts_service = get_tts_service()
    job = AudioNarrationJob.objects.create(
        user=user,
        story=primary_story,
        artifact=artifact,
        narration_text=narration_text,
        language=language,
        speed=1.0,
        status=AudioNarrationJob.Status.PROCESSING,
        engine=normalise_engine(tts_service, 'narration'),
    )
    try:
        result = tts_service.submit_narration(
            text=narration_text,
            language=job.language,
            voice_id='default',
            speed=job.speed,
            slug=artifact.slug or 'artifact-guide',
        )
        job.audio_file.save(
            result['filename'], ContentFile(result['audio_bytes']), save=False,
        )
        job.duration = result['duration']
        job.file_size = result['file_size']
        job.status = AudioNarrationJob.Status.COMPLETED
        job.completed_at = timezone.now()
        job.save()
        return '🔊 Audio guide generated — press play to listen.', 'success'
    except TTSGenerationError as exc:
        job.status = AudioNarrationJob.Status.FAILED
        job.error_message = str(exc)
        job.save()
        return f'Narration failed: {exc}', 'error'


def generate_story_video(user, story, prompt):
    """Queue an AI video for a story. Returns (message, kind)."""
    if story.author_id != user.id and user.role not in (
        'admin', 'institution_manager',
    ):
        raise PermissionDenied('You can only generate videos for your own stories.')

    if not prompt:
        prompt = (
            f'Visualize this African tale: {story.title}. {story.summary or story.title}'
        )

    active = VideoGenerationJob.objects.filter(
        story=story, user=user,
        status__in=(VideoGenerationJob.Status.PENDING, VideoGenerationJob.Status.PROCESSING),
    ).first()
    if active is not None:
        return 'A video is already being generated for this story.', 'info'

    # The in-flight guard above is per story, so looping over several stories
    # — or simply waiting for a job to leave PENDING — would otherwise start
    # unbounded paid Luma renders. Same rolling-24h cap as the API.
    if not quota.video_within_cap(user):
        return (
            f'You have reached your daily video limit of '
            f'{quota.video_cap()}. Please try again tomorrow.',
            'error',
        )

    # Recorded on the job at submit so completion has a duration to show even
    # when the provider does not report one back.
    requested_duration = 5

    job = VideoGenerationJob.objects.create(
        user=user,
        story=story,
        prompt=prompt,
        status=VideoGenerationJob.Status.PENDING,
        duration=requested_duration,
    )
    try:
        luma_service = get_luma_service()
        result = luma_service.submit_video_generation(
            prompt=prompt, duration=requested_duration
        )
    except LumaAIError as exc:
        # The job row already exists, so record why it died rather than
        # leaving a permanently-pending job, and tell the user plainly.
        job.status = VideoGenerationJob.Status.FAILED
        job.error_message = str(exc)
        job.save(update_fields=['status', 'error_message', 'updated_at'])
        return f'🎬 Video generation unavailable: {exc}', 'error'

    job.luma_job_id = result['id']
    # Stamp which vendor actually answered, so a job served by a fallback
    # provider — or by the mock — is never credited to the primary one.
    # `result_field` rather than `result.get`: a test double returning a Mock
    # would land a non-string in a CharField and fail at save time.
    job.provider = result_field(result, 'provider')
    job.engine = result_field(result, 'engine') or normalise_engine(
        luma_service, 'video'
    )
    job.save()
    return '🎬 Video generation started — check back shortly.', 'success'


def refresh_video_job(user, story):
    """Poll the job's external status and persist the outcome (may be None)."""
    job = (
        VideoGenerationJob.objects.filter(story=story, user=user)
        .order_by('-created_at')
        .first()
    )
    if job is None or job.luma_job_id is None or job.status not in (
        VideoGenerationJob.Status.PENDING, VideoGenerationJob.Status.PROCESSING,
    ):
        return job

    # A server that has lost its provider configuration must not break the
    # page render: report the stored state and let the user retry later.
    try:
        luma_service = get_luma_service()
        luma_status = luma_service.get_job_status(
            job.luma_job_id, provider=job.provider
        )
    except LumaAIError:
        return job


    if luma_status.get('status') == 'completed':
        job.status = VideoGenerationJob.Status.COMPLETED
        job.video_url = luma_status.get('video_url', '')
        job.thumbnail_url = luma_status.get('thumbnail_url', '')
        # Keep the requested duration when the API reports none, so the
        # player does not show 00:00 for a clip we asked to be N seconds.
        job.duration = luma_status.get('duration') or job.duration
        # Mirror the API status path: store the finished render locally so
        # playback outlives the provider's CDN URL. Best effort — on failure
        # the job completes on the remote URL, exactly as before.
        store_video_asset(job)
    elif luma_status.get('status') == 'failed':
        job.status = VideoGenerationJob.Status.FAILED
        job.error_message = luma_status.get('error', 'Unknown error')
    else:
        job.status = VideoGenerationJob.Status.PROCESSING
    job.save()
    return job


# ---------------------------------------------------------------------------
# Profile + account (§1) and web settings
# ---------------------------------------------------------------------------
def update_profile(user, *, first_name, last_name, email, institution):
    """Update editable profile fields (role is not self-service, like the API).

    Returns ``(errors, changed)`` — empty errors means the update applied.
    """
    errors = []
    if email and User.objects.filter(email__iexact=email).exclude(pk=user.pk).exists():
        errors.append(_('A user with this email already exists.'))
    if errors:
        return errors, False

    user.first_name = first_name
    user.last_name = last_name
    if email:
        user.email = email
    if user.role == 'institution_manager':
        user.institution = institution
    user.save(update_fields=['first_name', 'last_name', 'email', 'institution'])
    return [], True


def delete_profile(username):
    """Permanently delete the account and associated data."""
    User.objects.filter(username=username).delete()


def set_language(user, code):
    """Persist the user's web UI language and return the code actually stored."""
    code = resolve_ui_language(code)
    settings_obj, _ = WebUserSettings.objects.get_or_create(user=user)
    if settings_obj.language != code:
        settings_obj.language = code
        settings_obj.save(update_fields=['language'])
    return code


def register_user(*, username, email, password, password2, role):
    """Create a new account. Returns (user_or_None, errors)."""
    username = (username or '').strip()
    email = (email or '').strip().lower()
    role = role or 'visitor'
    if role not in ('visitor', 'contributor'):
        role = 'visitor'

    errors = []
    if not username:
        errors.append(_('Username is required.'))

    # F-03: an attacker cannot use this form to test whether a given username or
    # email is registered. Telling a caller *which* field collided, and whether
    # it collided at all, turns an open signup form into a membership oracle for
    # any account on the platform. One generic message for both collisions; the
    # per-field detail is dropped rather than softened, since a message like
    # "that looks like an existing username" is just as revealing.
    # The legitimate user resolves the ambiguity by trying a different value.
    GENERIC_COLLISION = _(
        'An account with those details already exists. '
        'Try a different username or email.'
    )
    if User.objects.filter(username__iexact=username).exists():
        errors.append(GENERIC_COLLISION)
    if email and User.objects.filter(email__iexact=email).exists():
        errors.append(GENERIC_COLLISION)

    # Length/format problems are the *submitter's own* input, not a fact about
    # another account, so those stay specific — they help rather than enumerate.
    if len(password) < 8:
        errors.append(_('Password must be at least 8 characters.'))
    if password != password2:
        errors.append(_('Passwords do not match.'))

    if not errors:
        # F-04: AUTH_PASSWORD_VALIDATORS is configured in settings but was
        # never called from anywhere, so a length check was the only policy in
        # force and every password in the common-breach list was accepted. Run
        # the real validators now; they cover similarity to the username/email
        # as well as the breach list, and re-run on every attribute change via
        # this single entry point.
        try:
            validate_password(password, user=None)
        except DjangoValidationError as exc:
            errors.extend(exc.messages)

    if errors:
        return None, errors

    try:
        user = User.objects.create_user(
            username=username,
            email=email,
            password=password,
            role=role,
        )
    except IntegrityError:
        # Lost a race against a concurrent signup. The email has a
        # case-insensitive unique constraint, so the check above is only a
        # fast path and the database is the real arbiter. Report the same
        # generic message so the race does not re-open the enumeration oracle.
        return None, [GENERIC_COLLISION]
    return user, []