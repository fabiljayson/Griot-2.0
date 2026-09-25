# Component Diagram — Griot 2.0

## High-Level System Components

```mermaid
flowchart TB
    subgraph "Flutter Client Application"
        direction TB

        subgraph "UI Layer"
            Screens["Screens<br/>(Login, Home, Stories,<br/>StoryDetail, Library,<br/>QR Scanner, Gamification,<br/>Admin Dashboard)"]
            Widgets["Reusable Widgets<br/>(StoryCard, BadgeCard,<br/>QuizPlayer, AudioPlayer,<br/>VideoPlayer, ShareButton)"]
        end

        subgraph "State Management"
            Riverpod["Riverpod Providers<br/>(Auth, Story, Library,<br/>Gamification, Admin,<br/>Audio, Video, QR)"]
        end

        subgraph "Feature Services"
            AuthSvc["AuthService<br/>(Online-first JWT login,<br/>offline fallback)"]
            StorySvc["StoryService<br/>(CRUD, Search,<br/>Bookmarks, Likes; mirror)"]
            LibrarySvc["LibraryService<br/>(Continue Reading,<br/>Recently Read) — SQLite"]
            GamificationSvc["GamificationService<br/>(Quizzes, Badges) — SQLite"]
            QRSvc["QRService<br/>(Scanner, Artifact Lookup)"]
            AudioSvc["AudioService<br/>(TTS Playback,<br/>Offline Audio)"]
            VideoSvc["VideoService<br/>(Generation, Polling,<br/>Playback)"]
            ShareSvc["SharingService<br/>(Social Share,<br/>Quote Cards)"]
            AdminSvc["AdminService<br/>(Analytics, Users List,<br/>Moderation)"]
            ArtifactsSvc["ArtifactsService<br/>(Catalogue browse)"]
            DiscoverSvc["DiscoverService<br/>(Region stories)"]
            SettingsSvc["SettingsService<br/>(WhatsApp feedback)"]
        end

        subgraph "Core Infrastructure"
            APIClient["ApiClient<br/>(Dio + Interceptors)"]
            AuthInterceptor["AuthInterceptor<br/>(Bearer Token,<br/>Auto-Refresh)"]
            OfflineInterceptor["OfflineQueueInterceptor<br/>(Request Queuing)"]
            ConnectivitySvc["ConnectivityService<br/>(Online/Offline<br/>Detection)"]
            OfflineSync["OfflineSyncManager<br/>(Background Sync)"]
            LocalDB["AppDatabase<br/>(SQLite / IndexedDB)"]
            CacheRepos["Cache Repositories<br/>(Story, ReadingProgress,<br/>SearchHistory, Offline)"]
        end
    end

    subgraph "Django REST Framework API"
        direction TB

        subgraph "Authentication"
            JWTAuth["SimpleJWT<br/>(Token Obtain,<br/>Refresh, Blacklist)"]
            RolePerms["Role-Based Permissions<br/>(IsContributorOrAbove,<br/>IsAdminOrManager)"]
            Throttling["Rate Throttling<br/>(auth: 5/min ·<br/>anon: 120/min · user: 600/min)"]
        end

        subgraph "Business Logic"
            UserMgmt["User Management<br/>(Register, Profile,<br/>Delete Account)"]
            StoryEngine["Story Engine<br/>(CRUD, Search,<br/>Categories, Feeds)"]
            ContentMod["Content Moderation<br/>(Flag, Review,<br/>Resolve)"]
            QRModule["QR Code Module<br/>(Artifacts, QR Gen,<br/>Scan Tracking)"]
            GameEngine["Gamification Engine<br/>(Quizzes, Badges,<br/>XP, Certificates)"]
            MediaEngine["Media Engine<br/>(AI Video, TTS)"]
            AnalyticsEngine["Analytics Engine<br/>(Dashboard, Metrics,<br/>Engagement)"]
        end

        subgraph "Infrastructure"
            HealthCheck["Health Probes<br/>(Liveness, Readiness,<br/>Metrics)"]
            StructLog["Structured Logging<br/>(JSON Formatter,<br/>Request Middleware)"]
            SeedCmds["Seed Commands<br/>(Users, Stories, QR,<br/>Gamification)"]
        end
    end

    subgraph "External Services"
        LumaAI["🎬 Luma AI<br/>Dream Machine<br/>(Video Generation)"]
        TTSProvider["🔊 Google TTS via gTTS<br/>(Text-to-Speech,<br/>no API key)"]
        SentryMonitor["🐛 Sentry<br/>(Error Monitoring,<br/>DSN-gated)"]
        WhatsApp["💬 WhatsApp<br/>(feedback wa.me link)"]
    end

    subgraph "Data Layer"
        SQLite["SQLite<br/>(db.sqlite3 — dev / local)"]
        PostgreSQL["PostgreSQL 16<br/>(Render griot-db — prod)"]
        Crawler["Crawler (ingestion)<br/>discover-cameroon.com<br/>→ cameroon_content.json<br/>→ import_crawl_data"]
        MediaStorage["Media<br/>(Django /media/ on<br/>Render disk / local)"]
    end

    %% ─── Client Internal Connections ───────────────────
    Screens --> Widgets
    Screens --> Riverpod
    Widgets --> Riverpod
    Riverpod --> AuthSvc
    Riverpod --> StorySvc
    Riverpod --> LibrarySvc
    Riverpod --> GamificationSvc
    Riverpod --> QRSvc
    Riverpod --> AudioSvc
    Riverpod --> VideoSvc
    Riverpod --> ShareSvc
    Riverpod --> AdminSvc
    Riverpod --> ArtifactsSvc
    Riverpod --> DiscoverSvc
    Riverpod --> SettingsSvc

    AuthSvc --> APIClient
    StorySvc --> APIClient
    LibrarySvc --> LocalDB
    GamificationSvc --> LocalDB
    QRSvc --> APIClient
    AudioSvc --> APIClient
    VideoSvc --> APIClient
    ShareSvc --> APIClient
    AdminSvc --> APIClient
    ArtifactsSvc --> APIClient
    DiscoverSvc --> APIClient
    SettingsSvc --> WhatsApp

    APIClient --> AuthInterceptor
    APIClient --> OfflineInterceptor
    AuthInterceptor --> APIClient
    OfflineInterceptor --> ConnectivitySvc
    ConnectivitySvc --> OfflineSync
    OfflineSync --> APIClient
    APIClient --> LocalDB
    LocalDB --> CacheRepos

    %% ─── Client to Server ─────────────────────────────
    APIClient -- "HTTPS/JSON" --> JWTAuth

    %% ─── Server Internal Connections ──────────────────
    JWTAuth --> RolePerms
    JWTAuth --> Throttling

    UserMgmt --> JWTAuth
    StoryEngine --> RolePerms
    ContentMod --> RolePerms
    QRModule --> RolePerms
    GameEngine --> RolePerms
    MediaEngine --> RolePerms
    AnalyticsEngine --> RolePerms

    StoryEngine --> SQLite
    QRModule --> SQLite
    GameEngine --> SQLite
    MediaEngine --> SQLite
    AnalyticsEngine --> SQLite
    QRModule --> Crawler : import_crawl_data

    StoryEngine --> MediaStorage
    QRModule --> MediaStorage
    Crawler --> MediaStorage

    %% ─── External Services ────────────────────────────
    MediaEngine --> LumaAI
    MediaEngine --> TTSProvider
    APIClient -- "Sentry (client)" --> SentryMonitor
    AnalyticsEngine --> SentryMonitor
```

