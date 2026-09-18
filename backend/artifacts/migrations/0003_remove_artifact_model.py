"""
Drop the deprecated artifacts.Artifact table.

All artifact data is now served by qr_codes.Artifact, which has been
extended with the narrative fields (story, historical_significance,
source_url, audio_file, video_url_field) from this model.
"""

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('artifacts', '0002_artifact_category_artifact_historical_significance_and_more'),
    ]

    operations = [
        migrations.DeleteModel(
            name='Artifact',
        ),
    ]
