# Contracts: API & Web Routes

**Feature**: 002-story-submission-moderation | **Date**: 2026-09-19

## A1: Review queue (NEW)

```text
GET /api/stories/review-queue/
Authorization: Bearer <jwt>   (institution_manager | admin)
→ 200 {
  "count": int, "next": url|null, "previous": url|null,
  "results": [ {
    "id", "slug", "title", "summary",
    "author": {username, role},
    "status": "pending",
    "submitted_at": iso8601,        # latest updated_at
    "content_preview": str (≤200 chars)
  }, ... ]
}
→ 403 for authenticated non-moderators; 401 anonymous
```

Paginated (platform default, 20/page), ordered by `-updated_at`.

## A2: Submit for review (NEW)

```text
POST /api/stories/{slug}/submit/
Authorization: Bearer <jwt>   (story author; managers/admins any own-permission story)
→ 200 { "id", "slug", "status": "pending", "detail": "..." }
→ 200 (idempotent) if already pending — same payload
→ 403 if not author/moderator
→ 404 unknown slug
```

Accepts empty body. Valid transitions: draft→pending, rejected→pending.

## A3: Approve (NEW)

```text
POST /api/stories/{slug}/approve/
Authorization: Bearer <jwt>   (institution_manager | admin)
→ 200 { "id", "slug", "status": "published", "published_at": iso8601 }
→ 409 { "error": "not_pending", "current_status": <status> }  when story not pending
→ 403 { "error": "self_moderation_forbidden" }  manager approving own story
→ 401/403 otherwise
```

Empty body. Server sets `published_at`; clears `reviewer_notes`.

## A4: Reject (NEW)

```text
POST /api/stories/{slug}/reject/
Authorization: Bearer <jwt>   (institution_manager | admin)
Body: { "reason": "non-empty string" }
→ 200 { "id", "slug", "status": "rejected" }
→ 400 { "reason": ["This field may not be blank."] }  missing/blank reason
→ 409 { "error": "not_pending", "current_status": <status> }
→ 403 { "error": "self_moderation_forbidden" }
```

Writes `reviewer_notes=reason`; appends decision row.

## A5: Rejection reason visibility (MODIFIED serializer)

```text
GET /api/stories/{slug}/   (and list results for one's own stories)
→ adds "rejection_reason": <str|null>
  — populated ONLY when requester is the author, a manager, or an admin;
    null otherwise (never leaks to public/visitors)
```

## A6: Unchanged contracts (must not regress)

- `POST /api/stories/` create: remains `status` read-only → new stories are
  draft. Submission is now possible via A2 (closing the mobile gap).
- `GET /api/stories/` list + filters: unchanged; author scoping rules
  unchanged (contributors see own drafts/pending).
- Flag moderation: `GET /api/stories/moderation-queue/` (flags) and
  `POST /api/stories/{slug}/moderate/` — untouched, separate lifecycle.

## W1: Web routes (NEW)

| Route | Name | Method | Auth | Purpose |
|---|---|---|---|---|
| `/reviews/` | `web:review-queue` | GET | moderator | queue page: pending stories with author, submitted time, preview, approve/reject forms |
| `/actions/story/<slug>/submit/` | `web:story-submit` | POST | author | draft/rejected → pending (button on own story + form) |
| `/actions/story/<slug>/approve/` | `web:review-approve` | POST | moderator | pending → published |
| `/actions/story/<slug>/reject/` | `web:review-reject` | POST | moderator | form field `reason` required; redirect back with message |

POST-only actions follow `web/actions.py` conventions (`@login_required`,
`@require_POST`, role checks raising `PermissionDenied`, `_safe_next`
redirects, `messages` feedback).

## W2: Web page behavior

- Review queue page: list of pending stories (title, author, submitted,
  preview) each with Approve button and Reject form (reason textarea).
  Empty state: "No stories awaiting review."
- Story detail (author view): banner for `pending` ("Awaiting review") and
  `rejected` (reason shown) — visible to author + moderators only; submit
  button for draft/rejected own stories.
- Profile page: "My submissions" list — author's stories, status badge per
  story, newest first.
