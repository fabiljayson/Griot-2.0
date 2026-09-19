# Feature Specification: Story Submission & Moderation Workflow

**Feature Branch**: `002-story-submission-moderation`

**Created**: 2026-09-19

**Status**: Draft

**Input**: User description: "story submission & moderation workflow"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Moderator Approves or Rejects Submitted Stories (Priority: P1)

A contributor submits a cultural story for review. A moderator (institution
manager or admin) opens a review queue that lists stories currently awaiting
a decision, reads the story in context (who wrote it, when, what), and
either **approves** it (making it publicly visible and permanently dated) or
**rejects** it (returning it to the author with a written explanation).
Today the platform has no approval path at all: stories submitted for
review are invisible to reviewers, never become public, and the "Rejected"
state — though defined — can never be reached through any product flow.

**Why this priority**: This is the core trust loop of a community heritage
platform. Without a decision flow, contributed content can never reach the
public catalog except through the Django admin — the submission feature
effectively dead-ends.

**Independent Test**: Can be fully tested by submitting a story as a
contributor, confirming it appears in a moderator-only review queue,
approving it, and confirming it appears in the public catalog with a
publication date; repeated with a rejection and confirming the author can
see the rejection reason.

**Acceptance Scenarios**:

1. **Given** a contributor submits a story for review, **When** a moderator
   opens the review queue, **Then** the story appears with its title,
   author, submission time, and summary/content preview.
2. **Given** a story is awaiting review, **When** a moderator approves it,
   **Then** the story becomes publicly visible and its publication
   timestamp is recorded.
3. **Given** a story is awaiting review, **When** a moderator rejects it
   with a written reason, **Then** the story leaves the review queue, is
   not publicly visible, and the author can see the rejection reason on
   their own copy of the story.
4. **Given** a user without moderator role, **When** they attempt to open
   the review queue or act on a story in it, **Then** they are denied
   regardless of authentication state.
5. **Given** a story already approved or archived, **When** a moderator
   views the review queue, **Then** that story does not appear (queue
   shows only stories awaiting a first decision or resubmissions).

---

### User Story 2 - Author Sees Where Their Submission Stands (Priority: P2)

The submitting author can always see the current state of their own story
(draft, awaiting review, published, or rejected with reason) — on the story
itself and in a personal list of their submissions — without needing
moderator access. When a story is rejected, the reason travels with it so
the author can revise and resubmit rather than guessing what went wrong.

**Why this priority**: The submission workflow is only trustworthy if
authors get feedback; a rejection without a visible reason turns the
moderation step into a black hole and suppresses future contributions.

**Independent Test**: Can be fully tested by creating a story as a
contributor, checking its visible state transitions (draft → awaiting
review → rejected with reason), revising, and resubmitting — all without
any moderator account.

**Acceptance Scenarios**:

1. **Given** an author with a story awaiting review, **When** they view
   their own story or their submissions list, **Then** they see an
   "awaiting review" indication.
2. **Given** a rejected story, **When** the author views it, **Then** the
   moderator's written reason is displayed to the author (and to
   moderators), but not to the general public.
3. **Given** a rejected story, **When** the author edits and resubmits it,
   **Then** it re-enters the awaiting-review state, the previous rejection
   reason is cleared from the active display, and the story appears in the
   review queue again.
4. **Given** an author's submissions list, **When** they open it, **Then**
   it shows each of their stories with its current state, most recently
   updated first.

---

### User Story 3 - Every Interface Shows the Same Submission State (Priority: P3)

The three surfaces (REST API for the mobile app, server-rendered web UI)
expose identical story-state semantics: the same set of states, the same
rules for who may move a story between states, and the same visibility
rules. A story submitted on mobile looks the same to a web moderator, and
a decision made on the web is immediately reflected for the mobile author.

