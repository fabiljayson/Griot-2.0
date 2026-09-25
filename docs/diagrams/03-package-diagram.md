# Package Diagram — Griot 2.0

> **Updated 2026-09-23** to match the implementation: added `core/debug`,
> `core/navigation`, `core/widgets`, the `settings`, `artifacts` and `discover`
> features, the backend `web.services` module, the crawler as an ingestion
> component, and corrected the gamification/library data flow (local SQLite,
> **not** HTTP). Sentry is a Flutter-side dependency (DSN-gated).

## System Package Structure

```mermaid
packageDiagram
    title Griot 2.0 — Package Diagram

    package "Flutter Client" {
        package "core" {
            package "constants" {
                class AppConstants
                class PreRegisteredAccounts
            }
            package "database" {
                class AppDatabase
                class LocalAuthRepository
                class LocalStoryRepository
                class LocalGamificationRepository
                class LocalLibraryRepository
                class OfflineRequestRepository
                class OfflineUserRepository
                class StoryCacheRepository
                class ReadingProgressRepository
                class SearchHistoryRepository
            }
            package "debug" {
                class DebugLog
            }
            package "navigation" {
                class AppRouter
                class MainShell
                class AppDeepLink
                class AuthPageRoute
            }
            package "network" {
                class ApiClient
                class AuthInterceptor
                class RetryInterceptor
                class ConnectivityService
                class OfflineSyncManager
                class AppError
                class HttpUtils
            }
            package "offline" {
                class OfflineProvider
                class OfflineFeature
                class OfflineErrorBuffer
            }
            package "providers" {
                class DatabaseProviders
                class OnboardingProvider
            }
            package "theme" {
                class AppColors
                class AppTheme
                class AppTypography
            }
            package "widgets" {
                class BrandWidgets
                class GriotImage
                class GriotLoader
                class AuthFormWidgets
            }
        }

        package "features" {
            package "auth" {
                class LoginScreen
                class RegisterScreen
                class ProfileScreen
                class AuthWrapper
                class AuthProvider
                class AuthRepository
                class ServerAuthRepository
                class LocalAuthRepository
            }
            package "home" {
                class HomeScreen
                class ConnectivityStatusWidget
                class OfflineStoryCounter
            }
            package "stories" {
                class StoriesScreen
                class StoryDetailScreen
                class StoryFormScreen
                class StoryCard
                class StoryActions
            }
            package "library" {
                class LibraryScreen
                class ContinueReadingWidget
                class LibraryApiService
            }
            package "qr_scanner" {
                class QRScannerWidget
                class ArtifactDetailScreen
                class QrApiService
            }
            package "audio" {
                class AudioPlayerSheet
                class AudioPlayerService
                class OfflineAudioService
            }
            package "video" {
                class VideoGenerationSheet
                class VideoPlayerWidget
                class VideoStatusPoller
                class VideoApiService
            }
            package "gamification" {
                class GamificationScreen
                class QuizScreen
                class QuizPlayerWidget
                class BadgeCard
                class GamificationApiService
            }
            package "sharing" {
                class ShareSheet
                class QuoteCard
                class SharingService
            }
            package "settings" {
                class SettingsScreen
                class WhatsAppFeedbackService
            }
            package "artifacts" {
                class ArtifactsScreen
                class ArtifactCard
                class ArtifactsProvider
            }
            package "discover" {
                class RegionStoryScreen
                class RegionCard
                class RegionProvider
                class RegionModel
            }
            package "admin" {
                class AdminDashboardScreen
                class AdminApiService
                class GrowthChart
                class ModerationWidgets
                class StatCard
            }
        }
    }

    package "Django REST API" {
        package "users" {
            class User
            class UserRole
            class RegisterView
            class MeView
            class AuthTokenRefreshView
            class CustomTokenObtainPairView
        }
        package "stories" {
            class Story
            class StoryCategory
            class StoryBookmark
            class StoryLike
            class StoryFlag
            class StoryShare
            class ReadingProgress
            class StoryViewSet
        }
        package "qr_codes" {
            class Artifact
            class QRCodeScan
            class QRCodeGenerator
        }
        package "gamification" {
            class Quiz
            class QuizQuestion
            class QuizAttempt
            class Badge
            class UserBadge
            class UserProfile
            class Certificate
        }
        package "media_app" {
            class VideoGenerationJob
            class AudioNarrationJob
            class LumaAIService
            class TtsService
            class BlurhashUtils
        }
        package "api" {
            class HealthViews
            class AdminUsersListView
            class AnalyticsViews
            class JsonFormatter
            class RequestLogMiddleware
            class SeedAllCommand
        }
        package "web" {
            class WebViews
            class WebActions
            class WebServices
            class WebTemplates
        }
    }

    package "Crawler (ingestion tool)" {
        package "crawler" {
            class Config
            class Session
            class Utils
            class Extractors
            class Images
            class Runner
        }
    }

    package "External Services" {
        class LumaAiAPI
        class TTSProvider  %% gTTS via Google Translate public endpoint
        class Sentry  %% Flutter client only (DSN-gated)
        class WhatsApp   %% wa.me deep link from settings
    }

    %% ─── Frontend dependencies ──────────────────────────
    core ..> features : used by
    features.auth ..> core.network : online-first (JWT via ApiClient)
    features.stories ..> core.network : online-first + SQLite mirror
    features.library ..> core.database : LOCAL SQLite facade
    features.qr_scanner ..> core.network : API lookup + record scan
    features.audio ..> core.network : /api/media/audio + status
    features.audio ..> core.database : offline audio cache
    features.video ..> core.network : /api/media/videos + status
    features.gamification ..> core.database : LOCAL SQLite facade
    features.sharing ..> core.network : /api/stories/{slug}/share
    features.admin ..> core.network : /api/analytics/*
    features.artifacts ..> core.network : /api/artifacts
    features.discover ..> core.network : /api/categories
    features.settings ..> WhatsApp : wa.me chat (url_launcher)
    core.network ..> core.database : offline queue
    core.offline ..> Sentry : error reporting (client)

    %% ─── Backend / external ─────────────────────────────
    core.network ..> Django REST API : HTTPS
    media_app ..> LumaAiAPI : REST (mock if no LUMA_API_KEY)
    media_app ..> TTSProvider : gTTS (no key required)
    crawler ..> CrawlSource : discover-cameroon.com → cameroon_content.json
    crawler ..> Django REST API : import_crawl_data command → Artifact
```

