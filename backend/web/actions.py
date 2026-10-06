"""
Server-rendered web actions.

These POST endpoints perform the same mutations as the DRF API actions
(like, bookmark, share, flag, quiz answers, moderation) but return plain
HTTP redirects so they work without client-side JavaScript. The mobile
app continues to use the JSON API — these share the exact same models,
keeping both platforms in sync. Business logic lives in ``web/services.py``.
"""

import datetime
import urllib.parse

from django.conf import settings
from django.contrib import messages
from django.contrib.auth import login as auth_login
from django.contrib.auth import logout as auth_logout
from django.contrib.auth.decorators import login_required
from django.core.exceptions import PermissionDenied, ValidationError
from django.http import HttpResponseBadRequest, HttpResponseRedirect, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils import translation
from django.utils.translation import gettext as _
from django.views.decorators.http import require_POST

from config.rate_limit import rate_limit
from gamification.models import Quiz, QuizQuestion
from qr_codes.models import Artifact
from qr_codes.services.qr_worklist import (
    QR_WORKLIST_LIMIT,
    generate_qr_for_artifacts,
    missing_slugs,
)
from stories.models import Story
from stories.services import record_consent, request_consent

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
    resolve_ui_language,
    save_story,
    start_quiz,
    submit_quiz_answer,
    toggle_story_bookmark,
    toggle_story_like,
    update_profile,
)
from .services import (
    set_language as persist_language,
)


def _safe_next(request, fallback):
    """Only follow same-site ?next= targets (no open redirects)."""
    next_url = request.POST.get('next') or request.GET.get('next')
    if next_url and next_url.startswith('/') and not next_url.startswith('//'):
        return next_url
    return fallback


def _parse_recorded_at(raw):
    """Parse a ``<input type="date">`` value, or ``None`` if blank/garbage.

    A malformed date must not 500 the save form; provenance is metadata, and
    an unreadable one is simply absent.
    """
    raw = (raw or '').strip()
    if not raw:
        return None
    try:
        return datetime.date.fromisoformat(raw)
    except ValueError:
        return None


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
    messages.success(request, _('Thanks — our moderators will review this story.'))
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
    # The text a reader pastes into the platform they are sharing to, so it is
    # written in the language the page is in — a French speaker sharing a story
    # from the French interface should not paste English at their friends.
    share_text = _('Check out "%(title)s" on Griot AI! 🌍📖') % {'title': story.title}
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
        return HttpResponseBadRequest(_('No active attempt.'))

    if attempt.passed:
        messages.success(
            request,
            _('🎉 You passed and earned %(xp)s XP!') % {'xp': attempt.xp_earned},
        )
    else:
        messages.info(
            request,
            _('Scored %(score)s%% — try again at %(passing)s%% to pass.')
            % {'score': attempt.score, 'passing': quiz.passing_score},
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
        return HttpResponseBadRequest(_('action must be "remove" or "dismiss".'))

    moderate_story(request.user, story, action, notes)
    if action == 'remove':
        messages.success(
            request,
            _('Story "%(title)s" archived and flags resolved.') % {'title': story.title},
        )
    else:
        messages.success(
            request,
            _('Flags on "%(title)s" dismissed.') % {'title': story.title},
        )
    return HttpResponseRedirect(_safe_next(request, reverse('web:admin-dashboard')))


# ---------------------------------------------------------------------------
# Consent — mirrors POST /api/stories/{slug}/request-consent/ and
# POST /api/stories/{slug}/consent/
#
# Two steps, deliberately. The author records that they *asked*; only a
# moderator records what the community *answered*, with who attested, when, and
# on what basis. A contributor declaring their own community's agreement is
# the claim the consent field exists to keep trustworthy.
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_request_consent(request, slug):
    story = get_object_or_404(Story, slug=slug)
    request_consent(request.user, story)
    messages.success(
        request,
        _("Consent request recorded — awaiting the community's answer."),
    )
    return HttpResponseRedirect(
        _safe_next(request, reverse('web:story-detail', args=[slug])),
    )


@login_required
@require_POST
def story_record_consent(request, slug):
    story = get_object_or_404(Story, slug=slug)
    try:
        story, archived = record_consent(
            request.user,
            story,
            status=request.POST.get('consent_status', ''),
            basis=request.POST.get('basis', ''),
            rights_holder=request.POST.get('rights_holder') or None,
            licence=request.POST.get('licence') or None,
        )
    except ValidationError as exc:
        messages.error(request, '; '.join(exc.messages))
        return HttpResponseRedirect(
            _safe_next(request, reverse('web:story-detail', args=[slug])),
        )

    if archived:
        messages.warning(
            request,
            _('Consent withheld — the story has been archived.'),
        )
    else:
        messages.success(
            request,
            _('Consent recorded for "%(title)s".') % {'title': story.title},
        )
    return HttpResponseRedirect(
        _safe_next(request, reverse('web:story-detail', args=[story.slug])),
    )


# ---------------------------------------------------------------------------
# Story create/update — mirrors POST/PUT /api/stories/ via StoryFormScreen
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_save(request, slug=None):
    """Create or update a story from the web form (fields mirror the mobile
    StoryFormScreen: title, content, summary, language, region, tags,
    cultural context, moral lesson, source, categories and status, plus the
    provenance and licence a contributor is asked to declare).

    ``consent_status`` is deliberately not read from the POST body: a
    contributor recording their own community's consent is the claim this
    field exists to make trustworthy.
    """
    title = (request.POST.get('title') or '').strip()
    content = (request.POST.get('content') or '').strip()
    if not title or not content:
        messages.error(request, _('Title and content are required.'))
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
        origin=(request.POST.get('origin') or '').strip(),
        provenance_notes=(request.POST.get('provenance_notes') or '').strip(),
        rights_holder=(request.POST.get('rights_holder') or '').strip(),
        licence=(request.POST.get('licence') or '').strip(),
        recorded_at=_parse_recorded_at(request.POST.get('recorded_at')),
    )
    messages.success(request, message)
    return redirect('web:story-detail', slug=story.slug)


