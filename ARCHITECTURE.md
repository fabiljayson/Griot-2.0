# Griot 2.0 — African Teller: System Architecture

> A cross-platform digital heritage platform preserving and sharing Cameroon's
> oral traditions. Read cultural tales, scan museum artifact QR codes, watch
> AI-generated story videos, quiz your knowledge, and earn heritage badges.

This document describes the **entire application architecture**: screens and
navigation, data models and APIs, key user flows, roles & authentication, and
the constraints that shape the design.

---

## 1. High-Level Overview

The platform is a **client–server** architecture with a **feature-first** code
layout on both sides.

```
┌─────────────────────────────────────────────────────────────┐
│                         FLUTTER CLIENT                       │
│  iOS · Android · Web (PWA)                                   │
│  ┌───────────────┐  ┌───────────────┐  ┌──────────────────┐  │
│  │  Feature      │  │  Core         │  │  Local SQLite/   │  │
│  │  Modules      │  │  (Network,    │  │  IndexedDB cache │  │
│  │  (auth,       │  │  Theme, DB,   │  │  (offline)       │  │
│  │  stories, ...)│  │  Providers)   │  │                  │  │
│  └───────┬───────┘  └───────┬───────┘  └────────┬─────────┘  │
└──────────┼──────────────────┼───────────────────┼────────────┘
           │  HTTPS / JSON (Dio)                   │  offline-first
           ▼                                       ▼
┌──────────────────────────────────────────────────────────────────┐
│                   DJANGO REST FRAMEWORK API                        │
│  ┌────────┬──────────┬──────────┬───────────┬──────────┐          │
│  │ Users  │ Stories  │ QR Codes │ Gamific   │ Media    │          │
│  │ (auth, │ (tales,  │ (artif-  │ (quizzes, │ (AI video│          │
│  │ roles) │ bookmarks)│ acts)    │ badges)   │  & TTS)  │          │
│  └────────┴──────────┴──────────┴───────────┴──────────┘          │
│  ┌────────────────────────────────┐  ┌──────────────────────────┐  │
│  │  API (health, analytics,      │  │  Middleware / Logging    │  │
│  │  observability, seed commands)│  │  (structured JSON)       │  │
│  └────────────────────────────────┘  └──────────────────────────┘  │
│  SQLite (dev) / Postgres (prod) · Luma AI · TTS · QR generator    │
└──────────────────────────────────────────────────────────────────┘
```

- **Backend** — Django 5.2 + Django REST Framework (DRF), JWT auth, feature apps.
- **Frontend** — Flutter (Riverpod state management), Dio networking, local
  SQLite (mobile) / IndexedDB (web) caching.
- **Infrastructure** — Sentry error monitoring, structured JSON logging, health
  probes, analytics endpoints.

---

## 2. Screens & Navigation

The Flutter app is **auth-aware**: an `AuthWrapper` decides what to show based
on the current `AuthStatus`. Navigation is **imperative** (`Navigator.push`)
between feature screens; there is no bottom-tab scaffold yet — the `HomeScreen`
acts as the landing dashboard.

### 2.1 Navigation Root (`app.dart` → `AuthWrapper`)

```
AfricanTellerApp (MaterialApp)
 └── AuthWrapper(child: HomeScreen())
      ├── loading            → _AuthLoadingScreen (drum splash)
      ├── unauthenticated    → LoginScreen
      └── authenticated      → HomeScreen (landing dashboard)
```

### 2.2 Primary Screens & Flows

| Flow | Screen | Route / Trigger | Role Access |
|------|--------|----------------|-------------|
| **Onboarding / Auth** | `LoginScreen` | App start (unauthenticated) | All |
| | `RegisterScreen` | "Create account" from login | All |
| | `ProfileScreen` | User profile / role badge | Authenticated |
| **Home / Discovery** | `HomeScreen` | Root after login | All |
| **Stories** | `StoriesScreen` | Discovery grid + fuzzy search/filter | All |
| | `StoryDetailScreen` | Tap a story card (markdown reader, reading progress) | Authenticated |
| | `StoryFormScreen` | Create/edit a story | Contributor+ |
| **Library** | `LibraryScreen` | Continue reading, bookmarks, recently read | Authenticated |
| **QR / Artifacts** | QR scanner widget | Scan museum artifact | All |
| | `ArtifactDetailScreen` | Deep link `/artifact/<slug>` or scan result | All |
| **Audio** | `AudioPlayerSheet` | Play TTS narration from story/video detail | All |
| **Video** | `VideoGenerationSheet` | Generate AI video for a story | Contributor+ |
| | `VideoPlayerWidget` | Watch generated video | All |
| **Gamification** | `GamificationScreen` | Quizzes, badges, progress, leaderboard | Authenticated |
| **Sharing** | `ShareButton` / `QuoteCard` | Share story to social platforms | All |
| **Admin** | `AdminDashboardScreen` | Analytics, moderation, growth | Admin / Manager |

