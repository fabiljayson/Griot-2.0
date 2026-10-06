"""VR session lifecycle: start, record progress, complete.

Progress is recorded on `VRSession` and XP is handed to the existing
`gamification` profile rather than to a VR-specific counter. A second XP system
would produce two "levels" for one reader, and the leaderboard would silently
have to pick one.
"""

from django.conf import settings
from django.db import connection, transaction
from django.utils import timezone

from gamification.models import UserProfile

from ..models import VRSession
from .experiences import published_placements


class InvalidCompletionStatus(Exception):
    """Caller sent a status the model does not define."""

    code = 'invalid_completion_status'


class InvalidSessionArtifacts(Exception):
    """One or more artifact ids are not part of this session's experience."""

    code = 'invalid_artifacts'


def session_xp_reward() -> int:
    return int(getattr(settings, 'VR_SESSION_XP_COMPLETE', 25))


def start_session(*, user, experience, launch_token=None, device_model='') -> VRSession:
    """Open a new session row."""
    return VRSession.objects.create(
        user=user,
        experience=experience,
        launch_token=launch_token,
        device_model=device_model[:120],
    )


def find_active_session(*, user, experience):
    """The reader's open session for `experience`, if there is one.

    Used by `POST /api/vr/sessions/` so a headset that reconnects after losing
    the app does not create a second session and a second XP award for one visit.
    """
    return (
        VRSession.objects.filter(
            user=user,
            experience=experience,
            completion_status=VRSession.Status.ACTIVE,
        )
        .order_by('-start_time')
        .first()
    )


def validate_artifact_ids(experience, artifact_ids) -> list[int]:
    """Return the ids, or raise if any is outside this experience.

    A client could otherwise claim to have viewed arbitrary artifacts and inflate
    its own progress — or, worse, get XP for a museum it never entered. Only
    published placements of this experience count.
    """
    if not artifact_ids:
        return []

    try:
        requested = {int(value) for value in artifact_ids}
    except (TypeError, ValueError) as exc:
        raise InvalidSessionArtifacts('Artifact ids must be whole numbers.') from exc

    allowed = set(published_placements(experience).values_list('artifact_id', flat=True))
    unknown = requested - allowed
    if unknown:
        raise InvalidSessionArtifacts(
            'These artifacts are not part of this experience: '
            f'{", ".join(str(value) for value in sorted(unknown))}.'
        )

    return sorted(requested)


def complete_session(
    *,
    session,
    completion_status,
    progress=None,
    duration_seconds=None,
    artifact_ids=None,
) -> tuple[VRSession, int]:
    """Close `session`, returning `(session, xp_awarded_now)`.

    Idempotent with respect to XP: the award is a conditional
    `UPDATE ... WHERE xp_awarded = 0`, so a retried or duplicated completion
    (Unity retrying on a flaky link is the normal case, not the exception)
    cannot pay twice. `xp_awarded_now` is what *this* call paid, which is what
    the response should report.
    """
    valid_statuses = dict(VRSession.Status.choices)
    if completion_status not in valid_statuses:
        raise InvalidCompletionStatus(
            f'Unknown completion status. Expected one of: '
            f'{", ".join(valid_statuses)}.'
        )

    validated_ids = validate_artifact_ids(session.experience, artifact_ids)
    reward = (
        session_xp_reward()
        if completion_status == VRSession.Status.COMPLETED
        else 0
    )
    xp_awarded_now = 0

    with transaction.atomic():
        queryset = VRSession.objects.filter(pk=session.pk)
        if connection.features.has_select_for_update:
            queryset = queryset.select_for_update()
        row = queryset.get()

        now = timezone.now()
        row.completion_status = completion_status
        row.end_time = now

        if progress is not None:
            row.progress = min(1.0, max(0.0, float(progress)))

        if duration_seconds is not None:
            row.duration_seconds = max(0, int(duration_seconds))
        elif not row.duration_seconds:
            # Unity crashed or the link dropped: fall back to wall-clock time so
            # the analyst is not staring at a zero-minute session.
            row.duration_seconds = max(
                0, int((now - row.start_time).total_seconds())
            )

        update_fields = [
            'completion_status',
            'end_time',
            'progress',
            'duration_seconds',
            'updated_at',
        ]

        if reward:
            claimed = VRSession.objects.filter(
                pk=row.pk, xp_awarded=0,
            ).update(xp_awarded=reward)
            if claimed:
                xp_awarded_now = reward
                row.xp_awarded = reward
                profile, _ = UserProfile.objects.get_or_create(user=row.user)
                profile.add_xp(reward)

        row.save(update_fields=update_fields)

        if validated_ids:
            row.artifacts_viewed.set(validated_ids)

    return row, xp_awarded_now