@login_required
@require_POST
def story_delete(request, slug):
    """Delete a story — mirrors DELETE /api/stories/{slug}/."""
    story = get_object_or_404(Story, slug=slug)
    title = delete_story(request.user, story)
    messages.success(request, _('Story "%(title)s" deleted.') % {'title': title})
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
        # Stored copy wins over the provider URL — same rule as the API
        # serializer, kept here so the web page and the app agree on which
        # bytes they are playing.
        'video_url': job.video_file.url if job.video_file else job.video_url,
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
# QR codes — mirrors POST /api/artifacts/{slug}/generate-qr/
#
# A QR code is what a museum prints and pastes beside an object, so generating
# one is a curator's job and not a visitor's. Same rule as the API:
# institution managers and admins only, which is why this does not reuse
# `@login_required` and then check inside.
# ---------------------------------------------------------------------------
def _require_moderator(request):
    if request.user.role not in ('institution_manager', 'admin'):
        raise PermissionDenied


@login_required
@require_POST
def artifact_generate_qr(request, slug):
    """Generate (or regenerate) one artifact's printable QR code."""
    _require_moderator(request)
    artifact = get_object_or_404(Artifact, slug=slug)
    generate_qr_for_artifacts([artifact.slug])
    messages.success(
        request,
        _('QR code generated for "%(title)s".') % {'title': artifact.title},
    )
    return HttpResponseRedirect(_safe_next(request, reverse('web:admin-dashboard')))