### 2.3 Key End-to-End Navigation Flows

- **Onboarding → Home**: `RegisterScreen`/`LoginScreen` → `AuthWrapper` detects
  `authenticated` → renders `HomeScreen`.
- **Home → Artifact Detail**: (QR scan OR deep link) → `ArtifactDetailScreen`.
- **Home → Story Detail**: `HomeScreen` → `StoriesScreen` → `StoryDetailScreen`
  (markdown reader with live reading-progress %).
- **Story → Learn**: `StoryDetailScreen` → quiz (`GamificationScreen`) →
  badges/certificate.
- **Story → Media**: `StoryDetailScreen` → TTS audio sheet / AI video sheet.

---

## 3. Data Models & APIs

### 3.1 Backend App Structure (Django `LOCAL_APPS`)

| Django App | Purpose |
|------------|---------|
| `users` | Custom User model, JWT auth, roles, delete-account |
| `stories` | Stories, categories, bookmarks, likes, flags, reading progress, shares |
| `qr_codes` | Artifacts, QR code generation, scan tracking, deep links |
| `gamification` | Quizzes, attempts, badges, user profiles, certificates, leaderboard |
| `media_app` | AI video generation (Luma AI), TTS narration jobs |
| `api` | Health probes, analytics dashboard, observability middleware, seeding |

### 3.2 Core Entities & Fields

#### `users.User` (custom, `AUTH_USER_MODEL`)
- Extends Django `AbstractUser`.
- `role` — `visitor | contributor | institution_manager | admin`
- `institution` — optional museum/archive name (for managers).
- Helpers: `is_visitor`, `is_contributor`, `is_institution_manager`,
  `is_admin_role`, `role_display`.

#### `stories.*`
- **`Story`** — `title`, `slug`, `content` (Markdown), `summary`, `author`,
  `co_authors`, `categories` (M2M), `language` (`en/fr/ful/dua/ewo/bml/other`),
  `region`, `tags`, `cover_image`, `cover_image_blurhash`, `audio_url`,
  `video_url`, `cultural_context`, `moral_lesson`, `source`,
  `estimated_read_time`, `status` (`draft/pending/published/rejected/archived`),
  `reviewer_notes`, `view_count`, `like_count`, `bookmark_count`,
  `share_count`, timestamps.
- **`StoryCategory`** — `name`, `slug`, `description`, `icon`, `color`.
- **`StoryBookmark`** — `user` + `story` (unique), `note`.
- **`StoryLike`** — `user` + `story` (unique).
- **`StoryFlag`** — `reason`, `details`, `resolved`, `resolution_notes`.
- **`ReadingProgress`** — `progress_percent`, `last_read_position`, `completed`.
- **`StoryShare`** — `platform` (twitter/facebook/whatsapp/telegram/link/other).

#### `qr_codes.Artifact`
- `title`, `slug`, `description`, `category`
  (`sculpture/textile/instrument/jewelry/pottery/mask/weapon/fabric/tool/other`),
  `created_by`, `culture`, `region`, `estimated_date`, `materials`,
  `dimensions`, `image`, `image_blurhash`, `additional_images`,
  `qr_code_url`, `qr_code_svg`, `deep_link_path`, `stories` (M2M),
  `museum_name`, `floor`, `display_case`, `is_published`.
- **`QRCodeScan`** — `artifact`, `user`, `device_type`, `ip_address`,
  `user_agent`, `latitude`, `longitude`.

#### `gamification.*`
- **`Quiz`** — one-to-one with `Story`, `passing_score`, `time_limit_minutes`.
- **`QuizQuestion`** — options A–D, `correct_answer`, `explanation`, `difficulty`.
- **`QuizAttempt`** — `score`, `correct_count`, `passed`, `xp_earned`, `answers` (JSON).
- **`Badge`** / **`UserBadge`** — achievements (reading/quiz/social/exploration/special).
- **`UserProfile`** — `total_xp`, `level`, streaks, stories read/completed.
- **`Certificate`** — heritage certificates with `pdf_url`, `certificate_number`.

