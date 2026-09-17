from django.urls import path

from . import actions, views

app_name = 'web'

urlpatterns = [
    # --- Core screens ---
    path('', views.home_view, name='home'),
    path('stories/', views.stories_view, name='stories'),
    path('story/<slug:slug>/', views.story_detail_view, name='story-detail'),
    path('library/', views.library_view, name='library'),

    # --- Story form (Contributor+) — mirrors mobile StoryFormScreen ---
    path('stories/new/', views.story_form_view, name='story-new'),
    path('stories/<slug:slug>/edit/', views.story_form_view, name='story-edit'),

    # --- Profile — mirrors mobile ProfileScreen ---
    path('profile/', views.profile_view, name='profile'),

    # --- Quizzes hub — mirrors mobile quiz entry points ---
    path('quizzes/', views.quizzes_view, name='quizzes'),

    # --- Artifacts (QR catalog) ---
    path('artifacts/', views.artifact_list_view, name='artifacts'),
    path('artifact/<slug:slug>/', views.artifact_detail_view, name='artifact-detail'),

    # --- Gamification ---
    path('gamification/', views.gamification_view, name='gamification'),
    path('quiz/<int:quiz_id>/', views.quiz_play_view, name='quiz-play'),

    # --- Admin dashboard ---
    path('dashboard/', views.admin_dashboard_view, name='admin-dashboard'),

    # --- Auth (session-based) ---
    path('accounts/login/', views.WebLoginView.as_view(), name='login'),
    path('accounts/logout/', views.WebLogoutView.as_view(), name='logout'),
    path('accounts/register/', actions.register, name='register'),

    # --- Actions (POST only) ---
    path('actions/story/<slug:slug>/like/', actions.story_like, name='story-like'),
    path('actions/story/save/', actions.story_save, name='story-save'),
    path('actions/story/<slug:slug>/save/', actions.story_save, name='story-update'),
    path('actions/story/<slug:slug>/delete/', actions.story_delete, name='story-delete'),
    path('actions/story/<slug:slug>/generate-audio/', actions.story_generate_audio, name='story-generate-audio'),
    path('actions/artifact/<slug:slug>/generate-audio/', actions.artifact_generate_audio, name='artifact-generate-audio'),
    path('actions/story/<slug:slug>/generate-video/', actions.story_generate_video, name='story-generate-video'),
    path('actions/story/<slug:slug>/video-status/', actions.story_video_status, name='story-video-status'),
    path('actions/profile/update/', actions.profile_update, name='profile-update'),
    path('actions/profile/delete/', actions.profile_delete, name='profile-delete'),
    path('actions/story/<slug:slug>/bookmark/', actions.story_bookmark, name='story-bookmark'),
    path('actions/story/<slug:slug>/flag/', actions.story_flag, name='story-flag'),
    path('actions/story/<slug:slug>/share/', actions.story_share, name='story-share'),
    path('actions/story/<slug:slug>/progress/', actions.story_progress, name='story-progress'),
    path('actions/story/<slug:slug>/moderate/', actions.story_moderate, name='story-moderate'),
    path('actions/quiz/<int:quiz_id>/start/', actions.quiz_start, name='quiz-start'),
    path('actions/quiz/<int:quiz_id>/answer/<int:question_id>/', actions.quiz_answer, name='quiz-answer'),
    path('actions/quiz/<int:quiz_id>/finish/', actions.quiz_finish, name='quiz-finish'),
    path('actions/settings/language/', actions.set_language, name='set-language'),
]
