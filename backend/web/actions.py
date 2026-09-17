"""
Server-rendered web actions.

These POST endpoints perform the same mutations as the DRF API actions
(like, bookmark, share, flag, quiz answers, moderation) but return plain
HTTP redirects so they work without client-side JavaScript. The mobile
app continues to use the JSON API — these share the exact same models,
keeping both platforms in sync.
"""

from django.contrib import messages
from django.contrib.auth import login as auth_login
from django.contrib.auth import get_user_model
from django.contrib.auth.decorators import login_required
from django.core.exceptions import PermissionDenied
from django.db.models import F
from django.http import HttpResponseBadRequest, HttpResponseRedirect, JsonResponse
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils import timezone
from django.views.decorators.http import require_POST

from gamification.models import Quiz, QuizAttempt, QuizQuestion
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
    like, created = StoryLike.objects.get_or_create(user=request.user, story=story)
    if not created:
        like.delete()
        Story.objects.filter(pk=story.pk).update(
            like_count=max(0, story.like_count - 1)
        )
    else:
        Story.objects.filter(pk=story.pk).update(like_count=F('like_count') + 1)
    return HttpResponseRedirect(_safe_next(request, reverse('web:story-detail', args=[slug])))


@login_required
@require_POST
def story_bookmark(request, slug):
    story = get_object_or_404(Story, slug=slug)
    bookmark, created = StoryBookmark.objects.get_or_create(user=request.user, story=story)
    if not created:
        bookmark.delete()
        Story.objects.filter(pk=story.pk).update(
            bookmark_count=max(0, story.bookmark_count - 1)
        )
    else:
        Story.objects.filter(pk=story.pk).update(bookmark_count=F('bookmark_count') + 1)
    return HttpResponseRedirect(_safe_next(request, reverse('web:story-detail', args=[slug])))


@login_required
@require_POST
def story_flag(request, slug):
    story = get_object_or_404(Story, slug=slug)
    reason = request.POST.get('reason', 'other')
    valid_reasons = {c for c, _ in StoryFlag.Reason.choices}
    if reason not in valid_reasons:
        reason = StoryFlag.Reason.OTHER
    # One flag per user/story — update details if already flagged.
    StoryFlag.objects.update_or_create(
        user=request.user,
        story=story,
        defaults={
            'reason': reason,
            'details': request.POST.get('details', ''),
            'resolved': False,
        },
    )
    messages.success(request, 'Thanks — our moderators will review this story.')
    return HttpResponseRedirect(_safe_next(request, reverse('web:story-detail', args=[slug])))


@login_required
@require_POST
def story_share(request, slug):
    """Track a share and hand the user a pre-filled share target."""
    story = get_object_or_404(Story, slug=slug)
    platform = request.POST.get('platform', 'other')
    valid_platforms = {p for p, _ in StoryShare.PLATFORM_CHOICES}
    if platform not in valid_platforms:
        platform = 'other'

    StoryShare.objects.create(
        story=story,
        user=request.user,
        platform=platform,
        ip_address=request.META.get('REMOTE_ADDR'),
    )
    Story.objects.filter(pk=story.pk).update(share_count=F('share_count') + 1)

    share_url = request.build_absolute_uri(f'/story/{story.slug}/')
    share_text = f'Check out "{story.title}" on Griot AI! 🌍📖'
    targets = {
        'twitter': f'https://twitter.com/intent/tweet?url={share_url}&text={share_text}',
        'facebook': f'https://www.facebook.com/sharer/sharer.php?u={share_url}',
        'whatsapp': f'https://wa.me/?text={share_text}%20{share_url}',
        'telegram': f'https://t.me/share/url?url={share_url}&text={share_text}',
    }
    import urllib.parse

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

    progress, _ = ReadingProgress.objects.get_or_create(user=request.user, story=story)
    just_completed = percent >= 95 and not progress.completed
    progress.progress_percent = max(progress.progress_percent, percent)
    if percent >= 95:
        progress.completed = True
    progress.last_read_position = percent
    progress.save()

    # Keep gamification stats aligned with reading activity (§4.6):
    # completed stories count once, and the daily streak updates per day.
    from gamification.models import UserProfile

    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    if just_completed:
        profile.stories_completed += 1
        profile.stories_read += 1
    elif profile.stories_read == 0:
        profile.stories_read = 1
    profile.update_streak()
    profile.save(update_fields=['stories_read', 'stories_completed'])

    return HttpResponseRedirect(_safe_next(request, reverse('web:story-detail', args=[slug])))


