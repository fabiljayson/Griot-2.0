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
from django.db.models import Q
from django.utils import timezone

from . import trust as trust_score
from .models import ModerationLog, Story, StorySource, StoryVerification

#: Roles that may author a story.
CONTRIBUTOR_ROLES = ('contributor', 'institution_manager', 'admin')
#: Roles that may moderate one: record consent, approve, reject.
MODERATOR_ROLES = ('institution_manager', 'admin')

#: The only statuses a non-moderator may ever set. `pending` is what "submit
#: for review" means; `published`, `rejected` and `archived` are the
#: moderator's to give, and handing them to the author would make the review
#: queue decorative.
CONTRIBUTOR_SETTABLE_STATUS = (Story.Status.DRAFT, Story.Status.PENDING)

#: The statuses a moderator still owes a decision on — the verification queue.
VERIFICATION_QUEUE_STATUSES = (
    Story.Status.PENDING,
    Story.Status.UNDER_REVIEW,
    Story.Status.NEEDS_REVISION,
)


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


#: The consent states that are actually an answer from the community.
#:
#: `not_requested` and `pending` are the absence of an answer, so letting a
#: moderator record one of them as a "decision" would let them file a basis and
#: an attestation against a story nobody answered about — and leave the story in
#: the queue, so the next moderator sees a decision that is not one. `granted`,
#: `granted_restricted` and `withheld` are the three answers.
#:
#: One definition, because both consent forms (API and web) ask the same
#: question and a second copy would be a second thing to keep correct.
CONSENT_DECISIONS = (
    Story.Consent.GRANTED,
    Story.Consent.GRANTED_RESTRICTED,
    Story.Consent.WITHHELD,
)


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

    # `Story.Consent.choices` is the wrong set to validate against here: it also
    # holds the two states that mean nobody has answered yet.
    if status not in CONSENT_DECISIONS:
        raise ValidationError({'consent_status': (
            f'{status!r} is not a consent decision. Record granted, granted '
            'with restrictions, or withheld.'
        )})
    if not basis.strip():
        raise ValidationError({'consent_basis': (
            'Record the basis for this decision — a consent status with no '
            'basis behind it cannot be defended later.'
        )})

    before = story.status
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
    log_moderation(
        user, story, ModerationLog.Action.CONSENT_RECORDED,
        notes=f'Consent {status} — {story.consent_basis}',
        from_status=before, to_status=story.status,
    )
    return story, archived


# ---------------------------------------------------------------------------
# Visibility (one definition for every surface)
# ---------------------------------------------------------------------------
def visible_stories(user):
    """The stories `user` may see, as a queryset.

    Anonymous and visitors: published only. Contributors: published plus
    their own (whatever the review state). Moderators: everything — a queue
    that cannot show the item it queues is not a queue.
    """
    queryset = Story.objects.select_related('author').prefetch_related(
        'categories', 'sources', 'verification',
    )
    if user is None or not user.is_authenticated:
        return queryset.filter(status=Story.Status.PUBLISHED)
    if user.role in MODERATOR_ROLES:
        return queryset
    if user.role == 'contributor':
        return queryset.filter(
            Q(status=Story.Status.PUBLISHED) | Q(author=user),
        )
    return queryset.filter(status=Story.Status.PUBLISHED)


# ---------------------------------------------------------------------------
# Audit trail
# ---------------------------------------------------------------------------
#: Which log action a landing status represents, for transitions recorded
#: outside `verify_story` (an author submitting, a moderator PATCHing
#: `status` directly on either surface).
STATUS_ACTION = {
    Story.Status.PENDING: ModerationLog.Action.SUBMITTED,
    Story.Status.UNDER_REVIEW: ModerationLog.Action.REVIEW_STARTED,
    Story.Status.PUBLISHED: ModerationLog.Action.APPROVED,
    Story.Status.REJECTED: ModerationLog.Action.REJECTED,
    Story.Status.NEEDS_REVISION: ModerationLog.Action.CHANGES_REQUESTED,
    Story.Status.ARCHIVED: ModerationLog.Action.ARCHIVED,
}


def log_moderation(user, story, action, *, notes='', from_status='', to_status=''):
    """Append one audit-trail row. Never raises: the trail must not be able
    to fail the moderation action it is recording."""
    try:
        return ModerationLog.objects.create(
            story=story,
            actor=user if (user is not None and user.is_authenticated) else None,
            action=action,
            from_status=from_status or '',
            to_status=to_status or '',
            notes=notes or '',
        )
    except Exception:  # pragma: no cover - audit writes never break the action
        return None


def log_status_change(user, story, from_status, to_status, notes=''):
    """Record a status transition made outside `verify_story`.

    Idempotent by transition: staying put logs nothing, so a PATCH that does
    not move the story adds no noise.
    """
    if not to_status or from_status == to_status:
        return None
    action = STATUS_ACTION.get(to_status)
    if action is None:
        return None
    return log_moderation(
        user, story, action, notes=notes,
        from_status=from_status, to_status=to_status,
    )


