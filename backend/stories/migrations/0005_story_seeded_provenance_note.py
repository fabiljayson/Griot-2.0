from django.db import migrations

# Duplicated from `stories.management.commands.seed_stories.SEEDED_PROVENANCE_NOTE`
# rather than imported: a migration must not depend on application code that can
# change underneath it later.
SEEDED_PROVENANCE_NOTE = (
    'Demonstration content seeded from crawled pages of '
    'discover-cameroon.com for this project. Not recorded from a community '
    'member, and no community consent was sought for this text.'
)


def backfill_seeded_provenance(apps, schema_editor):
    """Fill the empty provenance on rows the seeder labelled `seeded`.

    All 12 seeded stories carried `origin='seeded'` with `provenance_notes`
    empty, so the model said the *category* and nothing else: not where the
    text came from, and not that no community consent was ever sought for it.

    Scoped to `origin='seeded' AND provenance_notes=''` so a row a moderator
    has since documented, or one imported from a real collection, is never
    touched. Idempotent — re-running it matches nothing.
    """
    Story = apps.get_model('stories', 'Story')
    Story.objects.filter(origin='seeded', provenance_notes='').update(
        provenance_notes=SEEDED_PROVENANCE_NOTE,
    )


class Migration(migrations.Migration):

    dependencies = [
        (
            'stories',
            '0004_story_consent_attested_at_story_consent_attested_by_and_more',
        ),
    ]

    operations = [
        migrations.RunPython(backfill_seeded_provenance, migrations.RunPython.noop),
    ]
