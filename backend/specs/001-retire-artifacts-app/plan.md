# Implementation Plan: Retire Deprecated Artifacts App & Scope Dev Hosts

**Branch**: `001-retire-artifacts-app` | **Date**: 2026-09-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-retire-artifacts-app/spec.md`

## Summary

Retire the deprecated `artifacts` Django app from the runtime (unregister it,
remove its duplicate QR landing route, relocate its import command to the
canonical `qr_codes` app, and update docs) while preserving compatibility for
legacy printed QR codes via a permanent 301 redirect from `/artifacts/<slug>/`
to `/artifact/<slug>/`. Additionally scope the development host allow-list
(remove the `'*'` wildcard), leaving production host sourcing untouched.
No data model changes; no API contract changes.

## Technical Context

**Language/Version**: Python 3.14 (venv at `.venv-linux`), Django 5.2.4

**Primary Dependencies**: Django 5.2, Django REST Framework 3.16, SimpleJWT, drf-spectacular

**Storage**: SQLite (dev/test); PostgreSQL via DATABASE_URL (prod) — no schema changes in this feature

**Testing**: Django test runner (`manage.py test`) with `config.settings.test`; 141 existing tests, all green

**Target Platform**: Linux server (Render), local dev on Linux/macOS/Windows

**Project Type**: Web service + server-rendered web UI (Django monolith)

**Performance Goals**: Redirect adds ≤1 DB query (slug lookup only when resolving target); landing page performance unchanged

**Constraints**: Zero downtime URL compatibility for printed QR codes; no destructive migration cleanup; test suite must stay green

**Scale/Scope**: 2 settings files touched, 1 URL config touched, 1 management command moved, ~4 new tests, README updated

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. API/Web/Flutter Parity | ✅ PASS | Redirect preserves web deep-link behavior; mobile uses API routes (`/api/artifacts/`), unaffected. Duplicate landing page removal *improves* parity (one canonical surface). |
| II. Security by Default | ✅ PASS | Dev `ALLOWED_HOSTS` wildcard removal is a direct strengthening; prod sourcing (env-only) unchanged. |
| III. Test-First Regression Coverage | ✅ PASS | Plan requires new tests (redirect, host allow-list, command availability) before removal lands; suite must stay green. |
| IV. Cultural Data Integrity | ✅ PASS | No data deletion; historical migrations preserved (FR-008); import command keeps idempotent/dry-run behavior — relocated verbatim. |
| V. Observability & Operational Honesty | ✅ PASS | Health endpoints, middleware, logging untouched; README truthfulness restored. |

**Post-design re-check**: ✅ PASS — design introduces no new complexity; all removals reduce surface area.

## Project Structure

### Documentation (this feature)

```text
specs/001-retire-artifacts-app/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── urls.md          # URL contract: legacy → canonical redirect mapping
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
config/
├── settings/
│   ├── base.py          # (untouched) INSTALLED_APPS shared baseline
│   ├── dev.py           # EDIT: remove '*' from ALLOWED_HOSTS
│   ├── test.py          # EDIT: scope ALLOWED_HOSTS for testserver + localhost
│   └── prod.py          # (untouched) env-sourced hosts stay
├── tests/               # NEW: config-level test package (discovered from repo root)
│   ├── __init__.py
│   ├── test_settings.py # NEW: dev/test ALLOWED_HOSTS scoping tests
│   └── test_urls.py     # NEW: legacy → canonical redirect tests
├── urls.py              # EDIT: replace artifacts include with redirect view
├── qr_codes/            # Canonical artifact app
│   ├── management/commands/
│   │   └── import_crawl_data.py   # NEW: relocated from artifacts (verbatim)
│   ├── urls.py          # (untouched — API routes unchanged)
│   ├── views.py         # (untouched)
│   └── tests.py         # EDIT: + redirect tests
├── web/
│   ├── urls.py          # (untouched — canonical /artifact/<slug>/ stays)
│   └── views.py         # (untouched)
├── artifacts/           # RETIRED at runtime → migration-history shell:
│   ├── __init__.py      # KEPT (package marker)
│   ├── models.py        # KEPT (already empty — historical record)
│   ├── migrations/      # KEPT on disk (FR-008) — migration graph history
│   ├── README.md        # NEW: deprecation note pointing to qr_codes
│   ├── admin.py         # REMOVED (already empty stub)
│   ├── apps.py          # REMOVED (unregistered app config)
│   ├── views.py         # REMOVED (legacy landing page)
│   ├── urls.py          # REMOVED (legacy route)
│   └── management/      # REMOVED after command relocation
├── templates/artifacts/ # REMOVED (legacy landing template; only renderer was
│                        # the removed view)
└── test_quiz_api.py     # (untouched) standalone smoke script
└── README.md            # EDIT: remove artifacts app from structure; document
                         # canonical command owner + legacy redirect note
```

**Structure Decision**: Single Django monolith layout is retained. The
migration history in `artifacts/migrations/` stays on disk (it is part of
the migration graph and referenced by deployed databases' migration
records), while the app's runtime surface (INSTALLED_APPS registration,
URL routes, views, management commands) is removed or relocated. The
`import_crawl_data` command moves to `qr_codes/management/commands/` so
its documented invocation (`python manage.py import_crawl_data`) is
unchanged from the operator's perspective.

## Complexity Tracking

> No constitution violations — table intentionally left empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
