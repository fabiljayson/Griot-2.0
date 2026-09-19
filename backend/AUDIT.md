# Project Audit — 2026-09-19

Full audit of the Griot 2.0 backend performed 2026-09-19 (Codebuff session).
Baseline: Django 5.2.4 / DRF 3.16 / Python 3.14, 141 tests.

## Checks performed

| Check | Result |
|---|---|
| `manage.py check` | 0 issues |
| `makemigrations --check --dry-run` | No migration drift |
| Test suite (`config.settings.test`) | 141 tests, 1 failure → fixed (see below), now OK |
| Hardcoded secrets scan | None found (env-var discipline holds) |
| SQL injection (`raw`/`extra`) / TLS (`verify=False`) | None found |
| `.gitignore` coverage | `db.sqlite3`, `server.log`, `staticfiles/` all ignored |
| Settings security | prod fail-fast on insecure key/hosts; auth throttle 5/min; JWT rotation+blacklist; analytics role-gated; health endpoints aggregate-only |

## Bug found & fixed

**`web/views.py::story_detail_view`** — the quiz lookup was nested inside the
`request.user.is_authenticated` block, so anonymous visitors never saw the
"Sign in to take quiz" card on story pages (breaking mobile parity and failing
`web.tests.QuizzesHubTests.test_story_shows_quiz_to_anonymous_visitors`).
Fix: hoist the quiz lookup above the auth branch. Suite is green.

## Findings & disposition

1. **Deprecated `artifacts` app still mounted** (duplicate QR landing page,
   empty models, README drift) → resolved by feature
   `specs/001-retire-artifacts-app` (runtime retirement + 301 redirect for
   printed QR codes; migration history preserved on disk).
2. **`dev.py` `ALLOWED_HOSTS` contained `'*'`** (host-header permissiveness)
   → resolved by feature 001: wildcard removed; test settings scoped to
   `testserver`/localhost/loopback; prod untouched (env-sourced).
3. **`test_quiz_api.py` at repo root** — standalone smoke script (guarded by
   `__main__`, safely import-discovered). OPEN (low priority): consider moving
   under an app or `scripts/` for consistency.
4. **No submission-approval workflow** — stories can be submitted for review,
   but no product path approves/rejects them (spec'd as feature
   `specs/002-story-submission-moderation`).

## Governance

The audit's security and testing observations are codified in the project
constitution (`.specify/memory/constitution.md`, v1.0.0): API/Web/Flutter
parity, security by default, test-first regression coverage, cultural data
integrity, observability.
