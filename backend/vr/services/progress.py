"""Read and record VR exploration progress.

Two directions live here:

* `progress_entries` rolls the reader's sessions up into one row per
  experience, which is what the "Progress: 65%" line in Flutter and Unity
  renders. It is a rollup rather than a raw session list because a reader who
  visited a gallery four times wants one answer to "how far did I get", not
  four.
* `record_progress` writes a partial update while a session is still open.
  XP is deliberately *not* awarded here — the only payout in this app is
  `complete_session`'s conditional update, and a second award path would make
  idempotency impossible to reason about.
"""

from django.shortcuts import get_object_or_404

from ..models import VRSession
from .experience_payload import experience_summary
from .sessions import validate_artifact_ids


class SessionNotActive(Exception):
    """Progress was posted against a session that is already closed."""

    code = 'session_not_active'


def progress_entries(*, user, experience_key=None) -> list[dict]:
    """One entry per experience the reader has a session for, newest first.

    `experience_key` accepts an id or a slug. It deliberately does *not* filter
    to active experiences: a gallery a curator has since closed still has
    progress the reader earned, and hiding it would read as data loss.
    """
    sessions = VRSession.objects.filter(user=user).select_related('experience')

    if experience_key is not None and str(experience_key).strip() != '':
        key = str(experience_key).strip()
        if key.isdigit():
            sessions = sessions.filter(experience_id=int(key))
        else:
            sessions = sessions.filter(experience__slug=key)

    entries: dict[int, dict] = {}
    for session in sessions.order_by('-start_time'):
        entry = entries.get(session.experience_id)
        if entry is None:
            entries[session.experience_id] = {
                'experience': experience_summary(session.experience),
                'session_count': 1,
                'completed': session.completion_status == VRSession.Status.COMPLETED,
                'completion_percentage': _percentage(session),
                'last_seen_at': session.start_time,
            }
            continue

        entry['session_count'] += 1
        entry['completed'] = entry['completed'] or (
            session.completion_status == VRSession.Status.COMPLETED
        )
        entry['completion_percentage'] = max(
            entry['completion_percentage'], _percentage(session),
        )
        # `-start_time` ordering means the first row seen is the newest, so
        # `last_seen_at` is already correct and later rows must not move it.

    return list(entries.values())


def _percentage(session: VRSession) -> int:
    if session.completion_status == VRSession.Status.COMPLETED:
        return 100
    return int(round(min(1.0, max(0.0, session.progress)) * 100))


def record_progress(*, session, progress=None, artifact_ids=None) -> VRSession:
    """Apply a partial progress update to an open session.

    `artifact_ids` is treated as the reader's complete viewed list (it replaces,
    not appends) because a headset that lost connectivity replays its last
    known state rather than a diff. Passing `None` leaves the set alone.
    """
    if not session.is_active:
        raise SessionNotActive(
            'This session is already finished. Start a new one to keep exploring.'
        )

    validated_ids = (
        validate_artifact_ids(session.experience, artifact_ids)
        if artifact_ids is not None
        else None
    )

    update_fields = ['updated_at']
    if progress is not None:
        session.progress = min(1.0, max(0.0, float(progress)))
        update_fields.append('progress')
    session.save(update_fields=update_fields)

    if validated_ids is not None:
        session.artifacts_viewed.set(validated_ids)

    return session


def session_for_token(user, sid):
    """The session a VR token is bound to, scoped to its owner.

    Filtered by owner so someone else's session is a 404 rather than a 403 that
    confirms the row exists — the same rule the complete endpoint follows.
    """
    return get_object_or_404(VRSession, pk=sid, user=user)