#### `media_app.*`
- **`VideoGenerationJob`** — Luma AI Dream Machine job (`luma_job_id`,
  `prompt`, `status`, `video_url`, `thumbnail_url`, `duration`).
- **`AudioNarrationJob`** — TTS job (`voice_id`, `language`, `speed`,
  `audio_url`, `duration`, `file_size`).

#### Client-side local cache (`AppDatabase` → SQLite/IndexedDB)
- `story_cache` — offline stories (title, category, region, content_markdown,
  hero_image_path, audio_path, video_url, is_favorite).
- `search_history` — local fuzzy-search history.
- `reading_progress` — `scroll_fraction`, `audio_resume_seconds`.

### 3.3 API Endpoints

All under `/api/`. JWT auth via SimpleJWT; default pagination (20/page).

#### Auth & Users (`users`)
| Method | Path | Description | Access |
|--------|------|-------------|--------|
| POST | `/api/auth/token/` | Obtain JWT access+refresh | Public |
| POST | `/api/auth/token/refresh/` | Refresh access token | Public |
| POST | `/api/auth/register/` | Create account | Public |
| GET | `/api/users/me/` | Current user profile | Authenticated |

#### Stories (`stories`)
| Method | Path | Description | Access |
|--------|------|-------------|--------|
| GET/POST | `/api/stories/` | List / create | List: All; Create: Contributor+ |
| GET/PUT/PATCH/DELETE | `/api/stories/{slug}/` | Detail / update / delete | Owner/Manager/Admin |
| GET | `/api/stories/categories/` | List categories | Public |
| GET | `/api/stories/my/` | Current user's stories | Authenticated |
| GET | `/api/stories/bookmarks/` | User bookmarks | Authenticated |
| GET | `/api/stories/recently-read/` | Recently read | Authenticated |
| GET | `/api/stories/continue-reading/` | In-progress stories | Authenticated |
| GET | `/api/stories/trending/` / `popular/` / `discover/` | Curation feeds | Public |
| GET | `/api/stories/moderation-queue/` | Flagged stories (grouped) | Admin/Manager |
| POST | `/api/stories/{slug}/bookmark/` | Toggle bookmark | Authenticated |
| POST | `/api/stories/{slug}/like/` | Toggle like | Authenticated |
| POST | `/api/stories/{slug}/flag/` | Flag for review | Authenticated |
| POST | `/api/stories/{slug}/moderate/` | Remove/dismiss flags | Admin/Manager |
| POST | `/api/stories/{slug}/progress/` | Update reading progress | Authenticated |
| POST | `/api/stories/{slug}/share/` | Track a share | Public/Auth |

**Query params (list):** `search`, `language`, `category`, `region`, `sort`.

#### QR Codes / Artifacts (`qr_codes`)
| Method | Path | Description | Access |
|--------|------|-------------|--------|
| GET/POST | `/api/artifacts/` | List / create artifacts | List: Public; Create: Manager/Admin |
| GET/PUT/DELETE | `/api/artifacts/{pk}/` | Artifact detail / update / delete | Manager/Admin |
| GET | `/api/artifacts/lookup/` | Lookup artifact by deep link | Public |
| GET | `/api/qr/{slug}/` | QR redirect to artifact | Public |

#### Gamification (`gamification`)
| Method | Path | Description | Access |
|--------|------|-------------|--------|
| CRUD | `/api/gamification/quizzes/` | Quizzes | Read: All; Write: Admin |
| CRUD | `/api/gamification/attempts/` | Quiz attempts | Authenticated |
| CRUD | `/api/gamification/badges/` | Badges | Read: All; Write: Admin |
| CRUD | `/api/gamification/user-badges/` | Earned badges | Authenticated |
| CRUD | `/api/gamification/certificates/` | Certificates | Authenticated/Admin |
| GET | `/api/gamification/profile/` | User gamification profile | Authenticated |
| GET | `/api/gamification/leaderboard/` | Leaderboard | Authenticated |

#### Media (`media_app`)
| Method | Path | Description | Access |
|--------|------|-------------|--------|
| CRUD | `/api/media/videos/` | AI video generation jobs | Contributor+ |
| CRUD | `/api/media/audio/` | TTS narration jobs | Contributor+ |
| GET | `/api/media/status/{job_type}/{job_id}/` | Poll job status | Owner/Admin |

