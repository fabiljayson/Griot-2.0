"""
Pre-generate narration audio for seeded stories and artifacts.

Synthesizes speech with the real gTTS service (requires network access to
Google Translate's TTS endpoint) and stores the MP3 files as completed
``AudioNarrationJob`` records, so audio is ready the moment a user taps
"Listen" — the API reuses these cached narrations instead of synthesizing
on demand.

Usage:
    python manage.py seed_narrations
    python manage.py seed_narrations --force      # regenerate everything
    python manage.py seed_narrations --dry-run    # preview only (no network)
    python manage.py seed_narrations --limit 10   # cap how many are processed
    python manage.py seed_narrations --language fr  # force a language

Narration is generated for:
  - every published Story (in the story's language, mapped to gTTS support)
  - every published Artifact (its primary story, or a composed audio guide)
"""

from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand
from django.utils import timezone

from qr_codes.models import Artifact
from stories.models import Story

from media_app.models import AudioNarrationJob
from media_app.services.tts import (
    TTSGenerationError,
    build_artifact_script,
    get_tts_service,
    resolve_language,
    strip_markdown,
)


class Command(BaseCommand):
    help = (
        'Pre-generate narration audio (gTTS) for published stories and '
        'artifacts so audio is ready before users tap Listen.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--force',
            action='store_true',
            help='Regenerate narration even when a completed one already exists.',
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Preview what would be generated without making network calls.',
        )
        parser.add_argument(
            '--language',
            default=None,
            help='Force a TTS language code (default: each story\'s language).',
        )
        parser.add_argument(
            '--limit',
            type=int,
            default=None,
            help='Only process this many stories and artifacts (for quick tests).',
        )

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _get_system_user(self):
        """System account that owns pre-generated narration jobs."""
        User = get_user_model()
        user, created = User.objects.get_or_create(
            username='griot_system',
            defaults={
                'email': 'system@africanteller.org',
                'role': 'institution_manager',
                'is_staff': True,
            },
        )
        if created:
            user.set_unusable_password()
            user.save(update_fields=['password'])
        return user

    def _generate(
        self,
        service,
        *,
        user,
        story=None,
        artifact=None,
        text,
        language,
        slug,
        force,
    ):
        """Generate audio for one target and store it as a completed job."""
        if force:
            old_jobs = AudioNarrationJob.objects.filter(
                story=story,
                artifact=artifact,
                language=language,
            )
            for job in old_jobs:
                job.audio_file.delete(save=False)
            old_jobs.delete()

        try:
            result = service.submit_narration(
                text=text,
                language=language,
                slug=slug,
            )
        except TTSGenerationError as exc:
            self.stderr.write(self.style.ERROR(f'  Failed: {exc}'))
            return False

        job = AudioNarrationJob.objects.create(
            user=user,
            story=story,
            artifact=artifact,
            narration_text=text,
            language=language,
            voice_id=result['voice_id'],
            speed=1.0,
            status=AudioNarrationJob.Status.COMPLETED,
            duration=result['duration'],
            file_size=result['file_size'],
            completed_at=timezone.now(),
        )
        job.audio_file.save(
            result['filename'],
            ContentFile(result['audio_bytes']),
            save=True,
        )
        return True

    def _needs_generation(self, *, story=None, artifact=None, language, force):
        """Whether a completed narration already exists for this target."""
        if force:
            return True
        return not AudioNarrationJob.objects.filter(
            story=story,
            artifact=artifact,
            language=language,
            status=AudioNarrationJob.Status.COMPLETED,
        ).exists()

    # ------------------------------------------------------------------
    # Command
    # ------------------------------------------------------------------
    def handle(self, *args, **options):
        force = options['force']
        dry_run = options['dry_run']
        limit = options['limit']
        language_override = options['language']

        service = get_tts_service()
        system_user = None if dry_run else self._get_system_user()

        stories = Story.objects.filter(status=Story.Status.PUBLISHED).order_by('id')
        artifacts = Artifact.objects.filter(is_published=True).order_by('id')
        if limit:
            stories = stories[:limit]
            artifacts = artifacts[:limit]

        generated = skipped = failed = 0

        # --- Stories ---------------------------------------------------
        for story in stories:
            language = language_override or resolve_language(story.language)
            text = strip_markdown(story.content)
            if not text:
                continue

            if not self._needs_generation(
                story=story,
                artifact=None,
                language=language,
                force=force,
            ):
                skipped += 1
                self.stdout.write(f'  Skipped story: {story.title} (narration exists)')
                continue

            if dry_run:
                generated += 1
                self.stdout.write(f'  Would narrate story: {story.title} [{language}]')
                continue

            self.stdout.write(f'  Narrating story: {story.title} [{language}]...')
            ok = self._generate(
                service,
                user=system_user,
                story=story,
                artifact=None,
                text=text,
                language=language,
                slug=story.slug or story.title,
                force=force,
            )
            if ok:
                generated += 1
                self.stdout.write(self.style.SUCCESS(f'    -> {story.title} done'))
            else:
                failed += 1

        # --- Artifacts (audio guides) ----------------------------------
        for artifact in artifacts:
            language = language_override or 'en'
            text = build_artifact_script(artifact)
            if not text:
                continue

            # Link the artifact's primary story (if any) so the job shows
            # both the artifact and its story — same convention as the API.
            primary_story = (
                artifact.stories
                .filter(status=Story.Status.PUBLISHED)
                .order_by('id')
                .first()
            )

            if not self._needs_generation(
                story=primary_story,
                artifact=artifact,
                language=language,
                force=force,
            ):
                skipped += 1
                self.stdout.write(
                    f'  Skipped artifact: {artifact.title} (narration exists)'
                )
                continue

            if dry_run:
                generated += 1
                self.stdout.write(
                    f'  Would narrate artifact: {artifact.title} [{language}]'
                )
                continue

            self.stdout.write(f'  Narrating artifact: {artifact.title} [{language}]...')
            ok = self._generate(
                service,
                user=system_user,
                story=primary_story,
                artifact=artifact,
                text=text,
                language=language,
                slug=artifact.slug or artifact.title,
                force=force,
            )
            if ok:
                generated += 1
                self.stdout.write(self.style.SUCCESS(f'    -> {artifact.title} done'))
            else:
                failed += 1

        self.stdout.write(
            self.style.SUCCESS(
                f'\nDone: {generated} generated, {skipped} skipped, {failed} failed.'
            )
        )
