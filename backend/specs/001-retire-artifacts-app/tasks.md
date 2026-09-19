---
description: "Task list for retiring the deprecated artifacts app and scoping dev ALLOWED_HOSTS"
---

# Tasks: Retire Deprecated Artifacts App & Scope Dev Hosts

**Input**: Design documents from `/specs/001-retire-artifacts-app/`

**Prerequisites**: plan.md ✅ | spec.md ✅ | research.md ✅ | data-model.md ✅ | contracts/urls.md ✅ | quickstart.md ✅

**Tests**: Included — required by spec FR-009 and Constitution III (Test-First, NON-NEGOTIABLE). Each story's tests are written FIRST and must FAIL before the implementation task lands.

**Organization**: Tasks grouped by user story (US1 = redirect & retirement, US2 = host scoping, US3 = documentation).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Path Conventions

Single Django monolith at repo root: `config/` (settings/urls/tests), `qr_codes/` (canonical artifact app), `artifacts/` (retired shell), `templates/`, `README.md`.

---

## Phase 1: Setup (Baseline Verification)

**Purpose**: Establish the pre-change baseline so regressions are attributable.

- [X] T001 Record pre-change baseline: run `manage.py check` (expect 0 issues), `manage.py makemigrations --check --dry-run` (expect "No changes detected"), and the full suite with `DJANGO_SETTINGS_MODULE=config.settings.test manage.py test` (expect "OK", 141 tests, 2 skipped). No file changes in this task.

**Checkpoint**: Baseline green — implementation may begin.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Command relocation MUST precede app unregistration (US1/T007) — Django discovers management commands only from *registered* apps, so moving `import_crawl_data` first guarantees the documented command never disappears (contracts/urls.md C4).

- [X] T002 [P] Create test package marker `config/tests/__init__.py` (empty file) so `config/tests/` is importable by the Django test runner
- [X] T003 Relocate the import command verbatim: create `qr_codes/management/__init__.py` and `qr_codes/management/commands/__init__.py` (if absent), copy `artifacts/management/commands/import_crawl_data.py` to `qr_codes/management/commands/import_crawl_data.py` unchanged, then verify `python manage.py import_crawl_data --dry-run` still runs (command is now discoverable from either app until T008 removes the old copy)

**Checkpoint**: Command available from canonical app — US1 retirement can proceed safely.

---

## Phase 3: User Story 1 — Legacy QR Codes Land on the Canonical Page (Priority: P1) 🎯 MVP

**Goal**: `/artifacts/<slug>/` permanently redirects to `/artifact/<slug>/`; the deprecated app is unregistered and its duplicate landing surface removed; printed QR codes keep working with one 301 hop.

**Independent Test**: Request `/artifacts/<slug>/` → expect 301 with `Location: /artifact/<slug>/`; request `/artifact/<slug>/` for a published artifact → expect 200; `'artifacts' not in settings.INSTALLED_APPS`; `python manage.py import_crawl_data --dry-run` still resolves.

### Tests for User Story 1 (write FIRST — must FAIL) ⚠️

- [X] T004 [P] [US1] Create `config/tests/test_urls.py` with failing tests: (a) GET `/artifacts/any-slug/` returns 301 with Location `/artifact/any-slug/` (slug-agnostic — no DB object needed, per contracts/urls.md C1); (b) GET `/artifacts/<existing-published-slug>/` redirects and following it yields 200; (c) GET `/artifact/<existing-published-slug>/` yields 200 (canonical preserved, C2). Run and confirm all FAIL (current behavior: legacy route serves duplicate 200 page)
- [X] T005 [P] [US1] Add failing test to `config/tests/test_settings.py`: `assert 'artifacts' not in settings.INSTALLED_APPS` under dev settings (FAILS today) plus guard that `artifacts/migrations/` still exists on disk (passes — pins FR-008)

### Implementation for User Story 1

- [X] T006 [US1] Replace the artifacts include in `config/urls.py`: swap `path('artifacts/', include('artifacts.urls'))` for a `RedirectView`-based permanent redirect mapping `artifacts/<slug:slug>/` → `/artifact/<slug:slug>/` (301, `permanent=True`) — depends on T004
- [X] T007 [US1] Remove `'artifacts'` from `LOCAL_APPS` in `config/settings/base.py` (leaving a trailing-comment note that migration history remains on disk) — depends on T003, T005, T006
- [X] T008 [US1] Delete retired runtime files: `artifacts/views.py`, `artifacts/urls.py`, `artifacts/admin.py`, `artifacts/apps.py`, `artifacts/management/` tree, and `templates/artifacts/` — KEEP `artifacts/__init__.py`, `artifacts/models.py` (empty shell), and `artifacts/migrations/` (FR-008) — depends on T007
- [X] T009 [US1] Run the full test suite: T004/T005 tests now PASS, all 141 baseline tests still pass, zero regressions — depends on T008

**Checkpoint**: US1 complete — legacy QR codes redirect, canonical page intact, app unregistered, command still discoverable. Independently demonstrable.

---

## Phase 4: User Story 2 — Dev Server Rejects Unknown Hosts (Priority: P2)

**Goal**: Development host allow-list scoped to real dev hosts (wildcard removed); test settings explicit; production untouched.

