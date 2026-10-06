"""Lookup rules for VR experiences.

Every rule about *which* experience a launch may open lives here, so the launch
endpoint, the Flutter client and the admin surface cannot disagree about it.
"""

from django.db.models import Prefetch
from django.shortcuts import get_object_or_404

from stories.models import Story

from ..models import VRExperience, VRExperienceArtifact


class NoVRExperience(Exception):
    """No active experience contains the requested artifact."""

    code = 'no_vr_experience'


class AmbiguousVRExperience(Exception):
    """Several active experiences contain the artifact; the caller must pick."""

    code = 'experience_ambiguous'


def active_experiences():
    """Experiences a reader may be launched into, newest first."""
    return VRExperience.objects.filter(is_active=True)


def published_placements(experience):
    """Placements of `experience` whose artifact is published.

    Draft artifacts are excluded even from an active experience: a scene that
    references an unpublished object would otherwise publish it by side effect,
    bypassing the review workflow that `is_published` represents.
    """
    return (
        VRExperienceArtifact.objects.filter(
            experience=experience,
            artifact__is_published=True,
        )
        .select_related('artifact', 'narration')
        .prefetch_related(
            Prefetch(
                'artifact__stories',
                queryset=Story.objects.filter(
                    status=Story.Status.PUBLISHED,
                ).only('id', 'slug', 'title', 'language'),
            ),
        )
        .order_by('order', 'id')
    )


def active_experiences_for_artifact(artifact):
    """Active experiences that place `artifact`, oldest first for stability."""
    return (
        active_experiences()
        .filter(placements__artifact=artifact)
        .distinct()
        .order_by('id')
    )


def find_experience_by_key(key):
    """Resolve an `id` or a `slug` to an active experience, or None.

    Both forms are accepted because two clients need them: the Flutter app only
    ever knows a slug, while Unity, after the exchange, works from numeric ids
    it read out of the payload.
    """
    if key is None or str(key).strip() == '':
        return None

    key = str(key).strip()
    if key.isdigit():
        return active_experiences().filter(pk=int(key)).first()
    return active_experiences().filter(slug=key).first()


def resolve_launch_experience(*, experience_key=None, artifact=None):
    """Work out which experience a launch request means.

    Order of intent: an explicit experience wins; otherwise the artifact decides,
    and only when it is unambiguous. Requiring the caller to disambiguate is the
    honest answer to "this mask is in two galleries" — picking one silently would
    drop the reader somewhere they did not choose.
    """
    if experience_key:
        experience = find_experience_by_key(experience_key)
        if experience is None:
            raise NoVRExperience('That experience is not available.')
        if artifact is not None and not VRExperienceArtifact.objects.filter(
            experience=experience, artifact=artifact
        ).exists():
            raise NoVRExperience('That artifact is not part of this experience.')
        return experience

    if artifact is None:
        raise NoVRExperience('A VR launch needs an experience or an artifact.')

    candidates = list(active_experiences_for_artifact(artifact)[:2])
    if not candidates:
        raise NoVRExperience('This artifact is not available in VR yet.')
    if len(candidates) > 1:
        raise AmbiguousVRExperience(
            'This artifact appears in more than one VR experience.'
        )
    return candidates[0]


def get_experience_or_404(key):
    """Read-path lookup: active experience by id or slug, 404 otherwise."""
    key = str(key).strip()
    if key.isdigit():
        return get_object_or_404(active_experiences(), pk=int(key))
    return get_object_or_404(active_experiences(), slug=key)
