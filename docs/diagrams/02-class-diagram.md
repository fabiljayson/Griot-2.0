# Class Diagram — Griot 2.0

## Backend Models (Django)

```mermaid
classDiagram
    title Griot 2.0 — Backend Class Diagram

    %% ─── Users ────────────────────────────────────────────
    class User {
        +int id
        +String username
        +String email
        +String password
        +String first_name
        +String last_name
        +String role: UserRole
        +String institution
        +bool is_staff
        +bool is_superuser
        +DateTime date_joined
        +is_visitor() bool
        +is_contributor() bool
        +is_institution_manager() bool
        +is_admin_role() bool
        +role_display() String
    }

    class UserRole {
        <<enumeration>>
        VISITOR = 'visitor'
        CONTRIBUTOR = 'contributor'
        INSTITUTION_MANAGER = 'institution_manager'
        ADMIN = 'admin'
    }

    User --> UserRole : has

    %% ─── Stories ──────────────────────────────────────────
    class Story {
        +int id
        +String title
        +String slug
        +String content
        +String summary
        +String language: Language
        +String region
        +String tags
        +ImageField cover_image
        +String cover_image_blurhash
        +String audio_url
        +String video_url
        +String cultural_context
        +String moral_lesson
        +String source
        +int estimated_read_time
        +String status: Status
        +String reviewer_notes
        +int view_count
        +int like_count
        +int bookmark_count
        +int share_count
        +DateTime created_at
        +DateTime updated_at
        +DateTime published_at
        +is_published() bool
        +tag_list() List
    }

    class StoryStatus {
        <<enumeration>>
        DRAFT = 'draft'
        PENDING = 'pending'
        PUBLISHED = 'published'
        REJECTED = 'rejected'
        ARCHIVED = 'archived'
    }

    class StoryLanguage {
        <<enumeration>>
        ENGLISH = 'en'
        FRENCH = 'fr'
        FULA = 'ful'
        DUALA = 'dua'
        EWONDO = 'ewo'
        BAMILEKE = 'bml'
        OTHER = 'other'
    }

    class StoryCategory {
        +int id
        +String name
        +String slug
        +String description
        +String icon
        +String color
        +DateTime created_at
    }

    class StoryBookmark {
        +int id
        +User user
        +Story story
        +DateTime created_at
        +String note
    }

    class StoryLike {
        +int id
        +User user
        +Story story
        +DateTime created_at
    }

    class StoryFlag {
        +int id
        +User user
        +Story story
        +String reason: Reason
        +String details
        +DateTime created_at
        +bool resolved
        +String resolution_notes
    }

    class StoryShare {
        +int id
        +Story story
        +User user
        +String platform
        +String ip_address
        +DateTime created_at
    }

    class ReadingProgress {
        +int id
        +User user
        +Story story
        +int progress_percent
        +int last_read_position
        +bool completed
        +DateTime created_at
        +DateTime updated_at
        +is_complete() bool
    }

    Story --> StoryStatus : has
    Story --> StoryLanguage : has
    User "1" --> "*" Story : authors
    User "1" --> "*" StoryBookmark : creates
    Story "1" --> "*" StoryBookmark : has
    User "1" --> "*" StoryLike : creates
    Story "1" --> "*" StoryLike : has
    User "1" --> "*" StoryFlag : creates
    Story "1" --> "*" StoryFlag : has
    Story "1" --> "*" StoryShare : has
    User "1" --> "*" ReadingProgress : tracks
    Story "1" --> "*" ReadingProgress : has
    StoryCategory "1" --> "*" Story : categorizes
    Story "*" --> "*" StoryCategory : belongs_to

    %% ─── QR Codes & Artifacts ─────────────────────────────
    class Artifact {
        +int id
        +String title
        +String slug
        +String description
        +String category: Category
        +User created_by
        +String culture
        +String region
        +String estimated_date
        +String materials
        +String dimensions
        +ImageField image
        +String image_blurhash
        +List additional_images
        +String qr_code_url
        +String qr_code_svg
        +String deep_link_path
        +String museum_name
        +String floor
        +String display_case
        +bool is_published
        +DateTime created_at
        +DateTime updated_at
        +qr_deep_link() String
    }

    class ArtifactCategory {
        <<enumeration>>
        SCULPTURE
        TEXTILE
        INSTRUMENT
        JEWELRY
        POTTERY
        MASK
        WEAPON
        FABRIC
        TOOL
        OTHER
    }

    class QRCodeScan {
        +int id
        +Artifact artifact
        +User user
        +String device_type
        +String ip_address
        +String user_agent
        +float latitude
        +float longitude
        +DateTime created_at
    }

    Artifact --> ArtifactCategory : has
    User "1" --> "*" Artifact : creates
    Artifact "1" --> "*" QRCodeScan : has
    User "1" --> "*" QRCodeScan : performs
    Artifact "*" --> "*" Story : related_stories

    %% ─── Gamification ─────────────────────────────────────
    class Quiz {
        +int id
        +Story story
        +String title
        +String description
        +int passing_score
        +int time_limit_minutes
        +bool is_published
        +DateTime created_at
        +DateTime updated_at
        +question_count() int
        +xp_reward() int
    }

    class QuizQuestion {
        +int id
        +Quiz quiz
        +String question_text
        +String option_a
        +String option_b
        +String option_c
        +String option_d
        +String correct_answer
        +String explanation
        +String difficulty: Difficulty
        +int order
    }

    class QuizAttempt {
        +int id
        +User user
        +Quiz quiz
        +int score
        +int correct_count
        +int total_questions
        +bool passed
        +int xp_earned
        +String status: Status
        +JSON answers
        +DateTime started_at
        +DateTime completed_at
        +int time_taken_seconds
        +calculate_score() int
    }

    class Badge {
        +int id
        +String name
        +String slug
        +String description
        +String emoji
        +String category: Category
        +int xp_required
        +int stories_read_required
        +int quizzes_passed_required
        +String color
        +String icon_url
        +bool is_active
        +bool is_secret
        +DateTime created_at
    }

    class UserBadge {
        +int id
        +User user
        +Badge badge
        +DateTime earned_at
    }

    class UserProfile {
        +int id
        +User user
        +int total_xp
        +int level
        +int stories_read
        +int stories_completed
        +int quizzes_passed
        +int total_quiz_xp
        +int current_streak
        +int longest_streak
        +Date last_active_date
        +DateTime created_at
        +DateTime updated_at
        +xp_for_next_level() int
        +xp_progress() float
        +add_xp(amount) void
        +update_streak() void
    }

    class Certificate {
        +int id
        +User user
        +String certificate_type: Type
        +String title
        +String description
        +DateTime issued_at
        +String certificate_number
        +int stories_read
        +int quizzes_passed
        +int level_achieved
        +String pdf_url
    }

    Quiz "1" --> "1" Story : tied_to
    Quiz "1" --> "*" QuizQuestion : contains
    User "1" --> "*" QuizAttempt : attempts
    Quiz "1" --> "*" QuizAttempt : has
    User "1" --> "*" UserBadge : earns
    Badge "1" --> "*" UserBadge : granted_as
    User "1" --> "1" UserProfile : has
    User "1" --> "*" Certificate : receives

    %% ─── Media ────────────────────────────────────────────
    class VideoGenerationJob {
        +int id
        +User user
        +Story story
        +String luma_job_id
        +String prompt
        +String luma_request_id
        +String status: Status
        +int progress_percent
        +String video_url
        +String thumbnail_url
        +int duration
        +String error_message
        +DateTime created_at
        +DateTime updated_at
        +DateTime started_at
        +DateTime completed_at
        +is_ready() bool
        +is_processing() bool
    }

    class AudioNarrationJob {
        +int id
        +User user
        +Story story
        +Artifact artifact
        +String narration_text
        +String voice_id
        +String language
        +float speed
        +String status: Status
        +FileField audio_file
        +String audio_url
        +int duration
        +int file_size
        +String error_message
        +DateTime created_at
        +DateTime updated_at
        +DateTime completed_at
        +is_ready() bool
    }

    class JobStatus {
        <<enumeration>>
        PENDING = 'pending'
        PROCESSING = 'processing'
        COMPLETED = 'completed'
        FAILED = 'failed'
    }

    User "1" --> "*" VideoGenerationJob : creates
    Story "1" --> "*" VideoGenerationJob : has
    User "1" --> "*" AudioNarrationJob : creates
    Story "1" --> "*" AudioNarrationJob : has
    Artifact "1" --> "*" AudioNarrationJob : has
    VideoGenerationJob --> JobStatus : has
    AudioNarrationJob --> JobStatus : has
```

