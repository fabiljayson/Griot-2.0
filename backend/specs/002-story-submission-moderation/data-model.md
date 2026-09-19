# Data Model: Story Submission & Moderation Workflow

**Feature**: 002-story-submission-moderation | **Date**: 2026-09-19

## New entity

### ModerationDecision (`stories.models.ModerationDecision`)

| Field | Type | Constraints | Purpose |
|---|---|---|---|
| `story` | FK → `stories.Story` | `on_delete=CASCADE`, `related_name='moderation_decisions'` | The reviewed story |
| `moderator` | FK → `users.User` | `on_delete=SET_NULL`, `null=True`, `related_name='moderation_decisions'` | Who decided (null if account deleted — audit keeps row) |
| `decision` | CharField | choices `approved` / `rejected`, max 20 | What was decided |
| `reason` | TextField | `blank=True`, default `''` | Written reason — REQUIRED non-empty for `rejected` (service-enforced) |
| `created_at` | DateTimeField | `auto_now_add=True` | When (indexed with story) |

**Meta**: `ordering = ['-created_at']`; index `('story', '-created_at')`.

**Invariant**: append-only. No product path updates or deletes rows; no
unique constraints (a story may have many decisions across review rounds).

## Modified entity

### Story (existing — no schema change)

Reused fields, no migration:

| Field | Role in workflow |
|---|---|
| `status` | Lifecycle state (existing choices reused) |
| `reviewer_notes` | **Active** reviewer explanation; written on reject, cleared on approve/resubmit. History lives in ModerationDecision. |
| `published_at` | Set by approval (timezone.now); cleared never (approval is terminal until a future unpublish feature) |

## State machine (authoritative)

```text
                    submit (author)              approve (moderator)
  ┌───────┐ ──────────────────────▶ ┌─────────┐ ─────────────────────▶ PUBLISHED
  │ DRAFT │                          │ PENDING │      (sets published_at,
  └───────┘ ◀────────────────────── └─────────┘       clears reviewer_notes)
              reject (moderator,          ▲  │
              requires reason)            │  │ resubmit (author; clears
                    ┌─────────────────────┘  │ reviewer_notes; stays/returns pending)
                    ▼                        │
                REJECTED ────────────────────┘
                    │
                    │ (author may edit + resubmit; delete allowed anytime)
                    ▼
                 deleted

  ARCHIVED: untouched by this feature (flag-moderation lifecycle)
```

**Transition rules** (enforced in `stories/services.py`, single source of truth):

| From | Action | Actor | To | Side effects |
|---|---|---|---|---|
| draft **or** rejected | submit | author (or manager/admin) | pending | idempotent if already pending |
| pending | approve | manager/admin (not own story unless admin) | published | `published_at=now`, clear `reviewer_notes`, decision row `approved` |
| pending | reject | manager/admin (not own story unless admin) | rejected | `reviewer_notes=reason` (required), decision row `rejected` |
| rejected | submit | author | pending | clear `reviewer_notes`, decision history preserved |
| any non-pending | approve/reject | — | **error** | typed `NotPendingError` carrying current status |

**Actor rules**: contributors/institution managers/admins may submit their
own stories. Moderation = institution_manager + admin, with the FR-008
self-approval ban (managers cannot moderate own stories; admins exempt).

## Visibility matrix (server-enforced)

| Data | Anonymous | Visitor (auth) | Author | Manager | Admin |
|---|---|---|---|---|---|
| Published story content | ✅ | ✅ | ✅ | ✅ | ✅ |
| Own draft/pending/rejected content | ❌ | ❌ | ✅ | ✅ (all) | ✅ |
| `reviewer_notes` / `rejection_reason` | ❌ | ❌ | ✅ (own) | ✅ | ✅ |
| Review queue | ❌ | ❌ | ❌ | ✅ | ✅ |
| Moderation decisions (history) | ❌ | ❌ | own stories | ✅ | ✅ |

Unchanged from today: queryset rules already scope author content; the only
new visibility surface is `rejection_reason` (SerializerMethodField) and the
moderator-only queue.

## Migration plan

One migration: `stories/00XX_moderationdecision.py` — creates the table and
indexes. No data migration (no backfill: only pending stories have a live
review; `published_at` backfill for already-published stories is out of
scope per assumptions). Committed together with model changes
(Constitution III quality gate).
