"""
The §13 review state machine, in one place.

The admin actions and the API endpoints both call these functions rather than
setting fields themselves, so the workflow is enforced identically no matter
which door a reviewer came through.

    imported ──approve──▶ published on Story/Artifact
        │
        ├──reject────────▶ REJECTED
        └──correct───────▶ NEEDS_CORRECTION

Everything upstream of `imported` (discovered, fetched, extracted, normalized)
is the pipeline's business and is unreachable from here. That directionality is
the point: a reviewer can accept, reject or send back, but cannot use this
module to move content *backwards* into an unreviewed state without going
through `unpublish`, which is deliberately explicit.
"""

from __future__ import annotations

from django.db import transaction


class ReviewError(Exception):
    """Raised when a review transition is not allowed from the current state."""


def _needs_review(item) -> bool:
    """An item is reviewable once the pipeline has produced content for it."""
    return item.processing_status == item.ProcessingStatus.IMPORTED


@transaction.atomic
def approve_item(item, *, reviewer=None) -> None:
    """Approve a crawled item and make what it produced publicly visible.

    §13 puts `APPROVED -> PUBLISHED` as a separate arrow, and this function
    takes both steps together: in this project the two are the same act. A
    `Story` is `pending` or nothing, and `Artifact.is_published` is a boolean,
    so "approved but still invisible" has nowhere to live. What the spec's
    separation actually buys — a distinct audit moment before publication — is
    preserved instead by the fact that this function is never called by the
    pipeline, only by a person.

    Refuses when:

    * the item produced nothing to approve, or
    * the imported content has no recorded original URL.

    The second is the important one. §5 requires every imported item to be
    traceable to its source; approving heritage text that cannot be traced
    would break that guarantee at the exact moment it becomes public, which is
    the worst possible time to discover it.
    """
    if not _needs_review(item):
        raise ReviewError(
            f'item {item.pk} is {item.get_processing_status_display()}, '
            'not awaiting review'
        )

    if item.story_id:
        target = item.story
        target.status = target.Status.PUBLISHED
        target.reviewer_notes = _note(item, reviewer, 'approved and published')
        target.save(update_fields=['status', 'reviewer_notes', 'updated_at'])
    elif item.artifact_id:
        target = item.artifact
        target.is_published = True
        target.save(update_fields=['is_published'])
    else:
        raise ReviewError(
            f'item {item.pk} produced no content, so there is nothing to approve'
        )

    if not item.references.exists():
        raise ReviewError(
            f'item {item.pk} has no provenance record; refusing to publish '
            'content that cannot be traced to its source'
        )

    item.processing_status = item.ProcessingStatus.APPROVED
    item.save(update_fields=['processing_status', 'updated_at'])


def reject(item, *, reviewer=None, reason: str = '') -> bool:
    """Reject an item. Keeps the audit trail (§13 "reject" is not "remove")."""
    if not _needs_review(item) and (
        item.processing_status != item.ProcessingStatus.NEEDS_CORRECTION
    ):
        return False

    if item.story_id:
        item.story.status = item.story.Status.REJECTED
        item.story.reviewer_notes = _note(
            item, reviewer, f'rejected: {reason}' if reason else 'rejected'
        )
        item.story.save(update_fields=['status', 'reviewer_notes', 'updated_at'])
    elif item.artifact_id:
        item.artifact.is_published = False
        item.artifact.save(update_fields=['is_published'])

    item.processing_status = item.ProcessingStatus.REJECTED
    item.save(update_fields=['processing_status', 'updated_at'])
    return True


def request_correction(item, *, reviewer=None, reason: str = '') -> bool:
    """Send an item back for correction, leaving it unpublished."""
    if not _needs_review(item):
        return False

    if item.story_id:
        item.story.status = item.story.Status.DRAFT
        item.story.reviewer_notes = _note(
            item, reviewer,
            f'correction requested: {reason}' if reason else 'correction requested',
        )
        item.story.save(update_fields=['status', 'reviewer_notes', 'updated_at'])

    item.processing_status = item.ProcessingStatus.NEEDS_CORRECTION
    item.save(update_fields=['processing_status', 'updated_at'])
    return True


def unpublish(item, *, reviewer=None, reason: str = '') -> bool:
    """Withdraw already-approved content from public view.

    Exists because `CrawledItem` outlives publication: an administrator who
    later discovers a rights problem, or a cultural group who ask for something
    to come down, needs a path that leaves the provenance record intact.
    """
    if item.processing_status != item.ProcessingStatus.APPROVED:
        return False

    if item.story_id:
        item.story.status = item.story.Status.ARCHIVED
        item.story.reviewer_notes = _note(
            item, reviewer,
            f'unpublished: {reason}' if reason else 'unpublished',
        )
        item.story.save(update_fields=['status', 'reviewer_notes', 'updated_at'])
    elif item.artifact_id:
        item.artifact.is_published = False
        item.artifact.save(update_fields=['is_published'])

    item.processing_status = item.ProcessingStatus.IMPORTED
    item.save(update_fields=['processing_status', 'updated_at'])
    return True


def _note(item, reviewer, action: str) -> str:
    """One line of audit text, written into the Story's own reviewer field."""
    from django.utils import timezone

    who = getattr(reviewer, 'username', None) or 'system'
    stamp = timezone.now().strftime('%Y-%m-%d %H:%M')
    return f'[{stamp}] {who} {action} crawl item {item.pk} ({item.original_url})'
