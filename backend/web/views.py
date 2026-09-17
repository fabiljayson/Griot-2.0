"""
Server-rendered web views mirroring the Griot AI mobile app.

Every view consumes the same models the DRF API serves to the Flutter app,
so the two platforms always display identical data.

Screens (mobile equivalent in brackets):
    HomeView            [HomeScreen]          — header, trending, popular, regions
    StoriesView         [StoriesScreen]       — masonry grid, search & filters
    StoryDetailView     [StoryDetailScreen]   — reader with like/bookmark/progress
    LibraryView         [LibraryScreen]       — continue reading, bookmarks, my stories
    ArtifactListView    [qr_scanner catalog]  — museum artifacts
    ArtifactDetailView  [ArtifactDetailScreen]— artifact info + related stories
    GamificationView    [GamificationScreen]  — XP profile, badges, leaderboard
    QuizPlayerView      [QuizPlayerWidget]    — interactive quiz flow
    AdminDashboardView  [AdminDashboardScreen]— analytics + moderation queue
    Login/Register/Logout — session auth mirroring BrandScaffold screens
"""

from collections import OrderedDict

from django.contrib.auth import get_user_model
from django.contrib.auth import views as auth_views
from django.core.exceptions import PermissionDenied
from django.db.models import Avg, Count, Q, Sum
from django.http import Http404
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.generic import TemplateView

from api.analytics import (
    get_dashboard_summary,
    get_gamification_stats,
)
from gamification.models import (
    Badge,
    Certificate,
    Quiz,
    QuizAttempt,
    UserBadge,
    UserProfile,
)
from media_app.models import AudioNarrationJob, VideoGenerationJob
from qr_codes.models import Artifact
from stories.models import (
    ReadingProgress,
    Story,
    StoryBookmark,
    StoryCategory,
    StoryFlag,
    StoryLike,
)

from .auth import DEFAULT_LOGIN_REDIRECT

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
# Small view helpers
# ---------------------------------------------------------------------------
def _published_stories():
    """Published stories with the same prefetches the API list uses."""
    return (
        Story.objects.filter(status=Story.Status.PUBLISHED)
        .select_related('author')
        .prefetch_related('categories')
    )


def _visible_stories(user):
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


def _with_flags(stories, user):
    """Attach `bookmarked` / `liked` booleans without N+1 queries."""
    if not user.is_authenticated:
        for s in stories:
            s.bookmarked = False
            s.liked = False
        return stories
    story_ids = [s.id for s in stories]
    bookmarked_ids = set(
        StoryBookmark.objects.filter(user=user, story_id__in=story_ids)
        .values_list('story_id', flat=True)
    )
    liked_ids = set(
        StoryLike.objects.filter(user=user, story_id__in=story_ids)
        .values_list('story_id', flat=True)
    )
    for s in stories:
        s.bookmarked = s.id in bookmarked_ids
        s.liked = s.id in liked_ids
    return stories


def _home_stories():
    """Trending + popular feeds for the home screen."""
    week_ago = timezone.now() - timezone.timedelta(days=7)
    trending = list(
        _published_stories()
        .filter(created_at__gte=week_ago)
        .annotate(engagement=Count('likes') + Count('bookmarks') + Sum('view_count'))
        .order_by('-engagement')[:6]
    )
    if not trending:
        trending = list(_published_stories().order_by('-view_count', '-like_count')[:6])
    popular = list(_published_stories().order_by('-view_count', '-like_count')[:4])
    return trending, popular


def _region_stories(limit=6):
    """Top region chips enriched with a representative story each."""
    regions = []
    for region in HOME_REGIONS:
        story = (
            _published_stories()
            .filter(region__icontains=region['label'])
            .order_by('-view_count')
            .first()
        )
        count = _published_stories().filter(region__icontains=region['label']).count()
        regions.append({**region, 'story': story, 'count': count})
    return regions[:limit]


def _gamification_context(user):
    """Shared gamification data for the profile + quiz screens."""
    profile, _ = UserProfile.objects.get_or_create(user=user)
    badges = Badge.objects.filter(is_active=True).order_by('category', 'xp_required')
    earned_ids = set(
        UserBadge.objects.filter(user=user).values_list('badge_id', flat=True)
    )
    certificates = Certificate.objects.filter(user=user)
    return profile, badges, earned_ids, certificates


def is_contributor_plus(user):
    """Role gate mirroring the API's IsContributorOrAbove permission."""
    return user.is_authenticated and user.role in (
        'contributor', 'institution_manager', 'admin',
    )


