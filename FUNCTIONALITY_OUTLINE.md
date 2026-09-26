# Griot 2.0 — African Teller: Complete Functionality Outline

> *A cross-platform digital heritage platform preserving and sharing Cameroon's oral traditions.*
> *A griot (ˈɡriː.oʊ) is a West African storyteller, praise-singer, and keeper of oral history.*

**Platforms:** iOS · Android · Web (PWA) · Django REST Framework API

---

## Table of Contents

1. [Authentication & User Management](#1--authentication--user-management)
2. [Stories & Storytelling](#2--stories--storytelling)
3. [Library & Personalization](#3--library--personalization)
4. [Offline-First Architecture](#4--offline-first-architecture)
5. [QR Code & Museum Artifacts](#5--qr-code--museum-artifacts)
6. [Audio Narration (TTS)](#6--audio-narration-tts)
7. [AI Video Generation](#7--ai-video-generation)
8. [Gamification & Certification](#8--gamification--certification)
9. [Social Sharing](#9--social-sharing)
10. [Admin Dashboard & Analytics](#10--admin-dashboard--analytics)
11. [Theme & UI](#11--theme--ui)
12. [Networking & Infrastructure](#12--networking--infrastructure)
13. [Data Seeding](#13--data-seeding)
14. [Deployment & Environments](#14--deployment--environments)
15. [Summary](#15--summary)

---

## 1. 🔐 Authentication & User Management

| Feature | Details |
|---|---|
| **Registration** | Email + username sign-up with role assignment (default: `visitor`) |
| **Login / Logout** | JWT access + refresh tokens (30 min access, 7 day refresh) |
| **Token Refresh** | Automatic silent refresh via `AuthInterceptor` on 401 responses |
| **User Roles** | 4-tier RBAC: `visitor` → `contributor` → `institution_manager` → `admin` |
| **Profile Screen** | View/edit profile, see role badge |
| **Role-Based Access** | Guest users can browse public content; logged-in users get write/feature access based on role |
| **Pre-registered Accounts** | Support for seeded pre-registered test accounts |
| **Offline Auth** | Offline user registration queue (`offline_users` table) that syncs when back online |
| **Throttling** | Auth endpoints: 5/min per IP; anonymous: 120/min; authenticated: 600/min |

### Role Capabilities

| Role | Capabilities |
|---|---|
| **Visitor** | Browse, read, listen, scan QR, take quizzes, earn badges (Explorer Mode). Guests can also browse public content. |
| **Contributor** | All Visitor abilities + create/edit own stories, generate AI video/audio. |
| **Institution Manager** | Manage museum artifacts & QR codes, moderate content (flag resolution), view some analytics. |
| **Admin** | Full platform administration, moderation queue, analytics dashboard, content management. |

### API Endpoints

| Method | Path | Description | Access |
|--------|------|-------------|--------|
| POST | `/api/auth/token/` | Obtain JWT access+refresh | Public |
| POST | `/api/auth/token/refresh/` | Refresh access token | Public |
| POST | `/api/auth/register/` | Create account | Public |
| GET | `/api/users/me/` | Current user profile | Authenticated |

---

## 2. 📖 Stories & Storytelling

| Feature | Details |
|---|---|
| **Story Repository** | Digital library of cultural tales from Cameroon & Central Africa |
| **Multi-Language Support** | Stories in `en`, `fr`, `ful`, `dua`, `ewo`, `bml`, and more |
| **Markdown Reader** | Rich story content rendered from Markdown with reading progress tracking |
| **Story Categories** | Categorized tales with emoji icons and color coding |
| **Region Filtering** | Filter stories by geographic/cultural region |
| **Story Detail Screen** | Full story view with author info, cultural context, moral lesson, source attribution |
| **Story Creation/Editing** | Contributors+ can create and edit stories via `StoryFormScreen` |
| **Story Cards** | Beautiful cards with cover images, blurhash placeholders, read time estimates |
| **Search & Discovery** | Fuzzy text search across title/content/summary/tags with language, category, region filters |
| **Curated Feeds** | Trending, Popular, and Discover story feeds |
| **Cover Images** | Story cover images with blurhash for lazy loading |

### Story Interactions

| Interaction | Details |
|---|---|
| **Bookmarking** | Toggle bookmark with optional notes; bookmarks visible in Library |
| **Liking** | Toggle like; tracks `like_count` |
| **Flagging** | Report inappropriate content with reason and details |
| **Reading Progress** | Continuous scroll % saved; resume where you left off |
| **Share Tracking** | Track shares across platforms (Twitter, Facebook, WhatsApp, Telegram, link) |
| **View Counting** | Tracks story views for analytics |

### Story Data Model Fields

- **Story** — `title`, `slug`, `content` (Markdown), `summary`, `author`, `co_authors`, `categories` (M2M), `language`, `region`, `tags`, `cover_image`, `cover_image_blurhash`, `audio_url`, `video_url`, `cultural_context`, `moral_lesson`, `source`, `estimated_read_time`, `status` (`draft/pending/published/rejected/archived`), `reviewer_notes`, `view_count`, `like_count`, `bookmark_count`, `share_count`, timestamps.
- **StoryCategory** — `name`, `slug`, `description`, `icon`, `color`.
- **StoryBookmark** — `user` + `story` (unique), `note`.
- **StoryLike** — `user` + `story` (unique).
- **StoryFlag** — `reason`, `details`, `resolved`, `resolution_notes`.
- **ReadingProgress** — `progress_percent`, `last_read_position`, `completed`.
- **StoryShare** — `platform` (twitter/facebook/whatsapp/telegram/link/other).

### API Endpoints

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

---

## 3. 📚 Library & Personalization

| Feature | Details |
|---|---|
| **Library Screen** | Personal reading hub |
| **Continue Reading** | Stories with saved progress, showing % completion |
| **Recently Read** | Chronological list of recently accessed stories |
| **Bookmarked Stories** | All bookmarked stories in one place |
| **My Stories** | Contributors can see their own submitted stories |

---

## 4. 📱 Offline-First Architecture

| Feature | Details |
|---|---|
| **Story Cache** | Save stories to local SQLite (mobile) / IndexedDB (web) |
| **Offline Reader** | Read cached stories without internet |
| **Offline Counter** | Home screen widget shows number of cached stories |
| **Reading Progress Sync** | Local progress synced when back online |
| **Offline Request Queue** | Non-GET API calls queued in `offline_requests` table for retry |
| **Offline User Registration** | User registrations queued in `offline_users` table |
| **Connectivity Monitoring** | Real-time connectivity status widget; auto-detects online/offline transitions |
| **Sync Manager** | `OfflineSyncManager` handles background synchronization |
| **Offline Error Buffer** | `OfflineErrorBuffer` persists errors to disk for later reporting |
| **Offline Audio** | Cached audio playback when offline |
| **Offline Video** | Cached video playback when offline |

### Client-Side Local Cache (SQLite on mobile; IndexedDB-backed on web via sqflite_common_ffi_web)

| Table | Purpose |
|---|---|
| `story_cache` | Offline stories (title, category, region, content_markdown, hero_image_path, audio_path, video_url, is_favorite) |
| `search_history` | Local fuzzy-search history |
| `reading_progress` | `scroll_fraction`, `audio_resume_seconds` |
| `offline_requests` | Queued API calls with retry logic |
| `offline_users` | Queued user registrations |

---

## 5. 🎫 QR Code & Museum Artifacts

| Feature | Details |
|---|---|
| **QR Scanner** | In-app QR code scanner for museum artifact codes |
| **Artifact Catalog** | Digital catalog of cultural artifacts |
| **Artifact Detail Screen** | Full artifact info: title, story, audio, video |
| **Deep Linking** | `/artifacts/<slug>` deep links for QR codes and shared links |
| **Auto QR Generation** | QR codes auto-generated on artifact save (PNG format) |
| **QR Scan Tracking** | Records device type, IP, user agent per scan |
| **Crawl Data Import** | 127 artifacts imported from discover-cameroon.com |
| **Mobile-First Design** | Optimized QR landing page for smartphone scans |

### Artifact Data Model Fields

- **Artifact (new `artifacts` app)** — `title`, `slug`, `category` (`kingdom/landmark/artifact/legend/culture`), `location`, `story` (narrative text), `historical_significance`, `source_url`, `audio_file` (optional), `video_url` (optional), `qr_code` (auto-generated PNG).
- **Artifact (existing `qr_codes` app)** — `title`, `slug`, `description`, `category` (`sculpture/textile/instrument/jewelry/pottery/mask/weapon/fabric/tool/other`), `created_by`, `culture`, `region`, `estimated_date`, `materials`, `dimensions`, `image`, `image_blurhash`, `additional_images`, `qr_code_url`, `qr_code_svg`, `deep_link_path`, `stories` (M2M), `museum_name`, `floor`, `display_case`, `is_published`.
- **QRCodeScan** — `artifact`, `user`, `device_type`, `ip_address`, `user_agent`, `latitude`, `longitude`.

### API Endpoints

| Method | Path | Description | Access |
|--------|------|-------------|--------|
| GET/POST | `/api/artifacts/` | List / create artifacts | List: Public; Create: Manager/Admin |
| GET/PUT/DELETE | `/api/artifacts/{pk}/` | Artifact detail / update / delete | Manager/Admin |
| GET | `/api/artifacts/lookup/` | Lookup artifact by deep link | Public |
| GET | `/api/qr/{slug}/` | QR redirect to artifact | Public |

---

## 6. 🎵 Audio Narration (TTS)

| Feature | Details |
|---|---|
| **Text-to-Speech** | AI-generated audio narration of stories |
| **Audio Player Sheet** | Bottom-sheet audio player with controls |
| **Language-Aware TTS** | Voice selection based on story language |
| **Voice Selection** | Choose from available TTS voices |
| **Speed Control** | Adjustable narration speed |
| **Offline Audio** | Cached audio playback when offline |
| **Audio Resume** | Resume from last listening position |
| **Duration Tracking** | Audio file size and duration metadata |

### AudioNarrationJob Data Model

- `voice_id`, `language`, `speed`, `audio_url`, `duration`, `file_size`, `status`, `artifact` (FK).

### API Endpoints

| Method | Path | Description | Access |
|--------|------|-------------|--------|
| CRUD | `/api/media/audio/` | TTS narration jobs | Contributor+ |
| GET | `/api/media/status/{job_type}/{job_id}/` | Poll job status | Owner/Admin |

---

## 7. 🎬 AI Video Generation

| Feature | Details |
|---|---|
| **Luma AI Integration** | AI-generated story videos via Luma Dream Machine |
| **Video Generation Sheet** | UI to create video from story content with custom prompts |
| **Video Player Widget** | Native video playback with controls |
| **Status Polling** | Real-time job status tracking (pending → processing → complete) |
| **Status Badge** | Visual indicator of video generation progress |
| **Thumbnail** | Auto-generated video thumbnails |
| **Offline Video** | Cached video playback when offline |
| **Contributor-Only** | Video generation requires contributor role or above |

### VideoGenerationJob Data Model

- `luma_job_id`, `prompt`, `status`, `video_url`, `thumbnail_url`, `duration`.

### API Endpoints

| Method | Path | Description | Access |
|--------|------|-------------|--------|
| CRUD | `/api/media/videos/` | AI video generation jobs | Contributor+ |
| GET | `/api/media/status/{job_type}/{job_id}/` | Poll job status | Owner/Admin |

---

## 8. 🏆 Gamification & Certification

| Feature | Details |
|---|---|
| **Quizzes** | Multiple-choice quizzes per story (A–D options) with correct answers and explanations |
| **Quiz Player Widget** | Interactive quiz-taking interface with timer |
| **XP System** | Earn experience points for reading, quizzes, social interactions |
| **Leveling** | User level progression based on total XP |
| **Badges** | Achievement badges across categories: Reading, Quiz, Social, Exploration, Special |
| **Badge Cards** | Visual badge display with icons and descriptions |
| **Leaderboard** | Ranked user leaderboard by XP |
| **Certificates** | Heritage certificates with unique certificate numbers and PDF export |
| **Passing Score** | Configurable quiz passing thresholds |
| **Difficulty Levels** | Quiz questions tagged by difficulty |

### Gamification Data Models

- **Quiz** — one-to-one with `Story`, `passing_score`, `time_limit_minutes`.
- **QuizQuestion** — options A–D, `correct_answer`, `explanation`, `difficulty`.
- **QuizAttempt** — `score`, `correct_count`, `passed`, `xp_earned`, `answers` (JSON).
- **Badge** / **UserBadge** — achievements (reading/quiz/social/exploration/special).
- **UserProfile** — `total_xp`, `level`, streaks, stories read/completed,
  `timezone` (IANA zone deciding which calendar day activity counts on).
- **Certificate** — heritage certificates with `pdf_url`, `certificate_number`.

### API Endpoints

| Method | Path | Description | Access |
|--------|------|-------------|--------|
| CRUD | `/api/gamification/quizzes/` | Quizzes | Read: All; Write: Admin |
| CRUD | `/api/gamification/attempts/` | Quiz attempts | Authenticated |
| CRUD | `/api/gamification/badges/` | Badges | Read: All; Write: Admin |
| CRUD | `/api/gamification/user-badges/` | Earned badges | Authenticated |
| CRUD | `/api/gamification/certificates/` | Certificates | Authenticated/Admin |
| GET | `/api/gamification/profile/` | User gamification profile | Authenticated |
| POST | `/api/gamification/activity/` | Count today as active; returns the profile and syncs the inbox | Authenticated |
| GET | `/api/gamification/leaderboard/` | Leaderboard | Authenticated |

---

### 🔔 Notifications

The reader inbox, alongside gamification because the daily streak nudge and the
activity ping that delivers it are the same feature.

| Feature | Details |
|---|---|
| **Notification Bell** | Home header bell with an unread badge (capped at 99+) |
| **Inbox** | Newest-first list grouped by day, with per-kind icons and unread dots |
| **New Story Alerts** | Sent when a story becomes published, keyed so a re-publish never doubles up |
| **Trending Digest** | Weekly recap of the most-engaged stories, one per reader per ISO week |
| **Streak Nudges** | Daily reminder when a live streak is about to expire, once per reader-local day |
| **Announcements** | Admin broadcasts land in every active reader's inbox |
| **Offline Behaviour** | None by design — a message is only shown if the server sent it |

#### API Endpoints

| Method | Path | Description | Access |
|--------|------|-------------|--------|
| GET | `/api/notifications/` | Inbox, newest first, with the unread count | Owner |
| GET | `/api/notifications/{id}/` | Single message | Owner |
| PATCH | `/api/notifications/{id}/` | Mark read (cannot be un-read) | Owner |
| GET | `/api/notifications/unread-count/` | Badge count only | Owner |
| POST | `/api/notifications/{id}/mark-read/` | Mark one message read | Owner |
| POST | `/api/notifications/mark-all-read/` | Clear the badge | Owner |
| POST | `/api/notifications/broadcast/` | Send an announcement to every active reader | Admin |

---

## 9. 🌐 Social Sharing

| Feature | Details |
|---|---|
| **Share Button** | Native share dialog |
| **Quote Card** | Beautifully designed shareable quote cards |
| **Platform Support** | Twitter, Facebook, WhatsApp, Telegram, copy link |
| **Trending Stories Widget** | Displays currently trending/popular stories |
| **Share Tracking** | Server-side tracking of shares by platform |

---

## 10. 👨‍💼 Admin Dashboard & Analytics

| Feature | Details |
|---|---|
| **Admin Dashboard** | Central admin screen with analytics overview |
| **Stat Cards** | Key metrics at a glance |
| **Growth Charts** | Visual growth trends |
| **Moderation Queue** | Review flagged stories grouped by reason |
| **Moderation Actions** | Remove or dismiss content flags with resolution notes |
| **Ranked Tiles** | Top-performing content/users ranking |

### Analytics Endpoints

| Method | Path | Description | Access |
|--------|------|-------------|--------|
| GET | `/api/analytics/dashboard/` | Dashboard summary | Admin |
| GET | `/api/analytics/users/` | User analytics | Admin |
| GET | `/api/analytics/stories/` | Story analytics | Admin |
| GET | `/api/analytics/gamification/` | Gamification analytics | Admin |
| GET | `/api/analytics/qr-codes/` | QR scan analytics | Admin |
| GET | `/api/analytics/engagement/` | Engagement analytics | Admin |

---

## 11. 🌓 Theme & UI

| Feature | Details |
|---|---|
| **Cameroonian Heritage Palette** | Culturally resonant, WCAG 2.1 AA compliant colors |
| **Dark / Light Mode** | System-following theme with in-app toggle |
| **Custom Typography** | Fraunces + Plus Jakarta Sans fonts |
| **Emoji Icons** | Emoji-based category glyphs |
| **QR Scanner Overlay** | Traditional African border motif overlay |
| **Role Badges** | Visual role indicators (Visitor, Contributor, Manager, Admin) |
| **Localization** | English + French UI; multi-language story content |
| **Responsive Design** | Mobile-first with web/PWA adaptation |

### Color Palette

| Color | Hex | CSS Class | Usage |
|---|---|---|---|
| 🟦 | `#1E2B58` | `cam-indigo` | Primary headers, navigation |
| 🟨 | `#C68B29` | `cam-bronze` | CTAs, active states, audio controls |
| 🟥 | `#A0382B` | `cam-earth` | Historical alerts, badges |
| 🟩 | `#1B4332` | `cam-green` | Success states, location tags |
| ⬜ | `#FBF9F4` | `cam-ivory` | Background canvas (60%) |
| ⬜ | `#FFFFFF` | `cam-white` | Cards, surfaces (30%) |
| ⬛ | `#1C1C1E` | `cam-dark` | Body text |

### Supported Locales

| Code | Language |
|---|---|
| `en` | English |
| `fr` | French |
| `ful` | Fulfulde |
| `dua` | Duala |
| `ewo` | Ewondo |
| `bml` | Bamileke |

---

## 12. 🔌 Networking & Infrastructure

| Feature | Details |
|---|---|
| **Dio HTTP Client** | Shared client with interceptors |
| **Exponential Backoff Retry** | 1s → 3s → 7s, 3 attempts |
| **Auth Interceptor** | Auto Bearer token injection and refresh |
| **Ngrok Support** | Physical device testing via ngrok tunnel |
| **Base URL Config** | `--dart-define=API_BASE_URL=...` |
| **Sentry Monitoring** | Error tracking via `--dart-define=SENTRY_DSN=...` |
| **Health Probes** | `/api/health/`, `/api/health/ready/`, `/api/health/metrics/` |
| **Structured Logging** | JSON-formatted request/response logs |
| **Request Logging Middleware** | Middleware captures all API requests |
| **Offline Queue Interceptor** | Dio interceptor that queues non-GET requests when offline |

### Health / Observability API Endpoints

| Method | Path | Description | Access |
|--------|------|-------------|--------|
| GET | `/api/health/` | Liveness probe | Public |
| GET | `/api/health/ready/` | Readiness probe | Public |
| GET | `/api/health/metrics/` | Metrics | Public |

### Frontend Feature Modules Structure

```
frontend/lib/
├── main.dart                          # Entry point, Sentry init
├── app.dart                           # MaterialApp, theme, localizations, AuthWrapper
├── core/
│   ├── constants/                     # app_constants, pre_registered_accounts
│   ├── database/                      # SQLite/IndexedDB, models, repositories
│   ├── network/                       # Dio client, auth interceptor, connectivity, offline sync
│   ├── offline/                       # Offline provider, error buffer, feature
│   ├── providers/                     # Riverpod providers
│   └── theme/                         # Colors, typography, themes
└── features/
    ├── admin/                         # Dashboard, analytics, moderation
    ├── audio/                         # TTS, audio player
    ├── auth/                          # Login, register, profile, role badge
    ├── gamification/                  # Quizzes, badges, leaderboard
    ├── home/                          # Home screen, connectivity widget
    ├── library/                       # Continue reading, bookmarks
    ├── notifications/                # Bell badge, inbox, activity ping
    ├── qr_scanner/                    # QR scanner, artifact detail
    ├── sharing/                       # Share button, quote card, trending
    ├── stories/                       # Story list, detail, form
    └── video/                         # Video generation, player
```

### Backend Django Apps Structure

```
backend/
├── config/                            # Settings (base/dev/prod/test), urls, wsgi/asgi
├── users/                             # Custom User model, JWT auth, roles
├── stories/                           # Stories, categories, bookmarks, flags, progress
├── qr_codes/                          # Artifacts, QR generation, scans, deep links
├── gamification/                      # Quizzes, badges, profiles, certificates
├── media_app/                         # Luma AI video, TTS narration
└── api/                               # Health, analytics, logging, middleware, seeding
```

---

## 13. 🗃️ Data Seeding

| Management Command | Purpose |
|---|---|
| `seed_all` | Master seeding command (runs all below) |
| `seed_users` | Pre-registered user accounts |
| `seed_stories` | Sample cultural stories with categories |
| `seed_qr_codes` | Museum artifact records with QR codes |
| `seed_gamification` | Quizzes, badges, certificates |
| `seed_narrations` | TTS narration job records |

---

## 14. 🚀 Deployment & Environments

| Environment | Config File | Database | Notes |
|---|---|---|---|
| **Development** | `config/settings/dev.py` | SQLite | DEBUG=True, media serving, ngrok support |
| **Production** | `config/settings/prod.py` | PostgreSQL | Static files, optimized settings |
| **Test** | `config/settings/test.py` | Test DB | Isolated test environment |

### Environment Variables / dart-defines

| Variable | Purpose |
|---|---|
| `API_BASE_URL` | Backend API base URL |
| `NGROK_URL` | Ngrok tunnel URL for physical device testing |
| `SENTRY_DSN` | Sentry error monitoring DSN |

---

## 15. 📊 Summary

### By the Numbers

| Category | Count |
|---|---|
| **Backend Django Apps** | 6 (users, stories, qr_codes, gamification, media_app, api) |
| **Frontend Feature Modules** | 10 (auth, home, stories, library, qr_scanner, audio, video, gamification, sharing, admin) |
| **API Endpoint Groups** | 8 (auth, stories, artifacts, gamification, media, analytics, health, sharing) |
| **Data Models** | 20+ (User, Story, Category, Bookmark, Like, Flag, Progress, Share, Artifact, QRScan, Quiz, Question, Attempt, Badge, UserProfile, Certificate, VideoJob, AudioJob, etc.) |
| **Offline Features** | 7 (story cache, request queue, user queue, connectivity monitor, sync manager, error buffer, offline audio/video) |
| **Supported Languages** | 6 (en, fr, ful, dua, ewo, bml) |
| **Quiz Badge Categories** | 5 (Reading, Quiz, Social, Exploration, Special) |
| **Platforms** | 3 (iOS, Android, Web/PWA) |

### Roadmap Phases

| Phase | Focus |
|---|---|
| 1 | Project setup & baseline architecture |
| 2 | Auth, user roles & compliance |
| 3 | Storytelling, repository & reader engine |
| 4 | Media, AI video (Luma AI) & resilient networking |
| 5 | Museum QR code engine & deep linking |
| 6 | Gamification, quizzes & certification |
| 7 | Personalization, library & reading progress |
| 8 | Social sharing & content discovery |
| 9 | Cross-platform PWA & web adaptation |
| 10 | Observability, data seeding & deployment |

---

*Generated from codebase analysis on August 10, 2026.*
