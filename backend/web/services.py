"""
Domain logic shared by the server-rendered web views and actions.

Database access and business rules live here so ``web/views.py`` and
``web/actions.py`` stay thin HTTP adapters (render, redirect, messages).
Each function mirrors the same rules the DRF API enforces, so both the HTML
site and the mobile app always behave identically.
"""

from collections import OrderedDict

from django.contrib.auth import get_user_model
from django.core.exceptions import PermissionDenied
from django.core.files.base import ContentFile
from django.db.models import Count, F, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone

from api.analytics import get_dashboard_summary
from gamification.models import (
    Badge,
    Certificate,
    Quiz,
    QuizAttempt,
    UserBadge,
    UserProfile,
)
from media_app.models import AudioNarrationJob, VideoGenerationJob
from media_app.services.luma_ai import get_luma_service
from media_app.services.tts import (
    TTSGenerationError,
    build_artifact_script,
    get_tts_service,
    strip_markdown,
)
from qr_codes.models import Artifact
from stories.models import (
    ReadingProgress,
    Story,
    StoryBookmark,
    StoryCategory,
    StoryFlag,
    StoryLike,
    StoryShare,
)

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
    ('-created_at', 'Newest'),
    ('created_at', 'Oldest'),
    ('-view_count', 'Most Viewed'),
    ('-like_count', 'Most Liked'),
])

CATEGORY_EMOJI_FALLBACK = '📖'


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
    """Normalize a narration job into {url, duration} for templates.

    FileField.url raises when no file is attached (legacy audio_url rows),
    so resolve the playable URL defensively here rather than in templates.
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
            narration = {'url': story.audio_url, 'duration': 0}
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
        narration = {'url': story.audio_url, 'duration': 0}

    related = (
        published_stories()
        .filter(categories__in=story.categories.all())
        .exclude(pk=story.pk)
        .distinct()[:3]
    )

    return {
        'story': story,
        'related_stories': related,
        'is_bookmarked': is_bookmarked,
        'is_liked': is_liked,
        'progress_percent': progress.progress_percent if progress else 0,
        'quiz': quiz,
        'narration': narration,
        'video_job': video_job,
        'can_generate_media': (
            user.is_authenticated
            and user.role in ('contributor', 'institution_manager', 'admin')
            and (
                user.role in ('institution_manager', 'admin')
                or story.author_id == user.id
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
    artifact.scans.create(
        user=user if user.is_authenticated else None,
        device_type='Web',
        ip_address=request.META.get('REMOTE_ADDR'),
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
    """KPI summary plus the flagged-story moderation queue."""
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
    }


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
            like_count=max(0, story.like_count - 1)
        )
    else:
        Story.objects.filter(pk=story.pk).update(like_count=F('like_count') + 1)


def toggle_story_bookmark(user, story):
    """Bookmark/unbookmark — mirrors POST /api/stories/{slug}/bookmark/."""
    bookmark, created = StoryBookmark.objects.get_or_create(user=user, story=story)
    if not created:
        bookmark.delete()
        Story.objects.filter(pk=story.pk).update(
            bookmark_count=max(0, story.bookmark_count - 1)
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
    profile.update_streak()
    profile.save(update_fields=['stories_read', 'stories_completed'])


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
        return 'Invalid answer.'
    attempt = QuizAttempt.objects.filter(
        user=user, quiz=quiz, status=QuizAttempt.Status.IN_PROGRESS,
    ).first()
    if attempt is None:
        return 'No active attempt — start the quiz first.'

    answers = attempt.answers or []
    if any(answer.get('question_id') == question.id for answer in answers):
        return 'Question already answered.'

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
        attempt.xp_earned = quiz.xp_reward
        profile, _ = UserProfile.objects.get_or_create(user=user)
        profile.add_xp(quiz.xp_reward)
        profile.quizzes_passed += 1
        profile.total_quiz_xp += quiz.xp_reward
        profile.save(update_fields=['quizzes_passed', 'total_quiz_xp'])

        earned_ids = UserBadge.objects.filter(user=user).values_list(
            'badge_id', flat=True,
        )
        for badge in Badge.objects.filter(is_active=True).exclude(id__in=earned_ids):
            if (
                (badge.xp_required and profile.total_xp >= badge.xp_required)
                or (badge.stories_read_required and profile.stories_read >= badge.stories_read_required)
                or (badge.quizzes_passed_required and profile.quizzes_passed >= badge.quizzes_passed_required)
            ):
                UserBadge.objects.create(user=user, badge=badge)

    attempt.save()
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
               status, category_ids):
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

    if status not in (Story.Status.DRAFT, Story.Status.PENDING):
        status = Story.Status.DRAFT
    if language not in {choice for choice, _ in Story.Language.choices}:
        language = Story.Language.ENGLISH

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
    }
    categories = StoryCategory.objects.filter(id__in=category_ids)

    if story is None:
        story = Story.objects.create(author=user, status=status, **fields)
        message = (
            'Story saved as draft.' if status == Story.Status.DRAFT
            else 'Story submitted for review.'
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

    job = AudioNarrationJob.objects.create(
        user=user,
        story=story,
        narration_text=narration_text,
        language=language,
        speed=1.0,
        status=AudioNarrationJob.Status.PROCESSING,
    )
    tts_service = get_tts_service()
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

    primary_story = artifact.stories.filter(
        status=Story.Status.PUBLISHED,
    ).order_by('id').first()

    job = AudioNarrationJob.objects.create(
        user=user,
        story=primary_story,
        artifact=artifact,
        narration_text=narration_text,
        language=language,
        speed=1.0,
        status=AudioNarrationJob.Status.PROCESSING,
    )
    tts_service = get_tts_service()
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

    job = VideoGenerationJob.objects.create(
        user=user,
        story=story,
        prompt=prompt,
        status=VideoGenerationJob.Status.PENDING,
    )
    luma_service = get_luma_service()
    result = luma_service.submit_video_generation(prompt=prompt)
    job.luma_job_id = result['id']
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

    luma_service = get_luma_service()
    luma_status = luma_service.get_job_status(job.luma_job_id)
    if luma_status.get('status') == 'completed':
        job.status = VideoGenerationJob.Status.COMPLETED
        job.video_url = luma_status.get('video_url', '')
        job.thumbnail_url = luma_status.get('thumbnail_url', '')
        job.duration = luma_status.get('duration', 0)
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
        errors.append('A user with this email already exists.')
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
    """Persist the user's web UI language."""
    if code not in {choice for choice, _ in Story.Language.choices}:
        code = 'en'
    settings_obj, _ = WebUserSettings.objects.get_or_create(user=user)
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
        errors.append('Username is required.')
    if User.objects.filter(username__iexact=username).exists():
        errors.append('That username is taken.')
    if email and User.objects.filter(email__iexact=email).exists():
        errors.append('A user with this email already exists.')
    if len(password) < 8:
        errors.append('Password must be at least 8 characters.')
    if password != password2:
        errors.append('Passwords do not match.')

    if errors:
        return None, errors

    user = User.objects.create_user(
        username=username,
        email=email,
        password=password,
        role=role,
    )
    return user, []