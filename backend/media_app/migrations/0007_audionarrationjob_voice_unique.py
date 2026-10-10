"""Give the completed-narration uniqueness constraint a voice.

Changing the narration voice used to be invisible to the database: the
constraint only knew (target, language), so the first time a reader picked a
second voice the insert of that second *completed* row would be rejected and
the request would 500. The voice belongs in the key — same story, different
voice, is a genuinely different recording.

The legacy rows come first: jobs created before this migration store the
literal placeholder ``default`` (or an empty string) in ``voice_id``, which
the endpoints now normalise to the job's own language (``en``, ``fr``, …).
The data pass rewrites those in place so that, once the constraint includes
the voice, old and new rows for the same recording still collide — the
guarantee keeps holding across the migration instead of quietly weakening.

Historical SQLite note: UPDATE inside a migration that also alters
constraints is executed with the schema editor's atomic block; the partial
index this replaces was created by 0004.
"""
from django.db import migrations, models
from django.db.models import F


def normalise_legacy_voice_ids(apps, schema_editor):
    """Rewrite placeholder voice ids to the canonical language id."""
    AudioNarrationJob = apps.get_model('media_app', 'AudioNarrationJob')
    AudioNarrationJob.objects.filter(
        voice_id__in=('default', ''),
    ).update(voice_id=F('language'))


class Migration(migrations.Migration):

    dependencies = [
        ('media_app', '0006_videogenerationjob_provider_and_more'),
    ]

    operations = [
        migrations.RunPython(
            normalise_legacy_voice_ids,
            migrations.RunPython.noop,
            elidable=True,
        ),
        migrations.RemoveConstraint(
            model_name='audionarrationjob',
            name='uniq_completed_narration_per_target_language',
        ),
        migrations.AddConstraint(
            model_name='audionarrationjob',
            constraint=models.UniqueConstraint(
                condition=models.Q(('status', 'completed')),
                fields=('target_key', 'language', 'voice_id'),
                name='uniq_completed_narration_per_target_language_voice',
            ),
        ),
    ]
