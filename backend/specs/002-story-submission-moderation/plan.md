# Implementation Plan: Story Submission & Moderation Workflow

**Branch**: `002-story-submission-moderation` | **Date**: 2026-09-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-story-submission-moderation/spec.md`

## Summary

Complete the story review lifecycle: authors submit drafts for review
(draft/rejected → pending), moderators decide from a dedicated review queue
(pending → published with publication date, or pending → rejected with a
required written reason), authors see their story's state and rejection
reason and can revise + resubmit. Every decision is recorded as an immutable
audit row (who, what, why, when). Logic is implemented once in a shared
service layer (`stories/services.py`) consumed by both the REST API (mobile
parity) and the web UI, per Constitution I.

## Technical Context

**Language/Version**: Python 3.14 (`.venv-linux`), Django 5.2.4, DRF 3.16

**Primary Dependencies**: Django REST Framework, SimpleJWT, drf-spectacular (schema must stay accurate — Constitution constraint)

**Storage**: SQLite dev / Postgres prod — **one new table** (`story_moderation_decision`), one migration

**Testing**: Django test runner under `config.settings.test`; baseline 154 tests OK

**Target Platform**: Linux server (Render), consumed by Flutter app + web UI

**Project Type**: Django monolith (DRF API + server-rendered web)

**Performance Goals**: Review queue = one paginated query (default page size 20); decisions complete in <100 ms at platform scale (hundreds of stories)

**Constraints**: No new roles or states; existing fields reused where possible; engagement data untouched; all state changes auditable

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. API/Web/Flutter Parity | ✅ PASS | Single service layer drives both surfaces; new endpoints appear in OpenAPI schema; web mirrors mobile flows. Closes an existing parity gap (API could not submit stories for review). |
| II. Security by Default | ✅ PASS | New endpoints role-gated (`IsAdminOrManager` semantics); rejection reason visibility enforced server-side; self-moderation conflict rule enforced in the shared service, not per-surface. |
| III. Test-First Regression Coverage | ✅ PASS | Every acceptance scenario maps to a red→green test; suite must stay green; new model ships with migration committed together. |
| IV. Cultural Data Integrity | ✅ PASS | Rejection never destroys content; resubmission preserves engagement data and decision history (append-only); slugs untouched. |
| V. Observability & Operational Honesty | ✅ PASS | Decisions logged through existing JSON logging; audit rows give operators ground truth on who approved what. |

**Post-design re-check**: ✅ PASS — one new model + service module; no architectural additions beyond the plan.

## Project Structure

### Documentation (this feature)

```text
specs/002-story-submission-moderation/
├── plan.md              # This file
├── research.md          # Phase 0 decisions
├── data-model.md        # ModerationDecision entity + state machine
├── quickstart.md        # End-to-end validation scenarios
├── contracts/
│   └── api.md           # API + web route contracts
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
stories/
├── models.py            # EDIT: + ModerationDecision model
├── services.py          # NEW: submit_story / approve_story / reject_story (shared logic)
├── serializers.py       # EDIT: + ReviewQueueSerializer, rejection_reason visibility field
├── views.py             # EDIT: + review_queue / submit / approve / reject actions
├── admin.py             # EDIT: register ModerationDecision (read-only-ish)
├── migrations/00XX_*.py # NEW: ModerationDecision
└── tests.py             # EDIT: API tests (queue, approve, reject, submit, visibility)

web/
├── views.py             # EDIT: + review_queue_view (moderator page)
├── actions.py           # EDIT: + review_approve / review_reject actions
├── urls.py              # EDIT: + review queue + action routes
└── tests.py             # EDIT: web tests (queue page, approve/reject, denial)

templates/web/
├── review_queue.html    # NEW: moderator review queue page
└── story_detail.html    # EDIT: author-facing status/rejection-reason panel

README.md                # EDIT: document review workflow routes
```

**Structure Decision**: Feature-first layout preserved. The workflow state
machine lives in `stories/services.py` (Constitution I: shared behavior
implemented once); API actions and web actions are thin wrappers. No new
app is created.

## Complexity Tracking

> No constitution violations — table intentionally left empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