#### Analytics (`api`)
| Method | Path | Description | Access |
|--------|------|-------------|--------|
| GET | `/api/analytics/dashboard/` | Dashboard summary | Admin |
| GET | `/api/analytics/users/` | User analytics | Admin |
| GET | `/api/analytics/stories/` | Story analytics | Admin |
| GET | `/api/analytics/gamification/` | Gamification analytics | Admin |
| GET | `/api/analytics/qr-codes/` | QR scan analytics | Admin |
| GET | `/api/analytics/engagement/` | Engagement analytics | Admin |

#### Health / Observability (`api`)
| GET | `/api/health/` | Liveness probe | Public |
| GET | `/api/health/ready/` | Readiness probe | Public |
| GET | `/api/health/metrics/` | Metrics | Public |

---

## 4. Key User Flows

### 4.1 Sign-Up / Onboarding
1. User opens app → `AuthWrapper` shows `LoginScreen`.
2. User taps "Create account" → `RegisterScreen`.
3. `POST /api/auth/register/` creates a `User` with default role `visitor`.
4. Client stores JWT pair (access + refresh) via `AuthRepository`.
5. `AuthWrapper` flips to `authenticated` → `HomeScreen`.

### 4.2 Search & Discovery
1. On `HomeScreen`/`StoriesScreen`, user searches by keyword.
2. `GET /api/stories/?search=...` (title/content/summary/tags) with optional
   `language`, `category`, `region`, `sort` filters.
3. Search queries are also stored locally in `search_history` for fuzzy
   suggestion.
4. Users can drill into curated feeds: `trending`, `popular`, `discover`.

### 4.3 Save / Collect (Bookmarks & Library)
1. On `StoryDetailScreen`, user taps bookmark → `POST /api/stories/{slug}/bookmark/`.
2. Reading progress is saved continuously via
   `POST /api/stories/{slug}/progress/` (scroll %).
3. `LibraryScreen` surfaces **Continue Reading**, **Recently Read**, and
   **Bookmarked** collections from `library_api_service`.

### 4.4 Offline Viewing
1. User saves a story to offline cache (`story_cache` table in local SQLite /
   IndexedDB) via `story_cache_repository`.
2. Offline content includes title, category, region, markdown content, hero
   image path, audio path, video URL.
3. `OfflineStoryCounter` on the home screen shows the number of cached stories.
4. When offline, the reader falls back to the cached markdown instead of the
   network.
5. Reading progress is also mirrored locally (`reading_progress` table) and
   synced when back online.

### 4.5 Artifact QR Scan
1. User scans a museum QR code (or opens a deep link `/artifact/<slug>`).
2. Client calls `GET /api/artifacts/lookup/` (deep link) or uses the scanned
   ID/slug.
3. `ArtifactDetailScreen` shows artifact info + related stories; scan is
   recorded in `QRCodeScan` for analytics.

### 4.6 Gamification & Certification
1. After reading, user takes a quiz (`QuizAttempt`).
2. Score is calculated; passing awards XP and updates `UserProfile.level`.
3. Earning badges (+XP) and completing milestones issues a `Certificate`.

---

## 5. Roles & Authentication

### 5.1 Authentication
- **JWT (SimpleJWT)** — access token 30 min, refresh 7 days, rotation +
  blacklist enabled.
- `AuthInterceptor` on the Flutter client auto-injects the `Bearer` token and
  refreshes on `401`.
- Throttling: auth endpoints `5/min` per IP; anonymous API `120/min`;
  authenticated `600/min`.

### 5.2 Roles (application-level `user.role`)

| Role | Identifier | Capabilities |
|------|-----------|--------------|
| **Visitor** | `visitor` | Browse, read, listen, scan QR, take quizzes, earn badges (Explorer Mode). Guests can also browse public content. |
| **Contributor** | `contributor` | All Visitor abilities + create/edit own stories, generate AI video/audio. |
| **Institution Manager** | `institution_manager` | Manage museum artifacts & QR codes, moderate content (flag resolution), view some analytics. |
| **Admin** | `admin` | Full platform administration, moderation queue, analytics dashboard, content management. |

> Note: `role` is the *application* role; Django's `is_staff`/`is_superuser`
> remain separate flags for the Django admin site.

### 5.3 Guest vs. Logged-In
- **Guest (unauthenticated):** can list/read published stories, view
  categories, artifacts, curated feeds, and health endpoints. Cannot create,
  bookmark, like, save, or see personalized library.
- **Logged-in:** full read + write (per role) + personalization (library,
  progress, gamification profile).

### 5.4 Permission Enforcement (backend `views.py`)
- `IsContributorOrAbove` — story creation.
- `IsStoryOwnerOrReadOnly` — edit/delete own stories (managers/admins override).
- `IsAdminOrManager` — moderation + analytics.
- Per-action `get_permissions()` in `StoryViewSet` maps actions→permissions.

