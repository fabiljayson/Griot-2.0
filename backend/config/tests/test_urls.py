"""
URL-level tests for the deprecated-artifacts retirement (feature 001).

Contract under test (specs/001-retire-artifacts-app/contracts/urls.md):

- C1: GET /artifacts/<slug>/  → 301 permanent redirect to /artifact/<slug>/
  (slug-agnostic; printed QR codes with the legacy path keep working).
- C2: GET /artifact/<slug>/   → canonical detail page stays intact
  (200 for published artifacts).
"""

from django.test import Client, TestCase

from qr_codes.models import Artifact


class LegacyArtifactRedirectTests(TestCase):
    """US1: legacy /artifacts/<slug>/ must 301 to /artifact/<slug>/."""

    def test_legacy_url_redirects_permanently(self):
        """C1: slug-agnostic 301 — no DB object required."""
        response = Client().get('/artifacts/any-slug/')
        self.assertEqual(response.status_code, 301)
        self.assertEqual(response['Location'], '/artifact/any-slug/')

    def test_legacy_redirect_target_resolves_for_published_artifact(self):
        """C1→C2: following the redirect lands on the canonical page."""
        Artifact.objects.create(
            title='Legacy Redirect Check',
            slug='legacy-redirect-check',
            description='Temporary artifact for redirect test.',
            is_published=True,
        )
        response = Client().get('/artifacts/legacy-redirect-check/', follow=True)
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Legacy Redirect Check')

    def test_canonical_detail_page_still_works(self):
        """C2: the canonical route is untouched by the retirement."""
        Artifact.objects.create(
            title='Canonical Check',
            slug='canonical-check',
            description='Temporary artifact for canonical route test.',
            is_published=True,
        )
        response = Client().get('/artifact/canonical-check/')
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, 'Canonical Check')

    def test_canonical_detail_404_for_unknown_slug(self):
        """C2: canonical route keeps its own 404 semantics."""
        response = Client().get('/artifact/does-not-exist/')
        self.assertEqual(response.status_code, 404)
