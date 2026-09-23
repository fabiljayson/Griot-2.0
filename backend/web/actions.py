"""
Server-rendered web actions.

These POST endpoints perform the same mutations as the DRF API actions
(like, bookmark, share, flag, quiz answers, moderation) but return plain
HTTP redirects so they work without client-side JavaScript. The mobile
app continues to use the JSON API — these share the exact same models,
keeping both platforms in sync. Business logic lives in ``web/services.py``.
"""

import urllib.parse

from django.contrib import messages
from django.contrib.auth import login as auth_login
from django.contrib.auth import logout as auth_logout
from django.contrib.auth.decorators import login_required
from django.http import HttpResponseBadRequest, HttpResponseRedirect, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.views.decorators.http import require_POST

from gamification.models import Quiz, QuizQuestion
from qr_codes.models import Artifact
from stories.models import Story

from .services import (
    delete_profile,
    delete_story,
    finish_quiz,
    flag_story,
    generate_artifact_audio,
    generate_story_audio,
    generate_story_video,
    moderate_story,
    record_progress,
    record_story_share,
    refresh_video_job,
    register_user,
    save_story,
    set_language as persist_language,
    start_quiz,
    submit_quiz_answer,
    toggle_story_bookmark,
    toggle_story_like,
    update_profile,
)


def _safe_next(request, fallback):
    """Only follow same-site ?next= targets (no open redirects)."""
    next_url = request.POST.get('next') or request.GET.get('next')
    if next_url and next_url.startswith('/') and not next_url.startswith('//'):
        return next_url
    return fallback


# ---------------------------------------------------------------------------
# Story interactions — mirrors POST /api/stories/{slug}/like|bookmark|flag
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_like(request, slug):
    story = get_object_or_404(Story, slug=slug)
    toggle_story_like(request.user, story)
    return HttpResponseRedirect(_safe_next(request, reverse('web:story-detail', args=[slug])))


@login_required
@require_POST
def story_bookmark(request, slug):
    story = get_object_or_404(Story, slug=slug)
    toggle_story_bookmark(request.user, story)
    return HttpResponseRedirect(_safe_next(request, reverse('web:story-detail', args=[slug])))


@login_required
@require_POST
def story_flag(request, slug):
    story = get_object_or_404(Story, slug=slug)
    flag_story(
        request.user,
        story,
        reason=request.POST.get('reason', 'other'),
        details=request.POST.get('details', ''),
    )
    messages.success(request, 'Thanks — our moderators will review this story.')
    return HttpResponseRedirect(_safe_next(request, reverse('web:story-detail', args=[slug])))


@login_required
@require_POST
def story_share(request, slug):
    """Track a share and hand the user a pre-filled share target."""
    story = get_object_or_404(Story, slug=slug)
    platform = request.POST.get('platform', 'other')
    record_story_share(
        request.user, story, platform, request.META.get('REMOTE_ADDR'),
    )

    share_url = request.build_absolute_uri(f'/story/{story.slug}/')
    share_text = f'Check out "{story.title}" on Griot AI! 🌍📖'
    targets = {
        'twitter': f'https://twitter.com/intent/tweet?url={share_url}&text={share_text}',
        'facebook': f'https://www.facebook.com/sharer/sharer.php?u={share_url}',
        'whatsapp': f'https://wa.me/?text={share_text}%20{share_url}',
        'telegram': f'https://t.me/share/url?url={share_url}&text={share_text}',
    }

    target = targets.get(platform)
    if target:
        return HttpResponseRedirect(
            target.replace(share_text, urllib.parse.quote(share_text))
            .replace(share_url, urllib.parse.quote(share_url))
        )
    return HttpResponseRedirect(_safe_next(request, reverse('web:story-detail', args=[slug])))


# ---------------------------------------------------------------------------
# Reading progress — mirrors POST /api/stories/{slug}/progress/
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_progress(request, slug):
    story = get_object_or_404(Story, slug=slug)
    try:
        percent = min(100, max(0, int(request.POST.get('progress_percent', 0))))
    except (TypeError, ValueError):
        percent = 0
    record_progress(request.user, story, percent)
    return HttpResponseRedirect(_safe_next(request, reverse('web:story-detail', args=[slug])))


