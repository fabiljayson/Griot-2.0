"""Case-insensitive uniqueness on `auth_user.email`.

Every email lookup in this codebase uses `email__iexact`, but the column had no
uniqueness guarantee at all — `RegisterSerializer.validate_email` was a
check-then-act guard, so two concurrent registrations could both pass it and
insert two rows for the same address, permanently stranding that email.

This migration resolves any pre-existing duplicates and then adds a
case-insensitive unique constraint. Blank emails are exempt because the column
is `blank=True`.
"""

import django.db.models.functions.text
from django.db import migrations, models
from django.db.models import F

# Login is by username (the JWT serializer is fed `username`), so clearing a
# duplicate's email does not lock that account out of signing in.
_DUPLICATE_EMAIL = ''


def resolve_duplicate_emails(apps, schema_editor):
    """Keep the earliest account per address; clear the email on the rest.

    Runs before the constraint is added, so the migration cannot fail on data
    that already violates it. Existing duplicates are artefacts of the retried
    registration bug, so the earliest row is the real account.
    """
    User = apps.get_model('users', 'User')
    db_alias = schema_editor.connection.alias

    seen = set()
    duplicates = []
    # Oldest first: date_joined, then pk, so the choice is deterministic.
    rows = (
        User.objects.using(db_alias)
        .exclude(email='')
        .order_by('date_joined', 'pk')
        .values_list('pk', 'email')
    )
    for pk, email in rows:
        key = email.strip().lower()
        if key in seen:
            duplicates.append(pk)
        else:
            seen.add(key)

    if duplicates:
        User.objects.using(db_alias).filter(pk__in=duplicates).update(
            email=_DUPLICATE_EMAIL
        )


def restore_duplicate_emails(apps, schema_editor):
    """No-op: the original addresses are not recoverable.

    Reversing drops the constraint only. Re-adding it later would fail if the
    cleared rows were given an address again, which is the correct signal that
    the duplicate needs a human decision rather than a silent restore.
    """


class Migration(migrations.Migration):

    dependencies = [
        ('auth', '0012_alter_user_first_name_max_length'),
        ('users', '0001_initial'),
    ]

    operations = [
        migrations.RunPython(resolve_duplicate_emails, restore_duplicate_emails),
        migrations.AddConstraint(
            model_name='user',
            constraint=models.UniqueConstraint(
                django.db.models.functions.text.Lower('email'),
                condition=models.Q(('email', ''), _negated=True),
                name='uniq_user_email_case_insensitive',
            ),
        ),
    ]