# ---------------------------------------------------------------------------
# Quiz actions — mirrors /api/gamification/quizzes/{id}/start|submit_answer|finish
# ---------------------------------------------------------------------------
@login_required
@require_POST
def quiz_start(request, quiz_id):
    quiz = get_object_or_404(Quiz, pk=quiz_id, is_published=True)
    attempt, _ = QuizAttempt.objects.get_or_create(
        user=request.user,
        quiz=quiz,
        status=QuizAttempt.Status.IN_PROGRESS,
        defaults={'total_questions': quiz.question_count},
    )
    return redirect('web:quiz-play', quiz_id=quiz.id)


@login_required
@require_POST
def quiz_answer(request, quiz_id, question_id):
    quiz = get_object_or_404(Quiz, pk=quiz_id)
    question = get_object_or_404(QuizQuestion, pk=question_id, quiz=quiz)
    attempt = QuizAttempt.objects.filter(
        user=request.user, quiz=quiz, status=QuizAttempt.Status.IN_PROGRESS,
    ).first()
    if attempt is None:
        return HttpResponseBadRequest('No active attempt — start the quiz first.')

    selected = request.POST.get('answer', '')
    if selected not in ('a', 'b', 'c', 'd'):
        return HttpResponseBadRequest('Invalid answer.')

    answers = attempt.answers or []
    if any(a.get('question_id') == question.id for a in answers):
        return HttpResponseBadRequest('Question already answered.')

    answers.append({
        'question_id': question.id,
        'selected_answer': selected,
        'correct_answer': question.correct_answer,
        'is_correct': selected == question.correct_answer,
        'explanation': question.explanation,
    })
    attempt.answers = answers
    attempt.save(update_fields=['answers'])
    return redirect('web:quiz-play', quiz_id=quiz.id)


@login_required
@require_POST
def quiz_finish(request, quiz_id):
    quiz = get_object_or_404(Quiz, pk=quiz_id)
    attempt = QuizAttempt.objects.filter(
        user=request.user, quiz=quiz, status=QuizAttempt.Status.IN_PROGRESS,
    ).first()
    if attempt is None:
        return HttpResponseBadRequest('No active attempt.')

    attempt.calculate_score()
    attempt.status = QuizAttempt.Status.COMPLETED
    attempt.completed_at = timezone.now()
    attempt.time_taken_seconds = int(
        (attempt.completed_at - attempt.started_at).total_seconds()
    )

    if attempt.passed:
        from gamification.models import UserBadge, UserProfile

        attempt.xp_earned = quiz.xp_reward
        profile, _ = UserProfile.objects.get_or_create(user=request.user)
        profile.add_xp(quiz.xp_reward)
        profile.quizzes_passed += 1
        profile.total_quiz_xp += quiz.xp_reward
        profile.save(update_fields=['quizzes_passed', 'total_quiz_xp'])

        # Badge eligibility — same rules as the API QuizViewSet.
        earned_ids = UserBadge.objects.filter(user=request.user).values_list(
            'badge_id', flat=True,
        )
        for badge in quiz._meta.apps.get_model('gamification', 'Badge').objects.filter(
            is_active=True,
        ).exclude(id__in=earned_ids):
            if (
                (badge.xp_required and profile.total_xp >= badge.xp_required)
                or (badge.stories_read_required and profile.stories_read >= badge.stories_read_required)
                or (badge.quizzes_passed_required and profile.quizzes_passed >= badge.quizzes_passed_required)
            ):
                UserBadge.objects.create(user=request.user, badge=badge)

        messages.success(
            request, f'🎉 You passed and earned {quiz.xp_reward} XP!',
        )
    else:
        messages.info(request, f'Scored {attempt.score}% — try again at {quiz.passing_score}% to pass.')

    attempt.save()
    return redirect('web:quiz-play', quiz_id=quiz.id)