---

## 6. Frontend Feature Modules (Flutter)

```
lib/
├── main.dart                     # Entry, Sentry init, runApp
├── app.dart                      # MaterialApp, theme, localizations, AuthWrapper
├── core/
│   ├── constants/  app_constants.dart
│   ├── database/   app_database.dart, models/, repositories/
│   ├── network/    api_client.dart (Dio), auth_interceptor.dart
│   ├── providers/  (Riverpod providers)
│   └── theme/      app_colors, app_theme, app_typography
└── features/
    ├── auth/       login, register, profile, auth_wrapper, role_badge
    ├── home/       home_screen, offline_story_counter
    ├── stories/    stories_screen, story_detail_screen, story_form_screen
    ├── library/    library_screen, continue_reading_widget
    ├── qr_scanner/ qr_scanner_widget, artifact_detail_screen
    ├── audio/      audio_player_sheet, audio_player_service
    ├── video/      video_generation_sheet, video_player_widget
    ├── gamification/ gamification_screen, quiz_player_widget, badge_card
    ├── sharing/    share_button, quote_card, trending_stories_widget
    └── admin/      admin_dashboard_screen, analytics models, services
```

Each feature exposes a `*_feature.dart` barrel file (models, providers,
repositories/services, screens, widgets) following a consistent convention.

---

## 7. Constraints

### 7.1 Platforms
- **Frontend:** Flutter → **iOS**, **Android**, and **Web (PWA)**. Mobile uses
  `sqflite` for local storage; the web client swaps to **IndexedDB**.
- **Backend:** Django REST Framework (Python), deployed via WSGI/ASGI.

### 7.2 Existing Design System
- Shared theme defined in Flutter (`AppTheme.light/dark`) with a custom
  **African heritage palette**:
  - `AppColors.terracotta` / `terracottaDark`
  - `AppColors.ochre` / `ochreTint`
  - `AppColors.savannahGreen`
  - `AppColors.error`
- Custom typography (`AppTypography`), emoji-based icons/category glyphs, and
  QR scanner overlays with **traditional border motifs**.
- Dark/light mode follows the system theme (togglable in-app via
  `settingsProvider`).

### 7.3 Localization
- Flutter `flutter_localizations` with delegates for Material, Widgets,
  Cupertino.
- Supported locales: **English (`en`)** and **French (`fr`)**.
- Story content supports multiple languages (`en/fr/ful/dua/ewo/bml/other`),
  and TTS narration is language-aware.

### 7.4 Networking & Resilience
- `ApiClient` uses **Dio** with:
  - exponential-backoff retry (1s → 3s → 7s, 3 attempts);
  - auth interceptor for token injection/refresh;
  - base URL injected via `--dart-define=API_BASE_URL`.
- Offline-first caching for the reading experience.

### 7.5 Observability & Ops
- **Sentry** (Flutter) for error monitoring, DSN via `--dart-define=SENTRY_DSN`.
- Backend structured JSON logging (`api.logging.JsonFormatter`,
  `RequestLogMiddleware`).
- Health liveness/readiness/metrics endpoints for deployment probes.
- Admin analytics views for monitoring engagement.

---

## 8. Repository Layout

```
├── backend/                 # Django REST Framework API
│   ├── config/              # settings (base/dev/prod/test), urls, wsgi/asgi
│   ├── users/               # custom User, JWT auth, roles
│   ├── stories/             # stories, bookmarks, flags, progress, categories
│   ├── qr_codes/            # artifacts, QR generation, scans, deep links
│   ├── gamification/        # quizzes, badges, profiles, certificates
│   ├── media_app/           # Luma AI video, TTS narration
│   └── api/                 # health, analytics, logging, middleware, seeding
├── frontend/                # Flutter app (iOS / Android / Web PWA)
│   ├── lib/                 # core/ + features/
│   ├── test/                # widget + model tests
│   └── web|android|ios/     # platform shells
└── UI model/                # design mockups
```

---

## 9. Deployment & Settings Environments

Backend settings are split by environment in `config/settings/`:
- `base.py` — shared config (apps, JWT, DRF, throttling, logging, DB).
- `dev.py` — development overrides (DEBUG on, SQLite, media serving).
- `prod.py` — production overrides (Postgres swap, allowed hosts, static).
- `test.py` — test database/runtime.

Database: **SQLite** by default (Phase 1); **Postgres** is the target for
production (swap `ENGINE` in `prod.py`).