# ---------------------------------------------------------------------------
# Verification queue & decisions
# ---------------------------------------------------------------------------
def verification_queue():
    """Stories awaiting a verification decision, richest row first."""
    return (
        Story.objects.filter(status__in=VERIFICATION_QUEUE_STATUSES)
        .select_related('author', 'verification', 'verification__reviewer')
        .prefetch_related('sources', 'categories')
        .order_by('-created_at')
    )


def get_verification(story) -> StoryVerification:
    """The story's evidence row, creating the empty one on first review."""
    verification, _ = StoryVerification.objects.get_or_create(story=story)
    return verification


def refresh_trust_score(story, *, evidence=None, reviewer=None) -> StoryVerification:
    """Recompute and cache the score from the evidence, optionally applying
    `evidence` first.

    The score is always derived — a hand-edited number would be the one
    thing on the page nobody could reproduce from the criteria below it.
    """
    verification = get_verification(story)
    if evidence:
        apply_evidence(verification, evidence)
    verification.trust_score = trust_score.calculate_trust_score(verification)
    if reviewer is not None:
        verification.reviewer = reviewer
    verification.save()
    return verification


def apply_evidence(verification: StoryVerification, evidence: dict):
    """Copy recognised criteria from a payload onto the row.

    Unknown keys are ignored rather than rejected: a client that still sends
    a retired criterion must not lose the review over it.
    """
    if not isinstance(evidence, dict):
        return
    changed = False
    for criterion in trust_score.CRITERIA:
        if criterion in evidence:
            setattr(verification, criterion, bool(evidence[criterion]))
            changed = True
    if changed:
        verification.verified_at = timezone.now()


#: The verification decisions a moderator may record, and the status each
#: one lands the story in. The log action mirrors the decision so the audit
#: trail reads as the reviewer's intent, not just the destination status.
VERIFY_ACTIONS = {
    'start_review': (Story.Status.UNDER_REVIEW, ModerationLog.Action.REVIEW_STARTED),
    'approve': (Story.Status.PUBLISHED, ModerationLog.Action.APPROVED),
    'reject': (Story.Status.REJECTED, ModerationLog.Action.REJECTED),
    'request_changes': (Story.Status.NEEDS_REVISION, ModerationLog.Action.CHANGES_REQUESTED),
}


def verify_story(user, story, *, action, notes='', evidence=None):
    """A moderator records a verification decision, with evidence.

    Returns `(story, verification)`. Applies any evidence criteria first so
    the trust score shown next to "Approved" is the score the approval was
    based on. Approving a story whose community withheld consent raises —
    `Story.save` refuses that combination, and rightly.
    """
    if not is_moderator(user):
        raise PermissionDenied('Moderator role required.')
    if action not in VERIFY_ACTIONS:
        raise ValidationError({'action': (
            f'{action!r} is not a verification action. Record start_review, '
            'approve, reject, or request_changes.'
        )})

    new_status, log_action = VERIFY_ACTIONS[action]
    from_status = story.status

    verification = refresh_trust_score(
        story, evidence=evidence, reviewer=user,
    )

    story.status = new_status
    if notes and notes.strip():
        story.reviewer_notes = (
            (story.reviewer_notes + '\n' if story.reviewer_notes else '')
            + f'{user.username}: {notes.strip()}'
        ).strip()
    if new_status == Story.Status.PUBLISHED and not story.published_at:
        story.published_at = timezone.now()
    # `Story.save` raises when consent was withheld — surfaced to the view,
    # which maps it to a 400.
    story.save()

    log_moderation(
        user, story, log_action, notes=(notes or '').strip(),
        from_status=from_status, to_status=new_status,
    )
    return story, verification


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------
def add_source(user, story, *, source_type, name, **extra) -> StorySource:
    """Attach a source to a story. Author or moderator only.

    Sources are evidence, so they cannot be appended to a story by a
    bystander — but the author must be able to document their own text
    while it is still in review, which is why ownership is enough here.
    """
    if not is_contributor(user):
        raise PermissionDenied('Contributor role or above required.')
    if story.author_id != user.id and not is_moderator(user):
        raise PermissionDenied('You can only add sources to your own stories.')
    if source_type not in StorySource.SourceType.values:
        raise ValidationError({'source_type': (
            f'{source_type!r} is not a recognised source type.'
        )})
    if not (name or '').strip():
        raise ValidationError({'name': 'A source needs a name.'})
    return StorySource.objects.create(
        story=story, source_type=source_type, name=name.strip(), **extra,
    )


def verify_source(user, source, *, is_verified=True) -> StorySource:
    """A moderator confirms or withdraws a source check."""
    if not is_moderator(user):
        raise PermissionDenied('Moderator role required.')
    source.is_verified = bool(is_verified)
    source.verified_by = user
    source.verified_at = timezone.now()
    source.save()
    # A verified source is the first trust criterion; the score follows the
    # evidence rather than the other way round.
    refresh_trust_score(
        source.story,
        evidence={'source_verified': source.story.sources.filter(is_verified=True).exists()},
        reviewer=user,
    )
    log_moderation(
        user, source.story,
        ModerationLog.Action.SOURCE_VERIFIED if is_verified else ModerationLog.Action.EVIDENCE_UPDATED,
        notes=f'Source "{source.name}" marked {"verified" if is_verified else "unverified"}.',
        to_status=source.story.status,
    )
    return source