**Why this priority**: Prevents the two clients from drifting into
incompatible workflows (the platform's constitution requires parity), but
delivers no standalone user value until US1/US2 exist.

**Independent Test**: Can be tested by exercising the same submit →
moderate → view cycle through both the API and the web UI and asserting
identical state outcomes and visibility.

**Acceptance Scenarios**:

1. **Given** any authenticated contributor on any surface, **When** they
   submit a story for review, **Then** the story enters the same
   awaiting-review state visible in the single moderator queue.
2. **Given** a moderator decision made via the web UI, **When** the author
   fetches their story through the API, **Then** the state and rejection
   reason match what the web shows.
3. **Given** the published catalog on any surface, **When** a story is
   approved, **Then** it appears in catalog listings on both surfaces
   without further action.

---

### Edge Cases

- What happens when a moderator approves their **own** submission?
  → Allowed only for admins; institution managers moderating their own
  story must not self-approve (conflict of interest) — the action is
  blocked with a clear error and the story stays in the queue for another
  moderator.
- What happens when a story awaiting review is **edited** by its author?
  → Editing keeps it in the awaiting-review state (re-review of updated
  content); the queue reflects the latest content and updated timestamp.
- What happens when a story is submitted twice (double-click / retry)?
  → Submission is idempotent: an already-awaiting-review story stays
  awaiting review; no duplicate queue entries.
- What happens when an author deletes a story that is awaiting review?
  → It disappears from the review queue; moderators see no ghost entries.
- What happens when a rejection reason is empty?
  → Rejection MUST require a non-empty reason; the action is refused
  otherwise, preventing reason-less rejections.
- What happens when a moderator tries to act on a story that was already
  decided (published/archived) or deleted while they had the queue open?
  → The action fails gracefully with a clear message; no state corruption.
- What happens to read counts, likes, or quizzes when a story is rejected
  and later resubmitted and approved?
  → Engagement data is never reset by moderation actions; approval does
  not duplicate quiz or badge state.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a moderator review queue listing every
  story currently awaiting review, most recent submission first, showing
  title, author, submission time, and a content preview.
- **FR-002**: System MUST allow moderators (institution managers and
  admins) to approve a story awaiting review; approval MUST make the story
  publicly visible and MUST record the publication timestamp.
- **FR-003**: System MUST allow moderators to reject a story awaiting
  review only when a non-empty written reason is provided; rejection MUST
  store the reason with the story and MUST NOT make the story public.
- **FR-004**: System MUST prevent non-moderators from viewing the review
  queue or performing moderation actions, on every surface.
- **FR-005**: System MUST allow authors to submit their own draft stories
  for review and to see the resulting state; submission MUST be idempotent
  for an already-awaiting-review story.
- **FR-006**: System MUST show each author the state of their own stories
  and a personal submissions list; the rejection reason MUST be visible to
  the story's author and to moderators but hidden from other users.
- **FR-007**: System MUST allow an author to edit and resubmit a rejected
  story; resubmission MUST clear the active rejection reason display and
  return the story to the awaiting-review state.
- **FR-008**: System MUST prevent institution managers from approving or
  rejecting their own submissions (admins are exempt).
- **FR-009**: System MUST keep the awaiting-review queue accurate: edited
  submissions stay queued, approved/archived/rejected stories leave it,
  and deleted stories disappear from it.
- **FR-010**: System MUST expose identical state semantics (states, state
  transition rules, and visibility rules) on both the REST API and the web
  UI, and publication decisions taken on one surface MUST be immediately
  reflected on the other.
- **FR-011**: System MUST preserve all engagement data (views, likes,
  bookmarks, shares, quiz attempts, badges) across rejection, resubmission,
  and approval.
- **FR-012**: System MUST record when each state change of a story was
  made and by whom, for accountability (who approved/rejected, when).
- **FR-013**: The review queue and story-state surfaces MUST remain fast
  at the platform's current scale (hundreds of stories): queue retrieval
  MUST stay a single paginated query, and state-change actions MUST
  complete without perceivable delay.

### Key Entities *(include if feature involves data)*

- **Story** (existing): carries the workflow state — the draft → awaiting
  review → published/rejected lifecycle; a written reviewer explanation;
  and a publication timestamp set only by approval. Rejection reason and
  publication timestamp have specific visibility rules (author + moderators
  see the reason; everyone sees published stories).
- **Moderation decision record** (new): who decided, what was decided
  (approved/rejected), the written reason, and when — appended per
  decision, never overwritten, so the history of a story's review round
  survives resubmissions.
- **User** (existing): role determines capability — contributors and above
  may submit; institution managers and admins may moderate; only admins may
  moderate their own submissions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A contributor can submit a story and a moderator can reach a
  decision (approve or reject) entirely through product interfaces, with
  no database or Django-admin intervention, in under 5 minutes end-to-end.
- **SC-002**: 100% of stories awaiting review appear in the moderator
  queue; zero non-pending stories appear in it.
- **SC-003**: A rejected author can state, from the product UI alone, why
  their story was rejected and what state their story is in — verified in
  usability walkthrough with 3 of 3 test participants.
- **SC-004**: A story approved on the web is visible in the public catalog
  within 60 seconds on both surfaces with no cache-busting manual action.
- **SC-005**: 100% of moderation state changes are attributable to a
  named account and timestamp (auditable for any story).
- **SC-006**: Non-moderators receive denial responses on 100% of attempts
  to reach the queue or act on it, verified across both surfaces.

## Assumptions

- The existing story states (draft, pending review, published, rejected,
  archived) and the existing roles (visitor, contributor, institution
  manager, admin) are sufficient — no new states or roles are introduced.
- "Moderator" means institution manager or admin, matching the existing
  `IsAdminOrManager` permission semantics used elsewhere in the platform.
- Flag-based moderation (community reports → flag queue → remove/dismiss)
  exists and stays separate: this feature covers the *submission review*
  lifecycle only.
- The Django admin remains a fallback for content operations but is not
  part of the acceptance flows.
- Approval dating uses the platform's existing publication-timestamp
  field; no separate audit schema is introduced beyond the decision
  record.
- Email or push notification of decisions is out of scope; authors check
  their submissions list (a follow-up feature may add notifications).
- The platform's content volume is in the hundreds of stories; queue
  pagination at 20 per page (the platform default) is adequate.
