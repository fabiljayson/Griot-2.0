from django.conf import settings
from django.db import migrations, models


def backfill_target_keys(apps, schema_editor):
    """Populate `target_key` on rows that predate the column.

    The column is added with a default of '', so without this every existing
    row would share one value and the unique index below could not be built.
    """
    AudioNarrationJob = apps.get_model('media_app', 'AudioNarrationJob')

    def key_for(story_id, artifact_id):
        if story_id and artifact_id:
            return f'both:{story_id}:{artifact_id}'
        if story_id:
            return f'story:{story_id}'
        if artifact_id:
            return f'artifact:{artifact_id}'
        return 'none'

    for job in AudioNarrationJob.objects.all().iterator():
        job.target_key = key_for(job.story_id, job.artifact_id)
        job.save(update_fields=['target_key'])


def drop_duplicate_completed_jobs(apps, schema_editor):
    """Remove duplicate completed jobs so the unique index can be created.

    Races between concurrent seed/generation runs left several completed jobs
    for the same target and language. Only the oldest is kept — the audio is
    equivalent, and the others are redundant storage.
    """
    AudioNarrationJob = apps.get_model('media_app', 'AudioNarrationJob')

    seen = set()
    for job in AudioNarrationJob.objects.filter(status='completed').order_by('id'):
        key = (job.target_key, job.language)
        if key in seen:
            job.delete()
        else:
            seen.add(key)


class Migration(migrations.Migration):

    dependencies = [
        ('media_app', '0003_audionarrationjob_engine_and_more'),
        ('qr_codes', '0002_artifact_add_narrative_fields'),
        ('stories', '0003_story_consent_status_story_licence_story_origin_and_more'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='audionarrationjob',
            name='target_key',
            field=models.CharField(
                default='',
                editable=False,
                help_text='Non-null identity of the narrated target (see build_target_key).',
                max_length=40,
            ),
        ),
        migrations.RunPython(backfill_target_keys, migrations.RunPython.noop),
        # Ordered before the index: a database cannot create a unique index
        # over data that already violates it.
        migrations.RunPython(drop_duplicate_completed_jobs, migrations.RunPython.noop),
        migrations.AddConstraint(
            model_name='audionarrationjob',
            constraint=models.UniqueConstraint(
                condition=models.Q(('status', 'completed')),
                fields=('target_key', 'language'),
                name='uniq_completed_narration_per_target_language',
            ),
        ),
    ]