## Component Communication Matrix

| Component | Connects To | Protocol | Description |
|---|---|---|---|
| **Flutter UI** | Riverpod | Internal | State observation |
| **Riverpod** | Feature Services | Internal | State mutation |
| **Feature Services** | ApiClient | Internal | API calls (auth, stories, qr, audio, video, share, admin, artifacts, discover) |
| **Library / Gamification Service** | AppDatabase | Internal | **Local SQLite** — no HTTP |
| **Settings Service** | WhatsApp | wa.me deep link | Feedback chat, no backend endpoint |
| **ApiClient** | AuthInterceptor | Internal | Token injection |
| **ApiClient** | OfflineInterceptor | Internal | Offline queuing |
| **ConnectivityService** | OfflineSyncManager | Internal | Connectivity events |
| **ApiClient** | Django REST API | HTTPS/JSON | HTTP requests |
| **SimpleJWT** | User Model | Internal | Token generation |
| **Role Permissions** | User Model | Internal | Authorization check |
| **Story Engine** | Story Model | Internal | CRUD operations |
| **Media Engine** | Luma AI API | REST API | Video generation |
| **Media Engine** | gTTS | REST API | Audio narration |
| **QR Code Module** | Crawler | File import | `import_crawl_data` command ingests `cameroon_content.json` |
| **ApiClient** | Sentry | SDK | Client-side error reporting (DSN-gated) |
| **All Backend Apps** | Database | SQL | `default` (Postgres prod / SQLite dev) + `local` alias |
| **Backend Apps** | Media | Filesystem | Django `/media/` (no S3/GCS) |