def _narration_payload(job):
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
# Home — mirrors mobile HomeScreen
# ---------------------------------------------------------------------------
def home_view(request):
    trending, popular = _home_stories()
    trending = _with_flags(trending, request.user)
    popular = _with_flags(popular, request.user)
    categories = StoryCategory.objects.all()[:8]
    artifact_count = Artifact.objects.filter(is_published=True).count()
    story_count = Story.objects.filter(status=Story.Status.PUBLISHED).count()

    context = {
        'trending_stories': trending,
        'popular_stories': popular,
        'categories': categories,
        'regions': _region_stories(),
        'artifact_count': artifact_count,
        'story_count': story_count,
        'active_nav': 'home',
    }
    return render(request, 'web/home.html', context)


# ---------------------------------------------------------------------------
# Stories — mirrors mobile StoriesScreen (discovery dashboard)
# ---------------------------------------------------------------------------
def stories_view(request):
    stories = _visible_stories(request.user)

    # --- Search (same fields as the API: title/content/summary/tags) ---
    search = request.GET.get('search', '').strip()
    if search:
        stories = stories.filter(
            Q(title__icontains=search)
            | Q(content__icontains=search)
            | Q(summary__icontains=search)
            | Q(tags__icontains=search)
        )

    # --- Filters ---
    language = request.GET.get('language', '').strip()
    if language:
        stories = stories.filter(language=language)

    category_slug = request.GET.get('category', '').strip()
    if category_slug:
        stories = stories.filter(categories__slug=category_slug)

    region = request.GET.get('region', '').strip()
    if region:
        stories = stories.filter(region__icontains=region)

    # --- Sort (whitelisted to mirror the API) ---
    sort = request.GET.get('sort', '-created_at')
    if sort in SORT_OPTIONS:
        stories = stories.order_by(sort)

    stories = _with_flags(list(stories[:60]), request.user)

    context = {
        'stories': stories,
        'categories': StoryCategory.objects.all(),
        'languages': Story.Language.choices,
        'sort_options': SORT_OPTIONS,
        'search': search,
        'selected_language': language,
        'selected_category': category_slug,
        'selected_region': region,
        'selected_sort': sort if sort in SORT_OPTIONS else '-created_at',
        'active_nav': 'stories',
    }
    return render(request, 'web/stories.html', context)


# ---------------------------------------------------------------------------
# Story detail — mirrors mobile StoryDetailScreen (markdown reader)
# ---------------------------------------------------------------------------
def story_detail_view(request, slug):
    story = get_object_or_404(
        _visible_stories(request.user), slug=slug,
    )

    # Count a view exactly like the API retrieve() does.
    Story.objects.filter(pk=story.pk).update(view_count=story.view_count + 1)

    is_bookmarked = is_liked = False
    progress = None
    quiz = None
    narration = None
    video_job = None
    if request.user.is_authenticated:
        is_bookmarked = StoryBookmark.objects.filter(user=request.user, story=story).exists()
        is_liked = StoryLike.objects.filter(user=request.user, story=story).exists()
        progress = ReadingProgress.objects.filter(user=request.user, story=story).first()
        quiz = Quiz.objects.filter(story=story, is_published=True).first()

        # Media parity (§6 audio / §7 video): reuse any completed narration for
        # this story, and surface the user's latest video job if they own one.
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
            narration = _narration_payload(narration_job) if narration_job else None
        if is_contributor_plus(request.user):
            video_job = (
                VideoGenerationJob.objects.filter(story=story, user=request.user)
                .order_by('-created_at')
                .first()
            )
    elif story.audio_url:
        narration = {'url': story.audio_url, 'duration': 0}

    related = (
        _published_stories()
        .filter(categories__in=story.categories.all())
        .exclude(pk=story.pk)
        .distinct()[:3]
    )

    # Share targets for the bottom sheet (mirrors mobile share_plus sheet).
    share_url = request.build_absolute_uri(f'/story/{story.slug}/')
    share_text = f'Check out "{story.title}" on Griot AI! 🌍'
    context = {
        'story': story,
        'related_stories': related,
        'is_bookmarked': is_bookmarked,
        'is_liked': is_liked,
        'progress_percent': progress.progress_percent if progress else 0,
        'quiz': quiz,
        'narration': narration,
        'video_job': video_job,
        'can_generate_media': (
            request.user.is_authenticated
            and request.user.role in ('contributor', 'institution_manager', 'admin')
            and (request.user.role in ('institution_manager', 'admin') or story.author_id == request.user.id)
        ),
        'share_targets': [
            ('twitter', 'Twitter', 'fa-x-twitter'),
            ('facebook', 'Facebook', 'fa-facebook-f'),
            ('whatsapp', 'WhatsApp', 'fa-whatsapp'),
            ('telegram', 'Telegram', 'fa-telegram'),
        ],
        'share_targets_json': {
            'story_url': share_url,
            'story_title': story.title,
            'share_text': share_text,
        },
        'active_nav': 'stories',
    }
    return render(request, 'web/story_detail.html', context)


