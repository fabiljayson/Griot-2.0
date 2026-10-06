"""Contract test: every API path the Flutter client calls must resolve.

The Flutter app builds request paths as string literals (sometimes via
`static const` base paths and `$slug` interpolation). DRF's `@action`
derives its URL from the method name, so a rename on either side silently
produces 404s that unit tests miss — both suites mock/`reverse()` their way
around the mismatch. This test closes that gap by walking the Dart sources
and resolving every `/api/...` path against the real URL table.

If this fails after a change, either the client path or the server route
moved: fix the drift, do not weaken the test.
"""

from __future__ import annotations

import re
from pathlib import Path

from django.test import SimpleTestCase
from django.urls import Resolver404, resolve

FRONTEND_LIB = Path(__file__).resolve().parents[3] / 'frontend' / 'lib'

# Single-quoted strings starting with /api/, e.g. '/api/stories/my/'.
_LITERAL = re.compile(r"'(/api/[^'\n]*)'")
# Interpolated paths, e.g. '$_basePath/artifacts/$slug/'.
_INTERPOLATED = re.compile(r"'(\$[_A-Za-z][_A-Za-z0-9]*/[^'\n]*)'")
# Base-path constants, e.g. static const _basePath = '/api/stories';
# The optional type annotation matters: `static const String _basePath = ...`
# is the common form, and without matching it the constant is never substituted
# and `$_basePath/launch/` resolves as the literal 'test-slug/launch/'.
_CONST = re.compile(r"static const\s+(?:\w+\s+)?(_\w+)\s*=\s*'(/api[^']*)'")
# $slug / ${slug} style placeholders become a generic slug segment.
_PLACEHOLDER = re.compile(r"\$\{?\w+\}?")

# Substring checks in interceptors, not request paths.
_NON_ENDPOINT_PREFIXES = {'/api/auth/'}


def _client_paths() -> list[tuple[Path, int, str]]:
    """Extract concrete request paths from the Dart sources."""
    collected: list[tuple[Path, int, str]] = []
    for dart_file in sorted(FRONTEND_LIB.rglob('*.dart')):
        text = dart_file.read_text(encoding='utf-8')
        consts = dict(_CONST.findall(text))
        for lineno, line in enumerate(text.splitlines(), start=1):
            matches = list(_LITERAL.finditer(line)) + list(
                _INTERPOLATED.finditer(line)
            )
            for match in matches:
                path = match.group(1)
                if '$' in path:
                    for name, base in consts.items():
                        path = path.replace(f'${name}', base)
                    path = _PLACEHOLDER.sub('test-slug', path)
                collected.append((dart_file, lineno, path))
    return collected


class ClientPathContractTests(SimpleTestCase):
    """Every `/api/...` path in frontend/lib must resolve."""

    def test_frontend_lib_exists(self):
        assert FRONTEND_LIB.is_dir(), (
            f'frontend/lib not found at {FRONTEND_LIB}; the contract test '
            'needs the Flutter sources in the repo layout it expects.'
        )

    def test_every_client_api_path_resolves(self):
        paths = _client_paths()
        assert paths, 'no /api/ paths found in frontend/lib — extractor broken?'

        unresolved: list[str] = []
        checked = 0
        for dart_file, lineno, path in paths:
            if not path.endswith('/'):
                continue  # base path without a route, e.g. '/api/stories'
            if path in _NON_ENDPOINT_PREFIXES:
                continue
            checked += 1
            try:
                resolve(path)
            except Resolver404:
                rel = dart_file.relative_to(FRONTEND_LIB.parent.parent)
                unresolved.append(f'{rel}:{lineno}  {path}')

        assert checked > 50, f'only {checked} paths checked — extractor broken?'
        assert not unresolved, (
            'Flutter calls API paths that do not resolve on the server:\n  '
            + '\n  '.join(unresolved)
        )

    def test_known_renamed_routes_resolve(self):
        # Pinned after the hyphen/underscore 404s (admin moderation+consent).
        for path in (
            '/api/stories/moderation_queue/',
            '/api/stories/consent_queue/',
            '/api/stories/test-slug/record_consent/',
            '/api/stories/test-slug/request_consent/',
        ):
            assert resolve(path).url_name, path
