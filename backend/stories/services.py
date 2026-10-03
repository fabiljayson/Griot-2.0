"""Shared story rules — the one place both surfaces ask the same question.

Constitution I: shared behaviour is implemented once in models/services and
reused, never duplicated per surface. Before this module existed, the status a
contributor may set was decided inside `web.services.save_story` and nowhere at
all in the API, where `status` was read-only — so the web form could submit a
story for review while the Flutter client, sending `status: 'pending'` from the
identical button, had the value silently dropped and the story stayed a draft.
The UI reported success for an action the server never performed.

Nothing here knows about HTTP: no request, no serializer, no surface. Callers
pass a user and a story.
"""

from django.core.exceptions import PermissionDenied, ValidationError
from django.utils import timezone

from .models import Story

#: Roles that may author a story.
CONTRIBUTOR_ROLES = ('contributor', 'institution_manager', 'admin')
#: Roles that may moderate one: record consent, approve, reject.
MODERATOR_ROLES = ('institution_manager', 'admin')

#: The only statuses a non-moderator may ever set. `pending` is what "submit
#: for review" means; `published`, `rejected` and `archived` are the
#: moderator's to give, and handing them to the author would make the review
#: queue decorative.
CONTRIBUTOR_SETTABLE_STATUS = (Story.Status.DRAFT, Story.Status.PENDING)


def is_contributor(user):
    """Whether `user` may author a story. Mirrors `IsContributorOrAbove`."""
    return bool(user) and user.is_authenticated and user.role in CONTRIBUTOR_ROLES


def is_moderator(user):
    """Whether `user` may moderate one."""
    return bool(user) and user.is_authenticated and user.role in MODERATOR_ROLES


def apply_contributor_status(requested):
    """The status a *contributor* is allowed to set.

    Unrecognised or moderator-only values fall back to draft rather than
    raising: a client sending an odd status must not cost someone their text.
    """
    if requested in CONTRIBUTOR_SETTABLE_STATUS:
        return requested
    return Story.Status.DRAFT


def resolve_status(user, requested):
    """The status `user` may actually set, applied for both surfaces.

    This is the check that stops an author publishing their own story past the
    review queue. It lives here rather than in a serializer or a view because
    there are two of each and they had already drifted once.
    """
    if requested is None:
        return None
    if is_moderator(user):
        return requested
    return apply_contributor_status(requested)


def request_consent(user, story):
    """A contributor records that they have *asked*: `not_requested` → `pending`.

    Recording the community's **answer** is deliberately not here — see
    `record_consent`. The distinction is the whole reason `consent_status` is
    read-only to contributors: a contributor declaring their own community's
    agreement is the claim this field exists to keep trustworthy.

    Idempotent: asking twice, or asking after the answer is in, changes
    nothing.
    """
    if not is_contributor(user):
        raise PermissionDenied('Contributor role or above required.')
    if story.author_id != user.id and not is_moderator(user):
        raise PermissionDenied('You can only act on your own stories.')

    if story.consent_status != Story.Consent.NOT_REQUESTED:
        return story

    story.consent_status = Story.Consent.PENDING
    story.save(update_fields=['consent_status', 'updated_at'])
    return story


#: The consent states in which a moderator still owes a decision.
#:
#: `not_requested` is in here deliberately. The contributor may not have asked
#: anyone yet, but a moderator who obtained an answer out of band still has to
#: record it, and a queue that hid those rows would leave that nowhere to
#: record it from.
CONSENT_AWAITING_DECISION = (Story.Consent.NOT_REQUESTED, Story.Consent.PENDING)


def consent_review_queue():
    """The stories a moderator still owes a consent decision on.

    One definition, because "which stories are waiting" is a rule rather than a
    view: the API queue and a moderator screen both ask it, and a second copy
    would be a second thing to keep correct.

    `granted`, `granted_restricted` and `withheld` are decisions already
    recorded, so they stay out — changing one is a correction made on the story
    itself, not a pending queue item.
    """
    return (
        Story.objects.filter(consent_status__in=CONSENT_AWAITING_DECISION)
        .select_related('author', 'consent_attested_by')
        .order_by('-created_at')
    )


def record_consent(user, story, *, status, basis='', rights_holder=None,
                   licence=None):
    """A moderator records the community's answer, attributable and dated.

    Sets `consent_status` alongside `consent_attested_by`, `consent_attested_at`
    and `consent_basis`, because a status with no name and no date behind it
    cannot answer "says who" — which is the only question that matters if it is
    ever challenged.

    **Withdrawing consent on a published story archives it.** The model already
    refuses to save that combination, so raising would mean consent could not be
    withdrawn at all; silently leaving it published is the one outcome the app
    must never produce. The record is kept, not deleted (Constitution IV).
    """
    if not is_moderator(user):
        raise PermissionDenied('Moderator role required.')

    valid = {choice for choice, _ in Story.Consent.choices}
    if status not in valid:
        raise ValidationError({'consent_status': f'Unknown consent status: {status}!r'})
    if not basis.strip():
        raise ValidationError({'consent_basis': (
            'Record the basis for this decision — a consent status with no '
            'basis behind it cannot be defended later.'
        )})

    story.consent_status = status
    story.consent_attested_by = user
    story.consent_attested_at = timezone.now()
    story.consent_basis = basis.strip()
    if rights_holder is not None:
        story.rights_holder = rights_holder
    if licence is not None:
        story.licence = licence

    archived = False
    if status == Story.Consent.WITHHELD and story.status == Story.Status.PUBLISHED:
        story.status = Story.Status.ARCHIVED
        story.reviewer_notes = (
            (story.reviewer_notes + '\n' if story.reviewer_notes else '')
            + f'Consent withdrawn by {user.username} — archived automatically.'
        ).strip()
        archived = True

    story.save()
    return story, archived