**Independent Test**: Import `config.settings.dev` → `'*' not in ALLOWED_HOSTS` and the four expected patterns present; import `config.settings.test` → `testserver` present; `config.settings.prod` unchanged (env-sourced).

### Tests for User Story 2 (write FIRST — must FAIL) ⚠️

- [X] T010 [P] [US2] Add failing settings tests to `config/tests/test_settings.py`: (a) dev `ALLOWED_HOSTS` contains exactly `localhost`, `127.0.0.1`, `.ngrok-free.app`, `.ngrok.io` and NOT `'*'`; (b) test settings include `testserver`, `localhost`, `127.0.0.1`; (c) prod module source untouched — assert via reading `config/settings/prod.py` that host sourcing still comes from `DJANGO_ALLOWED_HOSTS`/`RENDER_EXTERNAL_HOSTNAME` (C5). Run and confirm dev assertion FAILS (wildcard present today)

### Implementation for User Story 2

- [X] T011 [US2] Edit `config/settings/dev.py`: remove `'*'` from `ALLOWED_HOSTS` (keep the four legitimate dev/tunnel hosts) — depends on T010
- [X] T012 [P] [US2] Edit `config/settings/test.py`: set explicit `ALLOWED_HOSTS = ['testserver', 'localhost', '127.0.0.1']` — depends on T010
- [X] T013 [US2] Run settings tests then the full suite under `config.settings.test` — all PASS with zero regressions — depends on T011, T012

**Checkpoint**: US2 complete — dev/test hosts scoped, prod untouched. Independent of US1 outcome.

---

## Phase 5: User Story 3 — Documentation Names One Canonical Home (Priority: P3)

**Goal**: README describes a single canonical artifact app and command owner; retired app carries a deprecation note.

**Independent Test**: Read `README.md` — no `artifacts` app in the structure listing, import command documented under `qr_codes/`; `artifacts/README.md` exists and points to `qr_codes`.

### Implementation for User Story 3

- [X] T014 [P] [US3] Update `README.md`: remove the `artifacts/` line from the project-structure tree; annotate `qr_codes/` as the canonical artifact + QR engine including `import_crawl_data`; add a short "Legacy URLs" note documenting the `/artifacts/<slug>/` → `/artifact/<slug>/` 301 redirect for printed QR codes (SC-005: single canonical reference)
- [X] T015 [P] [US3] Create `artifacts/README.md`: deprecation note explaining the directory is a migration-history shell only (models removed in `0003`), canonical code lives in `qr_codes/`, files under `migrations/` must NOT be deleted while deployed databases reference them (FR-008)

**Checkpoint**: US3 complete — documentation ambiguity eliminated.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T016 Execute `specs/001-retire-artifacts-app/quickstart.md` end-to-end (all 6 sections) and record results
- [X] T017 Constitution compliance re-check against `.specify/memory/constitution.md` principles I–V (parity, security, test-first, data integrity, observability) and confirm `specs/001-retire-artifacts-app/checklists/requirements.md` still passes
- [X] T018 Final quality gate: `manage.py check` (0 issues) + `manage.py makemigrations --check --dry-run` (no changes) + full suite green under `config.settings.test` — matches or exceeds the T001 baseline

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none — run first
- **Foundational (Phase 2)**: depends on T001; T003 BLOCKS T007 (app unregister must not orphan the command)
- **US1 (Phase 3)**: depends on Phase 2
- **US2 (Phase 4)**: depends only on T002 (test package marker) — independent of US1, can run in parallel
- **US3 (Phase 5)**: depends on T008 (docs must describe the post-retirement state)
- **Polish (Phase 6)**: depends on all stories complete

### User Story Dependencies

- **US1 (P1)**: Phase 2 → T004/T005 (red tests) → T006 → T007 → T008 → T009 (green)
- **US2 (P2)**: T010 (red) → T011, T012 → T013 (green). No coupling to US1 files
- **US3 (P3)**: after T008; T014 and T015 are mutually parallel

### Parallel Opportunities

- T002, T003 can start together after T001
- T004 and T005 are parallel (different files, both red)
- US2 (T010–T013) can proceed in parallel with US1 (T004–T009) after Phase 2
- T014 and T015 are parallel
- Single-developer sequential path: T001 → T002 → T003 → T004 → T005 → T006 → T007 → T008 → T009 → T010 → T011 → T012 → T013 → T014 → T015 → T016 → T017 → T018

---

## Parallel Example: After Foundational

```text
Developer A (US1):  T004 → T006 → T007 → T008 → T009
Developer B (US2):  T010 → T011 + T012 → T013
Both converge on:   Phase 5 (T014, T015) → Phase 6
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 + Phase 2 (baseline + command relocation)
2. Phase 3 (US1: redirect + retirement) → **STOP and VALIDATE** via T009
3. This alone delivers the audit's P1 finding (duplicate landing surface eliminated, QR compatibility preserved)

### Incremental Delivery

- US1 → user-facing URL contract fixed (MVP)
- US2 → hardening layer (independent, low risk)
- US3 → documentation truth restored
- Phase 6 → full quickstart + constitution gate before merge

## Notes

- Tests are mandatory (FR-009 + Constitution III): red before green, per story
- No migrations may be created or deleted (research.md R5); `makemigrations --check` must stay clean
- Keep `artifacts/migrations/` intact — deletion is a separate, documented milestone
- Commit after each task or logical group
