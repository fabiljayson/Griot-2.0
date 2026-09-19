# Phase 0 Research: Story Submission & Moderation Workflow

**Feature**: 002-story-submission-moderation | **Date**: 2026-09-19

## R1: Where should the workflow state machine live?

**Decision**: New `stories/services.py` with three functions —
`submit_story(story, actor)`, `approve_story(story, actor)`,
`reject_story(story, actor, reason)` — each returning the updated story and
raising typed errors for illegal transitions.

**Rationale**: Constitution I requires shared behavior implemented once.
Today the web form and API independently assign `status`; the moderation
decision rules (self-approval ban, reason requirement, audit row) must not
be duplicated across surfaces. A service module keeps `views/actions` thin
and makes the transition rules unit-testable without HTTP.

**Alternatives considered**:
- *Model methods on `Story`* — viable, but a services module can import and
  coordinate `ModerationDecision` creation atomically without bloating the
  model; also matches the existing `media_app/services/` convention.
- *Signals* — rejected: hidden control flow, harder to test and audit.

## R2: Reuse `reviewer_notes` or add a dedicated rejection-reason field?

**Decision**: Reuse `Story.reviewer_notes` as the canonical rejection-reason
storage. Do **not** add a column to `Story`.

**Rationale**: `reviewer_notes` ("Internal notes from the reviewer") exists,
is already written by flag moderation, and is currently exposed **nowhere** —
so visibility rules can be introduced cleanly: author + moderators only.
The decision history (rounds of rejection) lives in the new
`ModerationDecision` table, so the active reason display can safely be
cleared on resubmission without losing history (FR-007, edge case).

**Alternatives considered**:
- *New `rejection_reason` column* — rejected: duplicates semantics of an
  existing field; drift risk between two "why" fields.
- *Reason only in decision rows, never on the story* — rejected: would make
  author-facing display require a join on every read; the active reason is
  genuinely a story-level attribute.

## R3: How is the audit trail modeled?

**Decision**: New model `stories.ModerationDecision`:
`story` (FK, related_name=`moderation_decisions`), `moderator` (FK
`SET_NULL` nullable), `decision` (choices: `approved`/`rejected`), `reason`
(text, required for rejections, blank for approvals), `created_at`
(auto_now_add, indexed with story). Rows are **append-only**: no update/delete
in any product path; admin may view but the change form is limited.

**Rationale**: FR-012/SC-005 require attributable state changes; spec's edge
case "rejection reason cleared on resubmission" requires history to survive
somewhere. A dedicated table with append-only semantics is the minimal
auditable design and gives `published_at` a human cause.

**Alternatives considered**:
- *django-simple-history on the whole Story* — rejected: heavyweight,
  tracks unrelated field churn, adds a dependency.
- *JSON column on Story* — rejected: unqueryable, not relationally
  auditable, contradicts FR-013's "single paginated query" ambition.

## R4: How do API endpoints map to the workflow?

**Decision**: Four new API actions on `StoryViewSet` (all in OpenAPI
automatically):

| Route | Method | Permission | Purpose |
|---|---|---|---|
| `/api/stories/review-queue/` | GET | `IsAdminOrManager` | pending stories, newest first, paginated |
| `/api/stories/{slug}/submit/` | POST | author (or manager/admin, object-level) | draft/rejected → pending |
| `/api/stories/{slug}/approve/` | POST | `IsAdminOrManager` + self-ban rule | pending → published, sets `published_at` |
| `/api/stories/{slug}/reject/` | POST | `IsAdminOrManager` + self-ban rule | pending → rejected, requires `reason` |

**Rationale**: `@action(detail=False)` for the queue gives a clean,
paginated DRF listing; detail actions keep decisions per-story and
mirror the existing `moderate` flag-flow pattern. Detail actions use the
slug lookup already configured on the ViewSet.

**Alternatives considered**:
- *Flat URLs (`/api/moderation/stories/`)* — rejected: fragments story
  behavior across modules; queue is intrinsically about stories.

## R5: Can a moderator moderate their own submission? (spec FR-008)

**Decision**: Institution managers are **blocked** from approving/rejecting
their own pending stories; admins are exempt. Enforced inside the service
functions (single source of truth), returning a typed error that both
surfaces map to 400/403 with a clear message.

