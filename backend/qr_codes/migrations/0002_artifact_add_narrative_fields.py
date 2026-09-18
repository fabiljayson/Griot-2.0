"""
Add narrative fields to qr_codes.Artifact, consolidating from the
deprecated artifacts app into a single Artifact model.

Fields migrated from artifacts.Artifact:
  - story (TextField): Narrative description
  - historical_significance (TextField): Cultural background
  - source_url (URLField): Original source
  - audio_file (FileField): Audio narration
  - video_url_field (URLField): Video URL
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('qr_codes', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='artifact',
            name='story',
            field=models.TextField(
                blank=True,
                default='',
                help_text="Narrative description of the artifact's cultural significance.",
            ),
        ),
        migrations.AddField(
            model_name='artifact',
            name='historical_significance',
            field=models.TextField(
                blank=True,
                default='',
                help_text='Cultural background or legend details.',
            ),
        ),
        migrations.AddField(
            model_name='artifact',
            name='source_url',
            field=models.URLField(
                blank=True,
                default='',
                help_text='Original source URL of the content.',
            ),
        ),
        migrations.AddField(
            model_name='artifact',
            name='audio_file',
            field=models.FileField(
                blank=True,
                null=True,
                upload_to='audio/',
                help_text='Optional audio narration file.',
            ),
        ),
        migrations.AddField(
            model_name='artifact',
            name='video_url_field',
            field=models.URLField(
                blank=True,
                null=True,
                help_text='Optional YouTube/Vimeo video URL.',
            ),
        ),
    ]
