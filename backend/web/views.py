"""
Server-rendered web views mirroring the Griot AI mobile app.

Every view consumes the same models the DRF API serves to the Flutter app,
so the two platforms always display identical data. Database access and
business rules live in ``web/services.py``; these handlers only adapt an
HTTP request into a rendered response.

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

from django.contrib.auth import views as auth_views
from django.core.exceptions import PermissionDenied
from django.shortcuts import redirect, render
from django.urls import reverse

from .auth import DEFAULT_LOGIN_REDIRECT
from .services import (
    SORT_OPTIONS,
    admin_dashboard_data,
    artifact_detail_data,
    artifact_list_data,
    gamification_data,
    home_data,
    library_data,
    profile_data,
    quiz_play_data,
    stories_data,
    story_detail_data,
    story_form_data,
    quizzes_data,
)


# ---------------------------------------------------------------------------
# Home — mirrors mobile HomeScreen
# ---------------------------------------------------------------------------
def home_view(request):
    context = home_data(request.user)
    context['active_nav'] = 'home'
    return render(request, 'web/home.html', context)


# ---------------------------------------------------------------------------
# Stories — mirrors mobile StoriesScreen (discovery dashboard)
# ---------------------------------------------------------------------------
def stories_view(request):
    data = stories_data(
        request.user,
        search=request.GET.get('search', '').strip(),
        language=request.GET.get('language', '').strip(),
        category_slug=request.GET.get('category', '').strip(),
        region=request.GET.get('region', '').strip(),
        sort=request.GET.get('sort', '-created_at'),
    )
    data['active_nav'] = 'stories'
    return render(request, 'web/stories.html', data)


# ---------------------------------------------------------------------------
# Story detail — mirrors mobile StoryDetailScreen (markdown reader)
# ---------------------------------------------------------------------------
def story_detail_view(request, slug):
    data = story_detail_data(request.user, slug)

    story = data['story']
    share_url = request.build_absolute_uri(f'/story/{story.slug}/')
    share_text = f'Check out "{story.title}" on Griot AI! 🌍'
    data.update({
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
    })
    return render(request, 'web/story_detail.html', data)


# ---------------------------------------------------------------------------
# Library — mirrors mobile LibraryScreen
# ---------------------------------------------------------------------------
def library_view(request):
    if not request.user.is_authenticated:
        return redirect(f'{reverse("web:login")}?next={reverse("web:library")}')

    context = library_data(request.user)
    context['active_nav'] = 'library'
    return render(request, 'web/library.html', context)


# ---------------------------------------------------------------------------
# Artifacts — mirrors QR scanner feature (catalog + detail)
# ---------------------------------------------------------------------------
def artifact_list_view(request):
    context = artifact_list_data(
        request.GET.get('category', '').strip(),
    )
    context['active_nav'] = 'artifacts'
    return render(request, 'web/artifacts.html', context)


def artifact_detail_view(request, slug):
    context = artifact_detail_data(request.user, request, slug)
    context['active_nav'] = 'artifacts'
    return render(request, 'web/artifact_detail.html', context)


# ---------------------------------------------------------------------------
# Gamification — mirrors mobile GamificationScreen (XP, badges, leaderboard)
# ---------------------------------------------------------------------------
def gamification_view(request):
    context = gamification_data(request.user)
    context['active_nav'] = 'gamification'
    return render(request, 'web/gamification.html', context)


# ---------------------------------------------------------------------------
# Quiz player — mirrors mobile QuizPlayerWidget flow
# ---------------------------------------------------------------------------
def quiz_play_view(request, quiz_id):
    if not request.user.is_authenticated:
        return redirect(
            f'{reverse("web:login")}?next={reverse("web:quiz-play", args=[quiz_id])}'
        )

    context = quiz_play_data(request.user, quiz_id)
    context['active_nav'] = 'gamification'
    return render(request, 'web/quiz_play.html', context)


# ---------------------------------------------------------------------------
# Admin dashboard — mirrors mobile AdminDashboardScreen (Phase 9)
# ---------------------------------------------------------------------------
def admin_dashboard_view(request):
    if not request.user.is_authenticated:
        return redirect(f'{reverse("web:login")}?next={reverse("web:admin-dashboard")}')
    if request.user.role not in ('admin', 'institution_manager'):
        raise PermissionDenied('Admin or Institution Manager role required.')

    context = admin_dashboard_data()
    context['active_nav'] = 'admin'
    return render(request, 'web/admin_dashboard.html', context)


# ---------------------------------------------------------------------------
# Story form — mirrors mobile StoryFormScreen (create / edit)
# ---------------------------------------------------------------------------
def story_form_view(request, slug=None):
    """Create or edit a story — web mirror of the mobile StoryFormScreen."""
    if not request.user.is_authenticated:
        return redirect(f'{reverse("web:login")}?next={request.get_full_path()}')

    context = story_form_data(request.user, slug)
    context['active_nav'] = 'library'
    return render(request, 'web/story_form.html', context)


# ---------------------------------------------------------------------------
# Profile — mirrors mobile ProfileScreen (role badge, edit, delete account)
# ---------------------------------------------------------------------------
def profile_view(request):
    if not request.user.is_authenticated:
        return redirect(f'{reverse("web:login")}?next={reverse("web:profile")}')

    context = profile_data(request.user)
    context['active_nav'] = 'profile'
    return render(request, 'web/profile.html', context)


# ---------------------------------------------------------------------------
# Quizzes hub — mirrors the mobile quiz entry points on GamificationScreen
# ---------------------------------------------------------------------------
def quizzes_view(request):
    """List published quizzes the signed-in user can take."""
    context = quizzes_data(request.user)
    context['active_nav'] = 'gamification'
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