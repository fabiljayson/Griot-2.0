# Phase 0 Research: Retire Deprecated Artifacts App & Scope Dev Hosts

**Feature**: 001-retire-artifacts-app | **Date**: 2026-09-19

## R1: How does the deprecated `artifacts` app differ from canonical `qr_codes`?

**Decision**: Retire the `artifacts` app from the runtime entirely; keep only
a migration-history shell.

**Rationale**: Code inspection (audit phase) established:

- `artifacts/models.py` is an empty shell — its `Artifact` model was removed
  in migration `0003_remove_artifact_model` and consolidated into
  `qr_codes.Artifact` (with narrative fields merged via `qr_codes/0002`).
- `artifacts/admin.py` is an empty stub ("intentionally left empty").
- The only view (`artifacts/views.py::artifact_detail`) renders
  `templates/artifacts/detail.html` — a *duplicate, feature-poor* landing
  page competing with `web.views.artifact_detail_view` (which adds scan
  recording, audio narration, related stories, blurhash support).
- No code anywhere references the `artifacts:detail` route name or imports
  `artifacts.models` (verified by search).
- QR codes encode `SITE_URL + /artifact/<slug>/` (the canonical web route)
  via `Artifact.qr_deep_link` — printed codes do NOT use the legacy path.

**Alternatives considered**:

- *Keep both routes serving the same page* — rejected: duplicate surfaces
  violate Constitution I (parity via one canonical implementation) and
  create drift risk (already true: legacy page lacks scan recording).
- *Hard-remove the whole `artifacts/` directory* — rejected for this
  feature: migration files are part of the migration graph and are
  referenced by the `django_migrations` bookkeeping rows of any deployed
  database; removal requires a documented data-migration milestone
  (FR-008 defers this).

## R2: What happens to `import_crawl_data`?

**Decision**: Move the command verbatim to
`qr_codes/management/commands/import_crawl_data.py`.

**Rationale**: Django discovers management commands from *registered* apps'
`management/commands/` directories. Once `artifacts` is unregistered, the
command would vanish. The command's own code already imports
`qr_codes.Artifact` (per its docstring), so relocation is behavior-neutral.
Documented operator invocation (`python manage.py import_crawl_data`,
including `--dry-run` / `--update-existing`) is unchanged (FR-004).

**Alternatives considered**:

- *Leave command in place and keep app registered* — rejected: defeats the
  retirement goal.
- *Rewrite the command during the move* — rejected: relocation must be
  behavior-neutral and reviewable as a pure move; rewrites belong in a
  separate change.

## R3: How should the legacy URL behave after retirement?

**Decision**: `config/urls.py` serves a permanent redirect:
`/artifacts/<slug>/` → `/artifact/<slug>/` (301), preserving query
strings where possible.

**Rationale**: Printed museum QR codes are long-lived physical assets;
some may encode the legacy path from the pre-consolidation era. A 301
preserves SEO equity and lets CDN/browser caches amortize the hop
(SC-001: single redirect hop). RedirectView with `permanent=True` is a
stdlib-class Django primitive — no custom logic required.

**Alternatives considered**:

- *410 Gone* — rejected: breaks every legacy printed code still in
  circulation; no user benefit.
- *Keep serving the legacy view* — rejected: keeps the duplicate surface
  alive.
- *302 temporary* — rejected: signals impermanence; search engines and
  caches treat it as non-authoritative.

## R4: Which hosts should dev/test allow-list?

**Decision**: dev: `localhost`, `127.0.0.1`, `.ngrok-free.app`,
`.ngrok.io` (team tunneling provider per existing config). test: add
`testserver` (required by Django's test client). Wildcard `'*'` removed.

**Rationale**: The existing dev config already lists the ngrok domains
explicitly alongside the wildcard — the wildcard adds nothing except
host-header permissiveness (dns-rebinding class exposure, and masks
misconfiguration by silently serving any Host). Django rejects unknown
Host headers with 400 Bad Request by default (SC-003: 3 patterns for
dev + tunneling wildcards = 4 entries total counting both ngrok
domains).

**Alternatives considered**:

- *Environment-variable-driven dev hosts* — rejected: dev settings are
  committed conveniences; env-driven host lists are the production
  pattern (which already exists in `prod.py`).
- *Keep `'*'` behind a flag* — rejected: YAGNI; a developer needing a
  different tunnel host can edit dev.py locally.

## R5: Does removing the app require a migration?

**Decision**: No migrations are created or deleted in this feature.

**Rationale**: `artifacts` has no models (since its `0003` migration).
Unregistering an app that has zero models and zero undeleted migrations
creates no migration state. The existing migrations stay on disk
(FR-008). `manage.py makemigrations --check` must report no changes
after the change (a quality gate already in the constitution).

## R6: What about `templates/artifacts/detail.html`?

**Decision**: Delete the template along with the view that renders it.

**Rationale**: It has exactly one renderer (`artifacts.views.
artifact_detail`), which is being removed. Retaining an unreachable
template contradicts the audit goal (dead surface). The web UI's
canonical artifact templates live under `templates/web/`.

## R7: Test placement conventions

**Decision**: New tests go in `config/tests/` (new package) for
settings/URL-level tests; app-level behavior tests extend existing
`qr_codes/tests.py` if needed.

**Rationale**: `config/` is a plain package (not an installed Django app),
but Django's test runner discovers `tests` packages/modules from the
working directory recursively. The project already uses `web/tests.py`
and `qr_codes/tests.py` conventions; a `config/tests/` package for
settings-level assertions (importing both settings modules) is the
cleanest fit without inventing a new app.

**Alternatives considered**:

- *A dedicated `core` app for tests* — rejected: inventing an installed
  app solely for tests adds registry noise; contradicts the retirement
  spirit.
- *Tests inside `config/settings/`* — rejected: settings modules are
  imported by the runner; test modules there would be confusing.

## R8: Is the Flutter client affected?

**Decision**: No client changes required.

**Rationale**: The mobile app consumes `/api/artifacts/...` (qr_codes
ViewSet routes), which are untouched. Deep-link handling on mobile
resolves `/artifact/<slug>/` paths via the lookup endpoint; the legacy
web path was never part of the mobile contract.