## Package Dependency Summary

| Frontend Package | Depends On | External APIs / Notes |
|---|---|---|
| `core.network` | `core.database`, `core.offline` | Django REST API (Dio + auth/retry/offline interceptor) |
| `features.auth` | `core.network`, `core.database` | `/api/auth/*`, `/api/users/me/` (online-first, offline fallback) |
| `features.stories` | `core.network`, `core.database` | `/api/stories/*` with SQLite offline mirror |
| `features.library` | `core.database` | **Local SQLite** (`LibraryApiService` → `LocalLibraryRepository`) |
| `features.qr_scanner` | `core.network` | `/api/artifacts/*`, `/api/artifacts/lookup/` |
| `features.audio` | `core.network`, `core.database` | `/api/media/audio/*`, status; offline cache |
| `features.video` | `core.network` | `/api/media/videos/*`, `/api/media/status/video/{id}/` |
| `features.gamification` | `core.database` | **Local SQLite** (`GamificationApiService` → `LocalGamificationRepository`); leaderboard hardcoded `[]` |
| `features.sharing` | `core.network` | `/api/stories/{slug}/share/` |
| `features.admin` | `core.network` | `/api/analytics/*`, `/api/stories/moderation_queue/` |
| `features.artifacts` | `core.network` | `/api/artifacts/` catalogue browse |
| `features.discover` | `core.network` | `/api/categories/` mapped to regions |
| `features.settings` | `url_launcher` | `wa.me` WhatsApp feedback — no backend endpoint |
| `core.offline` | `core.database` | Sentry DSN-gated error reporting |

| Backend Django App | Models / Classes | External Services |
|---|---|---|
| `users` | User, UserRole, CustomTokenObtainPairView, AuthTokenRefreshView, RegisterView, MeView | SimpleJWT (30m / 7d, rotate + blacklist) |
| `stories` | Story, Category, Bookmark, Like, Flag, Share, ReadingProgress | — |
| `qr_codes` | Artifact, QRCodeScan, QRCodeGenerator | — |
| `gamification` | Quiz, Question, Attempt, Badge, UserProfile, Certificate | — |
| `media_app` | VideoGenerationJob, AudioNarrationJob, LumaAIService, TtsService | Luma AI (mock fallback), gTTS |
| `web` | WebUserSettings, WebViews/WebActions/WebServices | — (server-rendered UI over the same models) |
| `api` | HealthViews, AdminUsersListView, AnalyticsViews, JsonFormatter, RequestLogMiddleware | — |
| `crawler` (tool) | Config, Session, Utils, Extractors, Images, Runner | discover-cameroon.com → `backend/data/cameroon_content.json` |