# ---------------------------------------------------------------------------
# Library — mirrors mobile LibraryScreen
# ---------------------------------------------------------------------------
def library_view(request):
    if not request.user.is_authenticated:
        return redirect(f'{reverse("web:login")}?next={reverse("web:library")}')

    continue_reading = (
        ReadingProgress.objects.filter(
            user=request.user, completed=False, progress_percent__gt=0,
        )
        .select_related('story', 'story__author')
        .order_by('-updated_at')[:5]
    )
    recently_read = (
        ReadingProgress.objects.filter(user=request.user)
        .select_related('story', 'story__author')
        .order_by('-updated_at')[:20]
    )
    bookmarks = (
        StoryBookmark.objects.filter(user=request.user)
        .select_related('story', 'story__author')
        .prefetch_related('story__categories')
    )
    my_stories = (
        Story.objects.filter(author=request.user)
        .select_related('author')
        .prefetch_related('categories')
        .order_by('-created_at')
    )

    context = {
        'continue_reading': continue_reading,
        'recently_read': recently_read,
        'bookmarks': bookmarks,
        'my_stories': my_stories,
        'active_nav': 'library',
    }
    return render(request, 'web/library.html', context)


# ---------------------------------------------------------------------------
# Artifacts — mirrors QR scanner feature (catalog + detail)
# ---------------------------------------------------------------------------
def artifact_list_view(request):
    artifacts = (
        Artifact.objects.filter(is_published=True)
        .select_related('created_by')
        .prefetch_related('stories')
    )
    category = request.GET.get('category', '').strip()
    if category:
        artifacts = artifacts.filter(category=category)

    context = {
        'artifacts': artifacts[:48],
        'categories': Artifact.Category.choices,
        'selected_category': category,
        'active_nav': 'artifacts',
    }
    return render(request, 'web/artifacts.html', context)


def artifact_detail_view(request, slug):
    artifact = get_object_or_404(
        Artifact.objects.filter(is_published=True).prefetch_related('stories'),
        slug=slug,
    )
    # Record the scan (same analytics the mobile deep-link flow produces).
    artifact.scans.create(
        user=request.user if request.user.is_authenticated else None,
        device_type='Web',
        ip_address=request.META.get('REMOTE_ADDR'),
        user_agent=request.META.get('HTTP_USER_AGENT', '')[:500],
    )
    related_stories = artifact.stories.filter(status=Story.Status.PUBLISHED)[:4]

    # Museum audio guide — mirrors the mobile artifact narration (§6).
    narration_job = artifact.audio_narrations.filter(
        status=AudioNarrationJob.Status.COMPLETED,
    ).order_by('-created_at').first()
    narration = _narration_payload(narration_job) if narration_job else None

    # Any authenticated user may generate a guide for a published artifact;
    # unpublished ones require manager/admin (same rule as the API).
    can_generate_audio = request.user.is_authenticated and (
        artifact.is_published
        or request.user.role in ('admin', 'institution_manager')
    )

    context = {
        'artifact': artifact,
        'related_stories': related_stories,
        'narration': narration,
        'can_generate_audio': can_generate_audio,
        'active_nav': 'artifacts',
    }
    return render(request, 'web/artifact_detail.html', context)


# ---------------------------------------------------------------------------
# Gamification — mirrors mobile GamificationScreen (XP, badges, leaderboard)
# ---------------------------------------------------------------------------
def gamification_view(request):
    leaderboard = (
        UserProfile.objects.select_related('user')
        .order_by('-total_xp')[:20]
    )
    badges = Badge.objects.filter(is_active=True).order_by('category', 'xp_required')

    profile = None
    earned_ids = set()
    certificates = Certificate.objects.none()
    my_rank = None
    if request.user.is_authenticated:
        profile, _ = UserProfile.objects.get_or_create(user=request.user)
        earned_ids = set(
            UserBadge.objects.filter(user=request.user).values_list('badge_id', flat=True)
        )
        certificates = Certificate.objects.filter(user=request.user)
        ranked_ids = list(
            UserProfile.objects.order_by('-total_xp')
            .values_list('id', flat=True)[:200]
        )
        if profile.id in ranked_ids:
            my_rank = ranked_ids.index(profile.id) + 1

    context = {
        'profile': profile,
        'badges': badges,
        'earned_ids': earned_ids,
        'certificates': certificates,
        'leaderboard': leaderboard,
        'my_rank': my_rank,
        'active_nav': 'gamification',
    }
    return render(request, 'web/gamification.html', context)