# ---------------------------------------------------------------------------
# Quiz actions — mirrors /api/gamification/quizzes/{id}/start|submit_answer|finish
# ---------------------------------------------------------------------------
@login_required
@require_POST
def quiz_start(request, quiz_id):
    quiz = get_object_or_404(Quiz, pk=quiz_id, is_published=True)
    start_quiz(request.user, quiz)
    return redirect('web:quiz-play', quiz_id=quiz.id)


@login_required
@require_POST
def quiz_answer(request, quiz_id, question_id):
    quiz = get_object_or_404(Quiz, pk=quiz_id)
    question = get_object_or_404(QuizQuestion, pk=question_id, quiz=quiz)

    error = submit_quiz_answer(
        request.user, quiz, question, request.POST.get('answer', ''),
    )
    if error is not None:
        return HttpResponseBadRequest(error)
    return redirect('web:quiz-play', quiz_id=quiz.id)


@login_required
@require_POST
def quiz_finish(request, quiz_id):
    quiz = get_object_or_404(Quiz, pk=quiz_id)
    attempt = finish_quiz(request.user, quiz)
    if attempt is None:
        return HttpResponseBadRequest('No active attempt.')

    if attempt.passed:
        messages.success(
            request, f'🎉 You passed and earned {attempt.xp_earned} XP!',
        )
    else:
        messages.info(
            request,
            f'Scored {attempt.score}% — try again at {quiz.passing_score}% to pass.',
        )
    return redirect('web:quiz-play', quiz_id=quiz.id)


# ---------------------------------------------------------------------------
# Moderation — mirrors POST /api/stories/{slug}/moderate/
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_moderate(request, slug):
    story = get_object_or_404(Story, slug=slug)
    action = request.POST.get('action', '')
    notes = request.POST.get('notes', '')
    if action not in ('remove', 'dismiss'):
        return HttpResponseBadRequest('action must be "remove" or "dismiss".')

    moderate_story(request.user, story, action, notes)
    if action == 'remove':
        messages.success(request, f'Story "{story.title}" archived and flags resolved.')
    else:
        messages.success(request, f'Flags on "{story.title}" dismissed.')
    return HttpResponseRedirect(_safe_next(request, reverse('web:admin-dashboard')))


# ---------------------------------------------------------------------------
# Story create/update — mirrors POST/PUT /api/stories/ via StoryFormScreen
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_save(request, slug=None):
    """Create or update a story from the web form (fields mirror the mobile
    StoryFormScreen: title, content, summary, language, region, tags,
    cultural context, moral lesson, source, categories and status)."""
    title = (request.POST.get('title') or '').strip()
    content = (request.POST.get('content') or '').strip()
    if not title or not content:
        messages.error(request, 'Title and content are required.')
        if slug:
            return redirect('web:story-edit', slug=slug)
        return redirect('web:story-new')

    story, message = save_story(
        request.user,
        slug=slug,
        title=title,
        content=content,
        summary=(request.POST.get('summary') or '').strip(),
        language=request.POST.get('language', 'en'),
        region=(request.POST.get('region') or '').strip(),
        tags=(request.POST.get('tags') or '').strip(),
        cultural_context=(request.POST.get('cultural_context') or '').strip(),
        moral_lesson=(request.POST.get('moral_lesson') or '').strip(),
        source=(request.POST.get('source') or '').strip(),
        status=request.POST.get('status', 'draft'),
        category_ids=request.POST.getlist('categories'),
    )
    messages.success(request, message)
    return redirect('web:story-detail', slug=story.slug)


@login_required
@require_POST
def story_delete(request, slug):
    """Delete a story — mirrors DELETE /api/stories/{slug}/."""
    story = get_object_or_404(Story, slug=slug)
    title = delete_story(request.user, story)
    messages.success(request, f'Story "{title}" deleted.')
    return redirect('web:library')