**Rationale**: Spec FR-008 + edge case. Enforcing in the service means the
web UI cannot accidentally bypass what the API enforces.

**Alternatives considered**:
- *Block all self-moderation including admins* — rejected: spec explicitly
  exempts admins; small teams rely on admin override.
- *Warn but allow* — rejected: conflict-of-interest rule must be hard.

## R6: What happens to `reviewer_notes` on approval / resubmission?

**Decision**: Approve clears `reviewer_notes` (nothing to explain to the
author once public). Resubmit clears it too (FR-007: reason leaves the
active display but persists in decision history). Reject writes it.

**Rationale**: Keeps the field's meaning sharp: "the active, unresolved
reviewer explanation, if any". History is never lost — `ModerationDecision`
rows are append-only.

**Alternatives considered**:
- *Keep the reason visible after resubmission* — rejected: contradicts
  FR-007/US2-AC3.

## R7: How does the author see state and reason?

**Decision**:
- API: `StoryDetailSerializer` gains a read-only `rejection_reason` field
  (value of `reviewer_notes`) exposed **only** when the requesting user is
  the author, an institution manager, or an admin (SerializerMethodField).
  The mobile author thus sees state + reason with zero new endpoints.
- Web: story detail template shows a status banner for pending/rejected
  (with reason) to the author/moderators; a new "My submissions" section
  on the existing profile page lists the author's stories with status.
- `StoryListSerializer` gains `status` exposure for the author's own list
  (it already includes `status` in detail; list currently omits it — verify
  during implementation and keep detail/list consistent for authors).

**Rationale**: Reuses existing serialization paths; visibility boundary is
server-enforced (Constitution II); no separate "author view" endpoints.

**Alternatives considered**:
- *Dedicated `/my-stories/` API* — rejected: existing list endpoint already
  scopes to author via queryset rules (contributors see own drafts/pending);
  adding the field is sufficient.

## R8: Does the web UI get new routes?

**Decision**: Yes — minimal, mirroring mobile flows:

| Route | Name | Purpose |
|---|---|---|
| `/reviews/` | `web:review-queue` | moderator-only review queue page |
| `/actions/story/<slug>/approve/` | `web:review-approve` | POST, moderator-only |
| `/actions/story/<slug>/reject/` | `web:review-reject` | POST, moderator-only, requires `reason` field |
| `/actions/story/<slug>/submit/` | `web:story-submit` | POST, author-only: draft/rejected → pending |

Plus the profile page gains the author's submissions list.

**Rationale**: Follows the existing `web/actions.py` POST-only action
pattern and the `web/urls.py` naming conventions; `review-queue` as a page
matches the admin-dashboard precedent (role check + render).

**Alternatives considered**:
- *Fold approvals into the existing flag moderation (`story_moderate`)* —
  rejected: different lifecycles (community flags vs. editorial review);
  conflating them would muddy both.

## R9: Concurrency and idempotency

**Decision**: Transitions are guarded: `submit` is a no-op-with-success for
already-pending stories (FR-005 idempotency); `approve`/`reject` target
**only** pending stories — acting on a non-pending story returns a typed
"not pending" error (409-equivalent) with the story's current status, so
stale moderator tabs fail gracefully (edge case). Transitions wrap story
update + decision row in `transaction.atomic()`.

**Rationale**: Directly implements the spec's double-submission, stale-tab,
and accuracy edge cases without locks (conflict window is one request at
this scale; atomic transaction prevents partial state).

**Alternatives considered**:
- *`select_for_update`* — deferred: unnecessary at hundreds-of-stories
  scale; revisit if the platform grows by orders of magnitude.

## R10: Are there any spec/constitution risks left?

**Decision**: One deliberate scope note — spec SC-004's "visible within 60
seconds on both surfaces" is satisfied trivially (same-process reads; no
caching layers in front of story detail/list beyond WhiteNoise static).
No cache invalidation work is required; the criterion stays as a business
check, not a build item.

**Rationale**: Honest scoping (Constitution V): document why a seemingly
technical criterion needs no build work.

**Alternatives considered**: none needed.