## Interface Contracts

### Client → Server API

| Interface | Method | Content Type | Auth Required |
|---|---|---|---|
| Login (`/api/auth/token/`) | POST | JSON | No (throttled 5/min) |
| Register (`/api/auth/register/`) | POST | JSON | No (throttled 5/min) |
| Refresh (`/api/auth/token/refresh/`) | POST | JSON | Refresh token (rotated + blacklisted) |
| Current User (`/api/users/me/`) | GET | JSON | Yes (JWT) |
| Stories List (`/api/stories/`) | GET | JSON | Read-only (IsAuthenticatedOrReadOnly) |
| Story Detail | GET | JSON | No |
| Create Story | POST | JSON | Yes (Contributor+) |
| Moderation Queue (`/api/stories/moderation_queue/`) | GET | JSON | Yes (Admin/Manager) |
| Moderate (`.../moderate/`) | POST | JSON | Yes (Admin/Manager) |
| Flag | POST | JSON | Yes |
| Bookmark | POST | JSON | Yes |
| Like | POST | JSON | Yes |
| Progress (`/api/stories/slug/progress/`) | POST | JSON | Yes — **local-first**, best-effort sync |
| Audio Narration (`/api/media/story/slug/audio/`) | POST | JSON | Yes (Authenticated; published story) |
| Video Generate (`/api/media/story/slug/video/`) | POST | JSON | Yes (Contributor+) |
| Video / Poll (`/api/media/video/task-id/`) | GET | JSON | Yes |
| QR Lookup (`/api/artifacts/lookup/`) | GET | JSON | No |
| Quiz Start / Submit / Finish (`/api/gamification/...`) | POST | JSON | Yes — **web client only** (mobile = local SQLite) |
| Analytics Dashboard / lists (`/api/analytics/...`) | GET | JSON | Yes (Admin/Manager — IsAdminOrManager) |
| Platform Users List (`/api/analytics/users/list/`) | GET | JSON | Yes (Admin/Manager) |
| Health (`/api/health/`, `ready/`, `metrics/`) | GET | JSON | No |
| Schema / Docs / Redoc | GET | JSON/HTML | No |

### Server → External Services

| Interface | Method | Service | Description |
|---|---|---|---|
| Video Generation | POST | Luma AI API | Submit video job (`LUMA_API_KEY` gated; mock fallback) |
| Video Status | GET | Luma AI API | Poll job status |
| TTS Generation | POST | gTTS (Google Translate endpoint) | Audio narration — no API key |
| Error Report | SDK | Sentry | **Client-side** (Flutter); backend DSN optional |