# ---------------------------------------------------------------------------
# Media: TTS narration — mirrors POST /api/media/audio/ (§6)
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_generate_audio(request, slug):
    story = get_object_or_404(Story, slug=slug)
    language = request.POST.get('language', story.language or 'en')
    message, kind = generate_story_audio(request.user, story, language)
    getattr(messages, kind)(request, message)
    return redirect('web:story-detail', slug=story.slug)


# ---------------------------------------------------------------------------
# Media: AI video — mirrors POST /api/media/videos/ + status polling (§7)
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_generate_video(request, slug):
    story = get_object_or_404(Story, slug=slug)
    prompt = (request.POST.get('prompt') or '').strip()
    message, kind = generate_story_video(request.user, story, prompt)
    getattr(messages, kind)(request, message)
    return redirect('web:story-detail', slug=story.slug)


@login_required
def story_video_status(request, slug):
    """Poll the Luma mock service and refresh the job (AJAX JSON)."""
    story = get_object_or_404(Story, slug=slug)
    job = refresh_video_job(request.user, story)
    if job is None:
        return JsonResponse({'status': 'none'}, status=404)
    return JsonResponse({
        'status': job.status,
        'video_url': job.video_url,
        'thumbnail_url': job.thumbnail_url,
    })


# ---------------------------------------------------------------------------
# Media: artifact audio guide — mirrors POST /api/media/audio/ (§5 + §6)
# ---------------------------------------------------------------------------
@login_required
@require_POST
def artifact_generate_audio(request, slug):
    """Generate the museum audio guide for an artifact.

    Permission mirrors the API: published artifacts can be narrated by any
    authenticated user; unpublished ones require manager/admin.
    """
    artifact = get_object_or_404(Artifact, slug=slug)
    language = request.POST.get('language', 'en')
    message, kind = generate_artifact_audio(request.user, artifact, language)
    getattr(messages, kind)(request, message)
    return redirect('web:artifact-detail', slug=artifact.slug)


# ---------------------------------------------------------------------------
# Profile — mirrors PATCH /api/users/me/ and DELETE /api/users/me/ (§1)
# ---------------------------------------------------------------------------
@login_required
@require_POST
def profile_update(request):
    """Update editable profile fields (role is not self-service, like the API)."""
    errors, changed = update_profile(
        request.user,
        first_name=(request.POST.get('first_name') or '').strip(),
        last_name=(request.POST.get('last_name') or '').strip(),
        email=(request.POST.get('email') or '').strip().lower(),
        institution=(request.POST.get('institution') or '').strip(),
    )
    if not changed:
        for error in errors:
            messages.error(request, error)
        return redirect('web:profile')
    messages.success(request, 'Profile updated.')
    return redirect('web:profile')


@login_required
@require_POST
def profile_delete(request):
    """Permanently delete the account — mirrors DELETE /api/users/me/."""
    username = request.user.username
    auth_logout(request)
    delete_profile(username)
    messages.success(request, f'Account "{username}" and associated data deleted.')
    return redirect('web:home')


# ---------------------------------------------------------------------------
# Web settings — language + theme toggles (mirrors mobile settings provider)
# ---------------------------------------------------------------------------
@login_required
@require_POST
def set_language(request):
    code = persist_language(request.user, request.POST.get('language', 'en'))
    return HttpResponseRedirect(_safe_next(request, reverse('web:home')))


# ---------------------------------------------------------------------------
# Session registration — mirrors POST /api/auth/register/
# ---------------------------------------------------------------------------
def register(request):
    if request.method == 'POST':
        user, errors = register_user(
            username=request.POST.get('username', ''),
            email=request.POST.get('email', ''),
            password=request.POST.get('password', ''),
            password2=request.POST.get('password2', ''),
            role=request.POST.get('role', 'visitor'),
        )
        if errors:
            return render(
                request, 'web/auth/register.html',
                {'errors': errors, 'form_data': request.POST},
                status=400,
            )

        auth_login(request, user)
        messages.success(request, f'Welcome to Griot AI, {user.username}!')
        return HttpResponseRedirect(_safe_next(request, reverse('web:home')))

    return render(request, 'web/auth/register.html')