<!-- SYNC IMPACT REPORT
Version change: (none — initial ratification) → 1.0.0
Modified principles: none (initial adoption)
Added sections:
  - Core Principles I–V (API/Web Parity, Security by Default, Test-First,
    Cultural Data Integrity, Observability)
  - Technology & Architecture Constraints
  - Development Workflow & Quality Gates
  - Governance
Removed sections: none (template placeholders replaced)
Follow-up TODOs: none
-->

# Griot 2.0 (African Teller) Constitution

## Core Principles

### I. API/Web/Flutter Parity

Every user-facing capability MUST exist in three aligned surfaces: the DRF
API (`/api/`), the server-rendered web UI (`web/` app), and the Flutter
mobile client contract. Web views MUST mirror the corresponding mobile
screens (naming, payloads, and flows), and shared behavior (view counting,
gamification, quiz scoring) MUST be implemented once in models/services and
reused — never duplicated per surface. A change to one surface that alters
shared behavior MUST be reflected in the others in the same change set.

### II. Security by Default

The split-settings layout (`config/settings/base.py` / `dev.py` / `test.py`
/ `prod.py`) is normative. Production MUST fail fast on missing or insecure
`DJANGO_SECRET_KEY` and `DJANGO_ALLOWED_HOSTS`; secrets MUST come only from
environment variables and MUST NOT be committed. Auth endpoints MUST remain
behind the strict `auth` throttle scope (5/min per IP); JWT access tokens
MUST stay short-lived (≤30 min) with refresh rotation and blacklisting.
Analytics and admin surfaces MUST enforce role checks
(`IsAdminOrManager`), and default DRF permissions MUST remain
`IsAuthenticatedOrReadOnly` or stricter. Development conveniences
(`DEBUG=True`, `CORS_ALLOW_ALL_ORIGINS`, `ALLOWED_HOSTS=['*']`) MUST be
confined to `dev.py`.

### III. Test-First Regression Coverage (NON-NEGOTIABLE)

Every bug fix and feature MUST land with tests that fail before the fix and
pass after. The suite (`DJANGO_SETTINGS_MODULE=config.settings.test python
manage.py test`) MUST pass with zero failures before any change is
considered complete; skipped tests MUST document why. Test settings MUST
stay isolated (new dicts, not in-place mutation of shared settings) so test
overrides can never leak into dev/prod.

### IV. Cultural Data Integrity

Heritage content is the product: stories, artifacts, and cultural metadata
(region, culture, language, provenance) MUST be preserved on import and
NEVER silently overwritten — import/update commands MUST be idempotent and
support `--dry-run` and explicit `--update-existing` confirmation. Models
MUST carry cultural metadata fields (category, region, culture, language)
and slugs MUST be stable, because QR codes and deep links encode them.
Deletion of cultural records MUST use `SET_NULL` or soft strategies that
retain provenance wherever the schema allows.

### V. Observability & Operational Honesty

All logs MUST be single-line structured JSON; request logging MUST go
through `api.middleware.RequestLogMiddleware`. Health endpoints (`/api/
health/`, `/api/health/ready/`, `/api/health/metrics/`) MUST remain
unauthenticated, expose only aggregate counts (never user data), and
readiness MUST return 503 on database failure. Any metrics labeled
process-local MUST be documented as per-worker so operators do not
misread them as cluster-wide.

## Technology & Architecture Constraints

- Stack is pinned in `requirements.txt`: Django 5.2, DRF 3.16, SimpleJWT,
  drf-spectacular, SQLite (dev) / PostgreSQL via `DATABASE_URL` (prod).
  Version bumps are deliberate changes, reviewed as such.
- Feature-first app layout (`users`, `stories`, `qr_codes`, `gamification`,
  `media_app`, `api`, `web`) MUST be preserved; cross-app imports go through
  models/services, not view internals.
- `artifacts` is deprecated and kept only for migration history; it MUST be
  removed only after a documented migration path exists.
- The custom user model (`users.User` with `UserRole`) is the only identity
  source; `is_staff`/`is_superuser` remain Django-admin flags and MUST NOT
  be conflated with application roles.
- OpenAPI schema (`drf-spectacular`) MUST stay accurate; new endpoints MUST
  appear in `/api/schema/` with correct permissions.

## Development Workflow & Quality Gates

- Every change MUST pass, in order: `manage.py check`,
  `manage.py makemigrations --check --dry-run` (no undocumented drift), and
  the full test suite under `config.settings.test`.
- Migrations MUST be committed together with the model changes that
  require them; squashing happens only at documented milestones.
- Seeding/import commands MUST remain idempotent, support `--dry-run`,
  and warn when using default demo credentials.
- Static assets are served locally (no CDNs); WhiteNoise must sit directly
  after `SecurityMiddleware`.
- The Flutter client and web UI share API contracts; breaking API changes
  require a version note in `SPECTACULAR_SETTINGS` and coordinated client
  updates.

## Governance

- This constitution supersedes ad-hoc practices; conflicts are resolved in
  favor of the constitution until formally amended.
- Amendments MUST be proposed in a change that updates this file with a
  version bump (MAJOR: principle removal/redefinition; MINOR: new principle
  or material expansion; PATCH: clarifications), a Sync Impact Report, and
  an updated Last Amended date.
- All reviews MUST verify: parity across surfaces (I), settings/security
  discipline (II), test coverage (III), data-integrity handling (IV), and
  observability (V). Complexity beyond these rules MUST be justified in the
  change description.

**Version**: 1.0.0 | **Ratified**: 2026-09-19 | **Last Amended**: 2026-09-19