# ---------------------------------------------------------------------------
# Moderation — mirrors POST /api/stories/{slug}/moderate/
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_moderate(request, slug):
    if request.user.role not in ('admin', 'institution_manager'):
        from django.core.exceptions import PermissionDenied
        raise PermissionDenied('Moderator role required.')

    story = get_object_or_404(Story, slug=slug)
    action = request.POST.get('action', '')
    notes = request.POST.get('notes', '')
    if action not in ('remove', 'dismiss'):
        return HttpResponseBadRequest('action must be "remove" or "dismiss".')

    StoryFlag.objects.filter(story=story, resolved=False).update(
        resolved=True,
        resolution_notes=notes,
    )
    if action == 'remove':
        story.status = Story.Status.ARCHIVED
        story.reviewer_notes = notes
        story.save(update_fields=['status', 'reviewer_notes', 'updated_at'])
        messages.success(request, f'Story "{story.title}" archived and flags resolved.')
    else:
        messages.success(request, f'Flags on "{story.title}" dismissed.')

    return HttpResponseRedirect(_safe_next(request, reverse('web:admin-dashboard')))


# ---------------------------------------------------------------------------
# Story create/update — mirrors POST/PUT /api/stories/ via StoryFormScreen
# ---------------------------------------------------------------------------
def _contributor_plus(user):
    return user.is_authenticated and user.role in (
        'contributor', 'institution_manager', 'admin',
    )


@login_required
@require_POST
def story_save(request, slug=None):
    """Create or update a story from the web form (fields mirror the mobile
    StoryFormScreen: title, content, summary, language, region, tags,
    cultural context, moral lesson, source, categories and status)."""
    if not _contributor_plus(request.user):
        raise PermissionDenied('Contributor role or above required.')

    story = None
    if slug:
        story = get_object_or_404(Story, slug=slug)
        if story.author_id != request.user.id and request.user.role not in (
            'institution_manager', 'admin',
        ):
            raise PermissionDenied('You can only edit your own stories.')

    title = (request.POST.get('title') or '').strip()
    content = (request.POST.get('content') or '').strip()
    if not title or not content:
        messages.error(request, 'Title and content are required.')
        if slug:
            return redirect('web:story-edit', slug=slug)
        return redirect('web:story-new')

    # 'draft' or 'pending' only — publication is a moderator decision,
    # exactly like the mobile form's Save Draft / Submit for Review buttons.
    status = request.POST.get('status', 'draft')
    if status not in (Story.Status.DRAFT, Story.Status.PENDING):
        status = Story.Status.DRAFT

    fields = {
        'title': title,
        'content': content,
        'summary': (request.POST.get('summary') or '').strip(),
        'language': request.POST.get('language', 'en'),
        'region': (request.POST.get('region') or '').strip(),
        'tags': (request.POST.get('tags') or '').strip(),
        'cultural_context': (request.POST.get('cultural_context') or '').strip(),
        'moral_lesson': (request.POST.get('moral_lesson') or '').strip(),
        'source': (request.POST.get('source') or '').strip(),
    }
    if fields['language'] not in {c for c, _ in Story.Language.choices}:
        fields['language'] = Story.Language.ENGLISH

    category_ids = request.POST.getlist('categories')
    categories = StoryCategory.objects.filter(id__in=category_ids)

    if story is None:
        story = Story.objects.create(author=request.user, status=status, **fields)
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
    messages.success(request, message)
    return redirect('web:story-detail', slug=story.slug)


@login_required
@require_POST
def story_delete(request, slug):
    """Delete a story — mirrors DELETE /api/stories/{slug}/."""
    story = get_object_or_404(Story, slug=slug)
    if story.author_id != request.user.id and request.user.role not in (
        'institution_manager', 'admin',
    ):
        raise PermissionDenied('You can only delete your own stories.')
    title = story.title
    story.delete()
    messages.success(request, f'Story "{title}" deleted.')
    return redirect('web:library')