# ---------------------------------------------------------------------------
# Quiz player — mirrors mobile QuizPlayerWidget flow
# ---------------------------------------------------------------------------
def quiz_play_view(request, quiz_id):
    if not request.user.is_authenticated:
        quiz = Quiz.objects.filter(pk=quiz_id).select_related('story').first()
        return redirect(
            f'{reverse("web:login")}?next={reverse("web:quiz-play", args=[quiz_id])}'
        )

    quiz = get_object_or_404(
        Quiz.objects.select_related('story').prefetch_related('questions'),
        pk=quiz_id,
        is_published=True,
    )

    # Resume an in-progress attempt if one exists (mirrors API start()).
    attempt = QuizAttempt.objects.filter(
        user=request.user, quiz=quiz, status=QuizAttempt.Status.IN_PROGRESS,
    ).first()

    context = {
        'quiz': quiz,
        'attempt': attempt,
        'active_nav': 'gamification',
    }
    return render(request, 'web/quiz_play.html', context)


# ---------------------------------------------------------------------------
# Admin dashboard — mirrors mobile AdminDashboardScreen (Phase 9)
# ---------------------------------------------------------------------------
def admin_dashboard_view(request):
    if not request.user.is_authenticated:
        return redirect(f'{reverse("web:login")}?next={reverse("web:admin-dashboard")}')
    if request.user.role not in ('admin', 'institution_manager'):
        from django.core.exceptions import PermissionDenied
        raise PermissionDenied('Admin or Institution Manager role required.')

    summary = get_dashboard_summary()

    # Flagged stories grouped for the moderation queue (same shape as the API).
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

    # Additional context the web dashboard surfaces beyond the summary.
    top_users = summary['gamification']['top_users']
    avg_score = summary['gamification']['avg_score']

    context = {
        'summary': summary,
        'moderation_queue': list(grouped_flags.values()),
        'top_users': top_users,
        'avg_score': avg_score,
        'active_nav': 'admin',
    }
    return render(request, 'web/admin_dashboard.html', context)


# ---------------------------------------------------------------------------
# Story form — mirrors mobile StoryFormScreen (create / edit)
# ---------------------------------------------------------------------------
def story_form_view(request, slug=None):
    """Create or edit a story — web mirror of the mobile StoryFormScreen."""
    if not request.user.is_authenticated:
        return redirect(f'{reverse("web:login")}?next={request.get_full_path()}')
    if not is_contributor_plus(request.user):
        raise PermissionDenied('Contributor role or above required to write stories.')

    story = None
    if slug:
        story = get_object_or_404(Story, slug=slug)
        # Same ownership rule as the API's IsStoryOwnerOrReadOnly.
        if story.author_id != request.user.id and request.user.role not in (
            'institution_manager', 'admin',
        ):
            raise PermissionDenied('You can only edit your own stories.')

    context = {
        'story': story,
        'editing': story is not None,
        'categories': StoryCategory.objects.all(),
        'languages': Story.Language.choices,
        'active_nav': 'library',
    }
    return render(request, 'web/story_form.html', context)


# ---------------------------------------------------------------------------
# Profile — mirrors mobile ProfileScreen (role badge, edit, delete account)
# ---------------------------------------------------------------------------
def profile_view(request):
    if not request.user.is_authenticated:
        return redirect(f'{reverse("web:login")}?next={reverse("web:profile")}')

    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    context = {
        'gamification_profile': profile,
        'active_nav': 'profile',
    }
    return render(request, 'web/profile.html', context)


# ---------------------------------------------------------------------------
# Quizzes hub — mirrors the mobile quiz entry points on GamificationScreen
# ---------------------------------------------------------------------------
def quizzes_view(request):
    """List published quizzes the signed-in user can take."""
    visible_story_ids = set(
        _visible_stories(request.user).values_list('id', flat=True)
    )
    quizzes = [
        quiz
        for quiz in Quiz.objects.filter(is_published=True)
        .select_related('story', 'story__author')
        .prefetch_related('questions')
        if quiz.story_id in visible_story_ids
    ][:24]

    latest_results = {}
    if request.user.is_authenticated:
        quiz_ids = [quiz.id for quiz in quizzes]
        attempts = (
            QuizAttempt.objects.filter(user=request.user, quiz_id__in=quiz_ids)
            .order_by('started_at')
        )
        for attempt in attempts:  # last write wins → latest attempt per quiz
            latest_results[attempt.quiz_id] = attempt

    context = {
        'quizzes': quizzes,
        'latest_results': latest_results,
        'active_nav': 'gamification',
    }
    return render(request, 'web/quizzes.html', context)


# ---------------------------------------------------------------------------
# Session auth — mirrors mobile Login/Register screens (BrandScaffold)
# ---------------------------------------------------------------------------
class WebLoginView(auth_views.LoginView):
    """Session login using the same credentials as the mobile JWT login."""

    template_name = 'web/auth/login.html'
    redirect_authenticated_user = True

    def get_success_url(self):
        next_url = self.get_redirect_url()
        return next_url or reverse(DEFAULT_LOGIN_REDIRECT)


class WebLogoutView(auth_views.LogoutView):
    template_name = 'web/auth/logout.html'