@login_required
@require_POST
def artifacts_generate_qr(request):
    """Generate QR codes for the ticked rows of the dashboard worklist.

    ``scope`` says which button was pressed, and it is not cosmetic. Both
    forms post to this one endpoint, so a form that simply carried no ``slugs``
    could not tell "generate everything still missing" from "generate for
    selected" where the curator forgot to tick anything — the second would
    silently regenerate the whole backlog. So the tick-box form asks for
    ``selected`` and an empty selection is reported rather than widened.
    """
    _require_moderator(request)
    scope = request.POST.get('scope', 'missing')
    slugs = request.POST.getlist('slugs')

    if scope == 'selected':
        if not slugs:
            messages.info(request, _('Tick at least one artifact first.'))
            return HttpResponseRedirect(
                _safe_next(request, reverse('web:admin-dashboard')),
            )
    else:
        slugs = missing_slugs(QR_WORKLIST_LIMIT)

    generated, missing = generate_qr_for_artifacts(slugs)
    if missing:
        messages.warning(
            request,
            _('%(count)d artifact(s) were not found and were skipped.')
            % {'count': len(missing)},
        )
    if generated:
        messages.success(
            request,
            _('%(count)d QR code(s) generated.') % {'count': len(generated)},
        )
    if not generated and not missing:
        messages.info(request, _('Nothing to generate — every artifact already has a code.'))
    return HttpResponseRedirect(_safe_next(request, reverse('web:admin-dashboard')))


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
    messages.success(request, _('Profile updated.'))
    return redirect('web:profile')


@login_required
@require_POST
def profile_delete(request):
    """Permanently delete the account — mirrors DELETE /api/users/me/."""
    username = request.user.username
    auth_logout(request)
    delete_profile(username)
    messages.success(
        request,
        _('Account "%(username)s" and associated data deleted.') % {'username': username},
    )
    return redirect('web:home')


# ---------------------------------------------------------------------------
# Web settings — language + theme toggles (mirrors mobile settings provider)
# ---------------------------------------------------------------------------
@require_POST
def set_language(request):
    """Switch the interface language.

    Deliberately *not* `@login_required`. French is the language of
    administration and schooling, and the reader who most needs this page in
    French is the one who has not made an account yet — gating the switch
    behind a login showed the French-speaker an English home page and hid the
    only control that would have fixed it.

    Two stores, because there are two things to remember:
      * the language cookie, which is what `LocaleMiddleware` reads on every
        request and therefore covers anonymous visitors;
      * `WebUserSettings`, so a signed-in reader gets their language on the
        next device instead of on the next browser.

    The cookie is written with Django's own `LANGUAGE_COOKIE_*` settings and
    under `LANGUAGE_COOKIE_NAME`, which is the same cookie and the same
    attribute set Django's built-in `set_language` view uses, so the two can
    never disagree about which language is active.
    """
    code = resolve_ui_language(request.POST.get('language'))
    if request.user.is_authenticated:
        code = persist_language(request.user, code)
    response = HttpResponseRedirect(_safe_next(request, reverse('web:home')))
    response.set_cookie(
        settings.LANGUAGE_COOKIE_NAME,
        code,
        max_age=settings.LANGUAGE_COOKIE_AGE,
        path=settings.LANGUAGE_COOKIE_PATH,
        domain=settings.LANGUAGE_COOKIE_DOMAIN,
        secure=settings.LANGUAGE_COOKIE_SECURE,
        httponly=settings.LANGUAGE_COOKIE_HTTPONLY,
        samesite=settings.LANGUAGE_COOKIE_SAMESITE,
    )
    # Activate for the rest of *this* request too, so the redirect target
    # renders in the new language rather than the old one.
    translation.activate(code)
    return response


# ---------------------------------------------------------------------------
# Session registration — mirrors POST /api/auth/register/
# ---------------------------------------------------------------------------
@rate_limit('web_register', methods=('POST',), key_by='ip')
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
        messages.success(
            request,
            _('Welcome to Griot AI, %(username)s!') % {'username': user.username},
        )
        # NOTE: deliberately *not* resetting the register budget on success.
        # Unlike login, a successful registration is itself the abuse signal
        # here — clearing the budget each time would let a caller mint unlimited
        # accounts (each success resets the counter) and would defeat the cap.
        return HttpResponseRedirect(_safe_next(request, reverse('web:home')))

    return render(request, 'web/auth/register.html')