## Frontend Classes (Flutter/Dart)

```mermaid
classDiagram
    title Griot 2.0 — Frontend Class Diagram

    %% ─── Core ─────────────────────────────────────────────
    class ApiClient {
        +Dio dio
        -OfflineRequestRepository _offlineRepository
        -ConnectivityService _connectivityService
        +static ApiClient instance
        +static ApiClient withAuth()
        +queueOfflineRequest() Future
    }

    class AuthInterceptor {
        -AuthRepository _authRepo
        -bool _isRefreshing
        +onRequest() void
        +onError() void
    }

    class ConnectivityService {
        -Connectivity _connectivity
        -OfflineRequestRepository _offlineRepository
        -StreamController _connectivityController
        -bool _isOnline
        +bool isOnline
        +Stream connectivityStream
        +initialize() void
        +dispose() void
    }

    class OfflineSyncManager {
        -OfflineRequestRepository _offlineRepository
        -ApiClient _apiClient
        -ConnectivityService _connectivityService
        -bool _isSyncing
        +initialize() void
        +triggerSync() Future
        +dispose() void
    }

    class OfflineQueueInterceptor {
        -OfflineRequestRepository _offlineRepository
        -ConnectivityService _connectivityService
        +onRequest() void
    }

    ApiClient --> AuthInterceptor : uses
    ApiClient --> OfflineQueueInterceptor : uses
    ApiClient --> ConnectivityService : depends
    OfflineSyncManager --> ConnectivityService : listens
    OfflineSyncManager --> ApiClient : replays requests
    OfflineSyncManager --> OfflineRequestRepository : reads queue

    %% ─── Auth ─────────────────────────────────────────────
    class AuthRepository {
        +Future~String~ accessToken
        +Future refreshTokens() void
        +Future clearTokens() void
    }

    class AuthProvider {
        +AsyncValue authState
        +login() Future
        +register() Future
        +logout() void
    }

    class AuthWrapper {
        +Widget child
        +build() Widget
    }

    class UserModel {
        +int id
        +String username
        +String email
        +String firstName
        +String lastName
        +String role
        +String institution
    }

    AuthProvider --> AuthRepository : uses
    AuthWrapper --> AuthProvider : watches
    AuthInterceptor --> AuthRepository : uses

    %% ─── Stories ──────────────────────────────────────────
    class StoryModel {
        +int id
        +String slug
        +String title
        +String summary
        +String content
        +UserModel author
        +String language
        +String region
        +List categories
        +String coverImage
        +String audioUrl
        +String videoUrl
        +int estimatedReadTime
        +bool isBookmarked
    }

    class StoryListNotifier {
        +StoryListState state
        +loadStories() Future
        +refresh() Future
        +loadMore() Future
        -_loadFromCache() Future
    }

    class StoryRepository {
        +fetchStories() Future
        +searchStories() Future
        +toggleBookmark() Future
        +toggleLike() Future
    }

    StoryListNotifier --> StoryRepository : uses
    StoryRepository --> ApiClient : HTTP calls

    %% ─── Gamification ─────────────────────────────────────
    class GamificationScreen {
        +build() Widget
    }

    class QuizPlayerWidget {
        +Quiz quiz
        +build() Widget
    }

    class BadgeCard {
        +Badge badge
        +bool earned
        +build() Widget
    }

    GamificationScreen --> QuizPlayerWidget : contains
    GamificationScreen --> BadgeCard : displays
```
