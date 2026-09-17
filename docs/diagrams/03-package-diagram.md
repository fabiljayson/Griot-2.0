# Package Diagram — Griot 2.0

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
                class StoryCacheRepository
                class OfflineRequestRepository
                class OfflineUserRepository
                class ReadingProgressRepository
                class SearchHistoryRepository
            }
            package "network" {
                class ApiClient
                class AuthInterceptor
                class ConnectivityService
                class OfflineSyncManager
                class HttpUtils
            }
            package "offline" {
                class OfflineProvider
                class OfflineErrorBuffer
            }
            package "providers" {
                class DatabaseProviders
                class SettingsProviders
            }
            package "theme" {
                class AppColors
                class AppTheme
                class AppTypography
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
                class QuizPlayerWidget
                class BadgeCard
                class GamificationApiService
            }
            package "sharing" {
                class ShareButton
                class QuoteCard
                class TrendingStoriesWidget
                class SharingService
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
            class TokenObtainPairView
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
            class QRGenerator
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
            class LumaAiService
            class TtsService
        }
        package "api" {
            class HealthViews
            class AnalyticsViews
            class JsonFormatter
            class RequestLogMiddleware
            class SeedCommands
        }
        package "web" {
            class WebViews
            class WebActions
            class WebTemplates
        }
    }

    package "External Services" {
        class LumaAiAPI
        class TTSProvider
        class Sentry
    }

    %% ─── Dependencies ─────────────────────────────────────
    core ..> features : used by
    features.auth ..> core.network : HTTP
    features.stories ..> core.network : HTTP
    features.library ..> core.network : HTTP
    features.qr_scanner ..> core.network : HTTP
    features.audio ..> core.network : HTTP
    features.video ..> core.network : HTTP
    features.gamification ..> core.network : HTTP
    features.sharing ..> core.network : HTTP
    features.admin ..> core.network : HTTP
    core.network ..> core.database : offline queue

    core.network ..> Django REST API : HTTPS
    media_app ..> LumaAiAPI : REST
    media_app ..> TTSProvider : REST
    core.offline ..> Sentry : error reporting
```

## Package Dependency Summary

| Frontend Package | Depends On | External APIs |
|---|---|---|
| `core.network` | `core.database`, `core.offline` | Django REST API |
| `features.auth` | `core.network` | `/api/auth/*` |
| `features.stories` | `core.network` | `/api/stories/*` |
| `features.library` | `core.network` | `/api/stories/my/` |
| `features.qr_scanner` | `core.network` | `/api/artifacts/*` |
| `features.audio` | `core.network` | `/api/media/audio/*` |
| `features.video` | `core.network` | `/api/media/videos/*` |
| `features.gamification` | `core.network` | `/api/gamification/*` |
| `features.sharing` | `core.network` | `/api/stories/{slug}/share/` |
| `features.admin` | `core.network` | `/api/analytics/*` |

| Backend Django App | Models | External Services |
|---|---|---|
| `users` | User, UserRole | SimpleJWT |
| `stories` | Story, Category, Bookmark, Like, Flag, Share, ReadingProgress | — |
| `qr_codes` | Artifact, QRCodeScan | QR Generator |
| `gamification` | Quiz, Question, Attempt, Badge, UserProfile, Certificate | — |
| `media_app` | VideoGenerationJob, AudioNarrationJob | Luma AI, TTS Provider |
| `web` | WebUserSettings | — (server-rendered UI over the same models) |
| `api` | — | Sentry |