# ---------------------------------------------------------------------------
# Media: TTS narration — mirrors POST /api/media/audio/ (§6)
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_generate_audio(request, slug):
    story = get_object_or_404(Story, slug=slug)
    if (
        story.author_id != request.user.id
        and request.user.role not in ('admin', 'institution_manager')
        and story.status != Story.Status.PUBLISHED
    ):
        raise PermissionDenied('You can only generate audio for your own or published stories.')

    # Reuse a completed narration, mirroring the API create() behavior.
    language = request.POST.get('language', story.language or 'en')
    existing = AudioNarrationJob.objects.filter(
        story=story,
        language=language,
        status=AudioNarrationJob.Status.COMPLETED,
    ).order_by('-created_at').first()
    if existing is not None:
        messages.info(request, 'This story already has a narration ready.')
        return redirect('web:story-detail', slug=story.slug)

    narration_text = strip_markdown(story.content)
    if not narration_text.strip():
        messages.error(request, 'There is no text available to narrate.')
        return redirect('web:story-detail', slug=story.slug)

    job = AudioNarrationJob.objects.create(
        user=request.user,
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
        from django.core.files.base import ContentFile

        job.audio_file.save(
            result['filename'], ContentFile(result['audio_bytes']), save=False,
        )
        job.duration = result['duration']
        job.file_size = result['file_size']
        job.status = AudioNarrationJob.Status.COMPLETED
        job.completed_at = timezone.now()
        job.save()
        messages.success(request, '🔊 Narration generated — press play to listen.')
    except TTSGenerationError as exc:
        job.status = AudioNarrationJob.Status.FAILED
        job.error_message = str(exc)
        job.save()
        messages.error(request, f'Narration failed: {exc}')
    return redirect('web:story-detail', slug=story.slug)


# ---------------------------------------------------------------------------
# Media: AI video — mirrors POST /api/media/videos/ + status polling (§7)
# ---------------------------------------------------------------------------
@login_required
@require_POST
def story_generate_video(request, slug):
    story = get_object_or_404(Story, slug=slug)
    if story.author_id != request.user.id and request.user.role not in (
        'admin', 'institution_manager',
    ):
        raise PermissionDenied('You can only generate videos for your own stories.')

    prompt = (request.POST.get('prompt') or '').strip()
    if not prompt:
        prompt = (
            f'Visualize this African tale: {story.title}. {story.summary or story.title}'
        )

    # One active job at a time per story/user (mirrors the mobile sheet).
    active = VideoGenerationJob.objects.filter(
        story=story, user=request.user,
        status__in=(VideoGenerationJob.Status.PENDING, VideoGenerationJob.Status.PROCESSING),
    ).first()
    if active is not None:
        messages.info(request, 'A video is already being generated for this story.')
        return redirect('web:story-detail', slug=story.slug)

    job = VideoGenerationJob.objects.create(
        user=request.user,
        story=story,
        prompt=prompt,
        status=VideoGenerationJob.Status.PENDING,
    )
    luma_service = get_luma_service()
    result = luma_service.submit_video_generation(prompt=prompt)
    job.luma_job_id = result['id']
    job.save()
    messages.success(request, '🎬 Video generation started — check back shortly.')
    return redirect('web:story-detail', slug=story.slug)


@login_required
def story_video_status(request, slug):
    """Poll the Luma mock service and refresh the job (AJAX JSON)."""
    story = get_object_or_404(Story, slug=slug)
    job = (
        VideoGenerationJob.objects.filter(story=story, user=request.user)
        .order_by('-created_at')
        .first()
    )
    if job is None:
        return JsonResponse({'status': 'none'}, status=404)

    if job.luma_job_id and job.status in (
        VideoGenerationJob.Status.PENDING, VideoGenerationJob.Status.PROCESSING,
    ):
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
    if (
        not artifact.is_published
        and request.user.role not in ('admin', 'institution_manager')
    ):
        raise PermissionDenied('You can only generate audio for published artifacts.')

    # Reuse a completed guide, mirroring the API create() behavior.
    language = request.POST.get('language', 'en')
    existing = AudioNarrationJob.objects.filter(
        artifact=artifact,
        language=language,
        status=AudioNarrationJob.Status.COMPLETED,
    ).order_by('-created_at').first()
    if existing is not None:
        messages.info(request, 'This artifact already has an audio guide ready.')
        return redirect('web:artifact-detail', slug=artifact.slug)

    narration_text = build_artifact_script(artifact)
    if not narration_text.strip():
        messages.error(request, 'There is no text available to narrate.')
        return redirect('web:artifact-detail', slug=artifact.slug)

    # Link the artifact's primary published story, exactly like the API does.
    primary_story = artifact.stories.filter(
        status=Story.Status.PUBLISHED,
    ).order_by('id').first()

    job = AudioNarrationJob.objects.create(
        user=request.user,
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
        from django.core.files.base import ContentFile

        job.audio_file.save(
            result['filename'], ContentFile(result['audio_bytes']), save=False,
        )
        job.duration = result['duration']
        job.file_size = result['file_size']
        job.status = AudioNarrationJob.Status.COMPLETED
        job.completed_at = timezone.now()
        job.save()
        messages.success(request, '🔊 Audio guide generated — press play to listen.')
    except TTSGenerationError as exc:
        job.status = AudioNarrationJob.Status.FAILED
        job.error_message = str(exc)
        job.save()
        messages.error(request, f'Narration failed: {exc}')
    return redirect('web:artifact-detail', slug=artifact.slug)


# ---------------------------------------------------------------------------
# Profile — mirrors PATCH /api/users/me/ and DELETE /api/users/me/ (§1)
# ---------------------------------------------------------------------------
@login_required
@require_POST
def profile_update(request):
    """Update editable profile fields (role is not self-service, like the API)."""
    user = request.user
    first_name = (request.POST.get('first_name') or '').strip()
    last_name = (request.POST.get('last_name') or '').strip()
    email = (request.POST.get('email') or '').strip().lower()
    institution = (request.POST.get('institution') or '').strip()

    errors = []
    if email and User.objects.filter(email__iexact=email).exclude(pk=user.pk).exists():
        errors.append('A user with this email already exists.')
    if errors:
        for error in errors:
            messages.error(request, error)
        return redirect('web:profile')

    user.first_name = first_name
    user.last_name = last_name
    if email:
        user.email = email
    if user.role == 'institution_manager':
        user.institution = institution
    user.save(update_fields=['first_name', 'last_name', 'email', 'institution'])
    messages.success(request, 'Profile updated.')
    return redirect('web:profile')


@login_required
@require_POST
def profile_delete(request):
    """Permanently delete the account — mirrors DELETE /api/users/me/."""
    from django.contrib.auth import logout as auth_logout

    username = request.user.username
    auth_logout(request)
    User.objects.filter(username=username).delete()
    messages.success(request, f'Account "{username}" and associated data deleted.')
    return redirect('web:home')


# ---------------------------------------------------------------------------
# Web settings — language + theme toggles (mirrors mobile settings provider)
# ---------------------------------------------------------------------------
@login_required
@require_POST
def set_language(request):
    code = request.POST.get('language', 'en')
    valid = {code for code, _ in Story.Language.choices}
    if code not in valid:
        code = 'en'
    settings_obj, _ = WebUserSettings.objects.get_or_create(user=request.user)
    settings_obj.language = code
    settings_obj.save(update_fields=['language'])
    return HttpResponseRedirect(_safe_next(request, reverse('web:home')))


# ---------------------------------------------------------------------------
# Session registration — mirrors POST /api/auth/register/
# ---------------------------------------------------------------------------
def register(request):
    if request.method == 'POST':
        username = (request.POST.get('username') or '').strip()
        email = (request.POST.get('email') or '').strip().lower()
        password = request.POST.get('password') or ''
        password2 = request.POST.get('password2') or ''
        role = request.POST.get('role', 'visitor')
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
            return render(
                request, 'web/auth/register.html',
                {'errors': errors, 'form_data': request.POST},
                status=400,
            )

        user = User.objects.create_user(
            username=username,
            email=email,
            password=password,
            role=role,
        )
        auth_login(request, user)
        messages.success(request, f'Welcome to Griot AI, {user.username}!')
        return HttpResponseRedirect(_safe_next(request, reverse('web:home')))

    return render(request, 'web/auth/register.html')
