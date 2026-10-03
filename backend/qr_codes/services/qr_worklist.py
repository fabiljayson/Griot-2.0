"""
The QR code worklist — which artifacts still have nothing to put on the wall.

A QR code is not a record. It is derived from an artifact's deep link and only
exists once someone generates it, which in practice means once a curator is
standing next to the object with a printer. So the useful question for a
moderator is not "what artifacts are there" but "which ones still have no code
to put on the wall", and that is what this is ordered by: the ones nobody has
generated for come first, because those are the ones doing nothing.

This module lives in `qr_codes` rather than in `web` because both surfaces read
it — the server-rendered dashboard (`web.services.admin_dashboard_data`) and the
mobile app (`ArtifactViewSet.qr_worklist`). When the rules lived only in `web`,
the app had no way to show the same list without a second, quietly diverging
copy of the ordering — the drift this project has already paid for twice
(`resolve_status`, `resolve_ui_language`).
"""

from django.db.models import Count

from ..models import Artifact
from .qr_generator import generate_artifact_qr

# Enough to work through in one sitting and to keep one POST bounded. 134
# artifacts is a plausible catalog; a national collection would not be, and the
# screen is a worklist rather than a bulk tool precisely because of that.
QR_WORKLIST_LIMIT = 50


def qr_worklist_data(limit: int = QR_WORKLIST_LIMIT):
    """Artifacts ordered by 'has no printable QR code yet'.

    Returns ``qr_artifacts``, ``qr_total``, ``qr_generated`` and
    ``qr_truncated``. The empty string sorts before any real SVG, so ordering on
    ``qr_code_svg`` puts the unlabelled objects at the top.
    """
    queryset = (
        Artifact.objects.all()
        .select_related('created_by')
        .annotate(scan_total=Count('scans'))
        .order_by('qr_code_svg', 'title')
    )
    artifacts = list(queryset[:limit])

    return {
        'qr_artifacts': artifacts,
        'qr_total': Artifact.objects.count(),
        'qr_generated': Artifact.objects.exclude(qr_code_svg='').count(),
        # Say so rather than implying the list is everything: a truncated
        # worklist that reads as complete is how a museum ends up with one
        # unlabeled object nobody notices is missing.
        'qr_truncated': queryset.count() > limit,
    }


def missing_slugs(limit: int = QR_WORKLIST_LIMIT):
    """Slugs of the artifacts with no code yet, bounded by [limit]."""
    return list(
        Artifact.objects.filter(qr_code_svg='')
        .order_by('title')
        .values_list('slug', flat=True)[:limit]
    )


def generate_qr_for_artifacts(slugs, *, persist: bool = True):
    """Generate QR codes for the named artifacts.

    Returns ``(generated, slugs_not_found)``. A slug that does not resolve is
    reported rather than raised: this is driven by a tick list, and a moderator
    who ticked a row that a concurrent edit deleted should be told which row,
    not handed a 404 for the whole batch.
    """
    found = list(
        Artifact.objects.filter(slug__in=list(slugs)).order_by('title')
    )
    generated = []
    for artifact in found:
        generate_artifact_qr(artifact, fmt='svg', persist=persist)
        generated.append(artifact)

    found_slugs = {artifact.slug for artifact in found}
    missing = [slug for slug in slugs if slug not in found_slugs]
    return generated, missing