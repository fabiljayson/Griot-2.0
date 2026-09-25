# Use Case Diagram — Griot 2.0

> **Reconciled with the implementation on 2026-09-22.** The diagram and tables
> below now describe *verified* behavior rather than the original intent.
> **Updated 2026-09-23** for the `settings` (WhatsApp feedback) and admin
> platform-users features ([Added](#added-2026-09-23)).
> Everything that changed, and every place where the implementation still
> looks wrong, is recorded in [Divergences](#divergences-from-the-original-document).

## Actors

| Actor | Description |
|---|---|
| **Guest** | Unauthenticated visitor browsing public content |
| **Visitor** | Authenticated user (role: visitor) |
| **Contributor** | Authenticated user who creates stories and media |
| **Institution Manager** | Manages museum artifacts, QR codes, moderates content |
| **Admin** | Full platform administration |
| **Luma AI** | External AI video generation service |
| **TTS Service** | External text-to-speech service |

## Use Case Diagram (Mermaid)

```mermaid
useCaseDiagram
    title Griot 2.0 — Use Case Diagram

    package "Authentication" {
        usecase "Register Account" as UC_REG
        usecase "Login" as UC_LOGIN
        usecase "View Profile" as UC_PROFILE
        usecase "Edit Profile" as UC_EDIT_PROFILE
        usecase "Set Language & Theme" as UC_PREFS
        usecase "Delete Account" as UC_DEL_ACC
    }

    package "Stories" {
        usecase "Browse Stories" as UC_BROWSE
        usecase "Search Stories" as UC_SEARCH
        usecase "Read Story" as UC_READ
        usecase "Create Story" as UC_CREATE_STORY
        usecase "Edit Story" as UC_EDIT_STORY
        usecase "Delete Story" as UC_DEL_STORY
        usecase "Bookmark Story" as UC_BOOKMARK
        usecase "Like Story" as UC_LIKE
        usecase "Flag Story" as UC_FLAG
        usecase "Track Reading Progress" as UC_PROGRESS
        usecase "View Curated Feeds" as UC_FEEDS
        usecase "View Trending" as UC_TRENDING
        usecase "View Popular" as UC_POPULAR
        usecase "View Discover" as UC_DISCOVER
    }

    package "Library" {
        usecase "View Library" as UC_LIB
        usecase "Continue Reading" as UC_CONTINUE
        usecase "View Bookmarks" as UC_VIEW_BM
        usecase "View Recently Read" as UC_RECENT
    }

    package "QR & Artifacts" {
        usecase "Scan QR Code" as UC_SCAN
        usecase "View Artifact" as UC_ARTIFACT
        usecase "Create Artifact" as UC_CREATE_ART
        usecase "Generate QR Code" as UC_GEN_QR
    }

    package "Audio" {
        usecase "Listen to TTS" as UC_TTS
        usecase "Generate Audio Narration" as UC_GEN_TTS
        usecase "Generate Artifact Audio Guide" as UC_GEN_GUIDE
        usecase "Play Offline Audio" as UC_OFFLINE_AUDIO
    }

    package "Video" {
        usecase "Generate AI Video" as UC_GEN_VIDEO
        usecase "Watch Video" as UC_WATCH
        usecase "Poll Video Status" as UC_POLL_VIDEO
    }

    package "Gamification" {
        usecase "Browse Quizzes" as UC_QUIZZES
        usecase "Take Quiz" as UC_QUIZ
        usecase "View Badges" as UC_BADGES
        usecase "View Leaderboard" as UC_LEADER
        usecase "View Certificate" as UC_CERT
        usecase "View Gamification Profile" as UC_GAME_PROFILE
    }

    package "Sharing" {
        usecase "Share Story" as UC_SHARE
        usecase "View Quote Card" as UC_QUOTE
    }

    package "Settings" {
        usecase "Send Feedback (WhatsApp)" as UC_FEEDBACK
    }

    package "Admin" {
        usecase "View Analytics Dashboard" as UC_ANALYTICS
        usecase "View Platform Users" as UC_PLATFORM_USERS
        usecase "Moderate Content" as UC_MODERATE
        usecase "View Moderation Queue" as UC_MOD_QUEUE
        usecase "Resolve Flags" as UC_RESOLVE
    }

    package "Offline" {
        usecase "Save Story Offline" as UC_SAVE_OFFLINE
        usecase "Read Offline" as UC_READ_OFFLINE
        usecase "Sync Pending Requests" as UC_SYNC
    }

    %% ── Guest (unauthenticated) ─────────────────────────────────────────
    %% Verified: trending/popular/discover and badges are `AllowAny` in the
    %% API; the web UI serves anonymous users the reader + artifact catalogue.
    %% NOT listed here any more:
    %%   UC_VIEW_BM  — bookmarks are per-user rows; a Guest cannot own one.
    %%   UC_GEN_QR   — it is a Manager/Admin action and now enforced as one
    %%                 (it previously fell through to AllowAny — see below).
    %% Reachable on web + API only: the Flutter app has no guest mode.
    Guest --> UC_REG
    Guest --> UC_LOGIN
    Guest --> UC_BROWSE
    Guest --> UC_SEARCH
    Guest --> UC_READ
    Guest --> UC_SCAN
    Guest --> UC_ARTIFACT
    Guest --> UC_TTS
    Guest --> UC_WATCH
    Guest --> UC_QUIZZES
    Guest --> UC_BADGES
    Guest --> UC_LEADER
    Guest --> UC_TRENDING
    Guest --> UC_POPULAR
    Guest --> UC_DISCOVER

    Visitor --|> Guest
    Visitor --> UC_GEN_TTS
    Visitor --> UC_PROFILE
    Visitor --> UC_EDIT_PROFILE
    Visitor --> UC_PREFS
    Visitor --> UC_BOOKMARK
    Visitor --> UC_LIKE
    Visitor --> UC_FLAG
    Visitor --> UC_PROGRESS
    Visitor --> UC_LIB
    Visitor --> UC_CONTINUE
    Visitor --> UC_VIEW_BM
    Visitor --> UC_RECENT
    Visitor --> UC_QUIZZES
    Visitor --> UC_QUIZ
    Visitor --> UC_BADGES
    Visitor --> UC_LEADER
    Visitor --> UC_CERT
    Visitor --> UC_GAME_PROFILE
    Visitor --> UC_SHARE
    Visitor --> UC_QUOTE
    Visitor --> UC_SAVE_OFFLINE
    Visitor --> UC_READ_OFFLINE
    Visitor --> UC_OFFLINE_AUDIO
    Visitor --> UC_GEN_GUIDE
    Visitor --> UC_FEEDBACK
    Visitor --> UC_DEL_ACC

    Contributor --|> Visitor
    Contributor --> UC_CREATE_STORY
    Contributor --> UC_EDIT_STORY
    Contributor --> UC_DEL_STORY
    Contributor --> UC_GEN_TTS
    Contributor --> UC_GEN_VIDEO
    Contributor --> UC_POLL_VIDEO

    InstitutionManager --|> Contributor
    InstitutionManager --> UC_CREATE_ART
    InstitutionManager --> UC_GEN_QR
    InstitutionManager --> UC_MODERATE
    InstitutionManager --> UC_MOD_QUEUE
    InstitutionManager --> UC_RESOLVE
    InstitutionManager --> UC_ANALYTICS
    InstitutionManager --> UC_PLATFORM_USERS

    Admin --|> InstitutionManager
    Admin --> UC_DEL_STORY
    Admin --> UC_ANALYTICS
    Admin --> UC_PLATFORM_USERS
    Admin --> UC_DEL_ACC
```

## Use Case Descriptions

| Use Case | Actor(s) | Description |
|---|---|---|
| Register Account | Guest | Create a new account (username/email/password) with role choice: visitor or contributor |
| Login | Guest | Authenticate and receive JWT tokens |
| Browse Stories | Guest, Visitor, Contributor, Manager, Admin | List and view published stories |
| Search Stories | All | Full-text search across stories with filters |
| Read Story | All | View story content in Markdown reader |
| Create Story | Contributor+ | Submit a new cultural story |
| Edit Story | Owner, Manager, Admin | Modify existing story content |
| Delete Story | Owner, Manager, Admin | Delete a story. Documented as Admin-only; the implementation also lets the author delete their own (see divergences) |
| Bookmark Story | Authenticated | Save story to personal library |
| Like Story | Authenticated | Toggle like on a story |
| Flag Story | Authenticated | Report content for moderation |
| Track Reading Progress | Authenticated | Save scroll position and completion |
| View Curated Feeds | All | Access trending/popular/discover feeds |
| Scan QR Code | All | Scan museum artifact QR code |
| View Artifact | All | View artifact details and related stories |
| Create Artifact | Manager, Admin | Add new artifact to catalog |
| Generate QR Code | Manager, Admin | Create QR code for an artifact. **Now enforced** — previously reachable unauthenticated (see divergences) |
| Listen to TTS | All | Play audio narration of a story |
| Generate Audio Narration | Authenticated (published story); Owner/Manager/Admin (own or unpublished) | Request TTS generation for a story |
| Generate Artifact Audio Guide | Authenticated (published artifact); Manager/Admin (unpublished) | Generate the museum audio guide via TTS |
| Edit Profile | Authenticated | Update name, email and institution (roles are admin-granted) |
| Set Language & Theme | Authenticated | Persist UI language (EN/FR). **Theme is not settable** — no endpoint writes `WebUserSettings.theme` |
| Browse Quizzes | All | List published quizzes with latest results (`QuizViewSet` is `IsAuthenticatedOrReadOnly`) |
| Generate AI Video | Contributor+ | Request Luma AI video generation |
| Take Quiz | Authenticated | Complete a story quiz |
| View Badges | All | Browse earned/available badges |
| View Leaderboard | All | See top users by XP (`LeaderboardView` is `AllowAny`). **No mobile UI** |
| View Certificate | Authenticated | Download heritage certificate. **No mobile UI** |
| Share Story | Authenticated | Share to social platforms (both the API and the web require a session) |
| View Analytics Dashboard | Admin, Institution Manager | View platform metrics. The implemented gate is `IsAdminOrManager`, which is **wider than the original Admin-only rule** |
| Moderate Content | Manager, Admin | Review flagged content |
| Save Story Offline | Authenticated | Cache story for offline reading |
| Read Offline | Authenticated | Read cached content without internet |
| Sync Pending Requests | System | Replay queued offline requests |
| Send Feedback (WhatsApp) | Authenticated | Open the developer's WhatsApp chat with a prefilled message via `wa.me` (`WhatsAppFeedbackService`) |
| View Platform Users | Manager, Admin | List platform users with search (`AdminUsersListView`, `GET /api/analytics/users/list/?search=`) |

---

## Divergences from the original document

Recorded 2026-09-22 after tracing every use case from UI → provider/repository →
API/view → model → authorization rule. Legend: **CORRECTED** = the document was
wrong and the implementation is authoritative · **FIXED** = the implementation was
wrong and has been changed · **OPEN** = implementation looks wrong and needs a
decision · **GAP** = documented but not built.

### CORRECTED (document changed to match the code)

| # | Item | Originally said | Actually implemented |
|---|---|---|---|
| 1 | `Guest → View Bookmarks` | Guests can view bookmarks | Removed. `StoryBookmark` is a `unique_together(user, story)` row; the read endpoints (`bookmarks`, `recently_read`, `continue_reading`) are all `IsAuthenticated`. |
| 2 | `Visitor → Register / Login` | Registration and login were Visitor use cases | Moved to **Guest**. They are pre-authentication actions; this file's own description table already attributed both to Guest. |
| 3 | `Admin → Delete Story` | Delete was Admin-only | A **Contributor may delete their own** story; Manager/Admin may delete any (`IsStoryOwnerOrReadOnly`, `web/actions.py::story_delete`). |
| 4 | `Generate Audio Narration` | Contributor+ | Any **authenticated** user for a **published** story; owner ∪ Manager/Admin otherwise. Mirrored in `AudioNarrationViewSet.create`. |
| 5 | `Browse Quizzes` / `View Leaderboard` | Authenticated | **Public.** `QuizViewSet` is `IsAuthenticatedOrReadOnly`; `LeaderboardView` is `AllowAny`. `QuizQuestionSerializer` correctly omits `correct_answer`, so this exposes questions but not answers. |
| 6 | `Share Story` | All | **Authenticated.** `StoryViewSet.share` falls to the `IsAuthenticated` branch; `web/actions.py::story_share` is `@login_required`, even though `StoryShare.user` is nullable and built for anonymous shares. |
| 7 | `View Analytics Dashboard` | Admin | **Admin + Institution Manager** (`IsAdminOrManager`, `api/views_analytics.py`). |
| 8 | `Set Language & Theme` | Language **and** theme persist | Only language is settable. No endpoint writes `WebUserSettings.theme`. |
| 9 | Accessor notation | `is_visitor()`, `is_published()` etc. as methods | These are `@property` in the models — see `02-class-diagram.md`. |

### FIXED (implementation changed to match the document)

| # | Item | Was | Now |
|---|---|---|---|
| 10 | `Generate QR Code` authorization | `ArtifactViewSet.get_permissions` allow-listed only CRUD, so the `generate_qr` custom action fell through to `AllowAny` — an **unauthenticated POST could persist `qr_code_svg`** onto a published artifact. | `generate_qr` added to the manager-only action list. Anonymous → 401, Visitor → 403, Manager/Admin → 200. Guarded by `qr_codes/tests.py::test_generate_qr_requires_manager`; scanning remains public. |

### OPEN (implementation looks wrong — awaiting a decision)

| # | Item | Problem |
|---|---|---|
| 11 | `Story.co_authors` | Declared on the model and in the class diagram, but **no permission check, serializer, form or view reads it.** Co-authors have no edit/media/delete rights. Either four authorization checks are incomplete or the relation is vestigial. |
| 12 | `home_view` vs public feeds | `trending`/`popular`/`discover` are `AllowAny` in the API, but `web/views.py::home_view` **empties trending and popular for anonymous users**. The same public use case is public on one client and blocked on the other. |
| 13 | Share copy | The API says *"African Teller"*, the web says *"Griot AI"*, and both embed `🌍📖`. |
| 14 | Duplicated template gate | `story_detail.html` uses the server-computed `can_generate_media` in four places but hand-rolls an equivalent expression for its Edit link — two sources of truth for one rule. |
| 15 | `nav_items.html` precedence | `{% if user.is_authenticated and user.role == 'admin' or user.role == 'institution_manager' %}` parses as `(auth and admin) or manager`, so the manager branch is not covered by the auth check. Safe today only because an undefined `AnonymousUser.role` renders as `''`. Same pattern in `story_detail.html`. |

### GAP (documented, not implemented)

| # | Item | Status |
|---|---|---|
| 16 | **Guest actor on mobile** | `AuthWrapper` shows `LoginScreen` for every unauthenticated state, so the entire Guest column is **unreachable in the Flutter app**. Also makes `SignInPrompt` dead code in practice. |
| 17 | **Publication workflow** | `draft`/`pending` are submittable from both clients, but `pending → published` happens **only via the Django admin site** (`stories/admin.py`). There is no review screen, no approve/reject endpoint, and `rejected` is never assigned anywhere. |
| 18 | **Mobile leaderboard / certificate** | `gamification_api_service.getLeaderboard()` is hardcoded to `return []`; no leaderboard or certificate UI exists in Flutter. |
| 19 | **Mobile artifact authoring** | No Flutter UI for `Create Artifact` or `Generate QR Code`. |
| 20 | **Mobile artifact audio guide** | No Flutter UI or service call for `Generate Artifact Audio Guide`. |
| 21 | **Mobile video playback** | `VideoStatusBadge` / `VideoPlayerWidget` are referenced only from inside the video feature, so `Watch Video` has no mobile surface. |
| 22 | **Quote card (web)** | `QuoteCardGenerator` is mobile-only; there is no backend model or web template for `View Quote Card`. |
| 23 | **Role-aware mobile navigation** | `main_shell.dart` renders the same five destinations for every role. `UserModel.canContribute` existed but was never referenced. |

### ADDED (2026-09-23)

| # | Item | Status |
|---|---|---|
| 24 | **Send Feedback (WhatsApp)** | Implemented in `frontend/lib/features/settings/` (`SettingsScreen` + `WhatsAppFeedbackService`). Opens a `wa.me` chat with a prefilled message to the developer contact — no backend endpoint. |
| 25 | **View Platform Users** | Implemented (`AdminUsersListView`, `GET /api/analytics/users/list/?search=`). Lists every platform account (SQLite + Postgres) with role/status filter; used by the admin dashboard users widget. Gated by `IsAdminOrManager`. |
