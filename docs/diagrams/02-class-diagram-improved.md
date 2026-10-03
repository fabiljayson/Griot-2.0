# Class Diagram — Griot 2.0 (improved)

> **Derived from `02-class-diagram.md`.** That file is the source of truth and
> is **not** replaced by this one. Every class, attribute, operation,
> relationship, stereotype and enumeration from it is preserved here, including
> its wording and its *member written without parentheses means `@property` or
> Dart getter* convention.
>
> **Three rules decided what was added.**
>
> 1. **Reuse before adding.** Where the brief asks for a class the project
>    already has under another name, the existing one is reused and the mapping
>    is recorded rather than a second class being invented.
> 2. **Every added member is grounded in the source.** New classes that
>    describe code that exists (`Notification`, the nine undeclared Flutter
>    classes, the story consent/provenance fields) carry the members the code
>    actually has. Classes that describe *not-yet-built* features are marked
>    `<<proposed>>` and carry only the attributes the brief specifies.
> 3. **Nothing existing is deleted.** Legacy fields kept for data migration are
>    shown struck through in intent (see `Artifact`) and explained in the
>    accompanying report.
>
> **Counting is reproducible.** The report that accompanies this file states
> class, attribute, operation, association and generalization counts. Those
> numbers are produced by `docs/diagrams/count_diagram_elements.py`, not
> asserted:
>
> ```bash
> python3 docs/diagrams/count_diagram_elements.py docs/diagrams/02-class-diagram-improved.md
> ```
>
> The Mermaid blocks additionally validate through the project's existing
> UML pipeline (`~/tools/mermaid2modelio`), which reports type/relationship
> counts and errors per block.

---

## Backend domain (Django)

Grouped into the packages requested by the brief. Grouping is presentational —
every one of these classes is a concrete Django model or enum in this
codebase, and the namespaces map onto the Django apps.

```mermaid
classDiagram
    title Griot 2.0 — Backend Domain (Django)

    namespace Core {
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
            +is_visitor bool
            +is_contributor bool
            +is_institution_manager bool
            +is_admin_role bool
            +role_display String
        }

        %% proposed — not implemented yet

        class UserRole {
            <<enumeration>>
            VISITOR = 'visitor'
            CONTRIBUTOR = 'contributor'
            INSTITUTION_MANAGER = 'institution_manager'
            ADMIN = 'admin'
        }
    }

    namespace Story {
        class Story {
            +int id
            +String title
            +String slug
            +String content
            +String summary
            +String language: StoryLanguage
            +String region
            +String tags
            +List co_authors
            +ImageField cover_image
            +String cover_image_blurhash
            +String audio_url
            +String video_url
            +String cultural_context
            +String moral_lesson
            +String source
            +int estimated_read_time
            +String status: StoryStatus
            +String reviewer_notes
            +int view_count
            +int like_count
            +int bookmark_count
            +int share_count
            +DateTime created_at
            +DateTime updated_at
            +DateTime published_at
            +is_published bool
            +tag_list List
            +String origin: StoryOrigin
            +String provenance_notes
            +String consent_status: StoryConsent
            +User consent_attested_by
            +DateTime consent_attested_at
            +String consent_basis
            +String rights_holder
            +String licence: StoryLicence
            +Date recorded_at
            +translation_for(code) StoryTranslation
        }

        class StoryTranslation {
            <<proposed>>
            +int id
            +Story story
            +String language: StoryLanguage
            +String title
            +Text content
            +String summary
            +String cultural_context
            +String moral_lesson
            +String translator_note
            +User translated_by
            +DateTime created_at
            +DateTime updated_at
        }

        %% proposed — not implemented yet

        class StoryStatus {
            <<enumeration>>
            DRAFT = 'draft'
            PENDING = 'pending'
            PUBLISHED = 'published'
            REJECTED = 'rejected'
            ARCHIVED = 'archived'
        }

        %% proposed — not implemented yet

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

        %% proposed — not implemented yet

        class StoryOrigin {
            <<enumeration>>
            NOT_DECLARED = 'not_declared'
            COMMUNITY_RECORDED = 'community_recorded'
            ORAL_TRANSCRIPTION = 'oral_transcription'
            PUBLISHED_COLLECTION = 'published_collection'
            ORIGINAL_CONTRIBUTION = 'original_contribution'
            SEEDED_DEMONSTRATION = 'seeded_demonstration'
            UNKNOWN = 'unknown'
        }

        %% proposed — not implemented yet

        class StoryConsent {
            <<enumeration>>
            NOT_REQUESTED = 'not_requested'
            PENDING = 'pending'
            GRANTED = 'granted'
            GRANTED_RESTRICTED = 'granted_restricted'
            WITHHELD = 'withheld'
        }

        %% proposed — not implemented yet

        class StoryLicence {
            <<enumeration>>
            ALL_RIGHTS_RESERVED = 'all_rights_reserved'
            CC_BY = 'cc_by'
            CC_BY_SA = 'cc_by_sa'
            CC_BY_NC = 'cc_by_nc'
            CC_BY_NC_SA = 'cc_by_nc_sa'
            PUBLIC_DOMAIN = 'public_domain'
            UNDETERMINED = 'undetermined'
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
            +String reason: FlagReason
            +String details
            +DateTime created_at
            +bool resolved
            +String resolution_notes
        }

        %% proposed — not implemented yet

        class FlagReason {
            <<enumeration>>
            CULTURAL_INACCURACY = 'cultural_inaccuracy'
            INAPPROPRIATE_CONTENT = 'inappropriate_content'
            COPYRIGHT_VIOLATION = 'copyright_violation'
            WRONG_CATEGORY = 'wrong_category'
            OTHER = 'other'
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
            +is_complete bool
        }
    }

    namespace Museum {
        class Museum {
            <<proposed>>
            +int id
            +String name
            +String description
            +String location
            +String region
            +String address
            +float latitude
            +float longitude
            +String website
            +String phone
            +String email
        }

        class MuseumFloor {
            <<proposed>>
            +int id
            +Museum museum
            +String name
            +int number
            +String description
        }

        class DisplayCase {
            <<proposed>>
            +int id
            +MuseumFloor floor
            +String name
            +String number
            +String description
        }

        class Artifact {
            +int id
            +String title
            +String slug
            +String description
            +String category: ArtifactCategory
            +String content_type: ArtifactContentType
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
            +qr_deep_link String
            +Museum museum
            +MuseumFloor located_on
            +DisplayCase displayed_in
        }

        %% proposed — not implemented yet

        class ArtifactCategory {
            <<enumeration>>
            SCULPTURE = 'sculpture'
            TEXTILE = 'textile'
            INSTRUMENT = 'instrument'
            JEWELRY = 'jewelry'
            POTTERY = 'pottery'
            MASK = 'mask'
            WEAPON = 'weapon'
            FABRIC = 'fabric'
            TOOL = 'tool'
            OTHER = 'other'
        }

        %% proposed — not implemented yet

        class ArtifactContentType {
            <<enumeration>>
            KINGDOM = 'kingdom'
            LANDMARK = 'landmark'
            ARTIFACT = 'artifact'
            LEGEND = 'legend'
            CULTURE = 'culture'
            UNKNOWN = 'unknown'
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
    }

    namespace Gamification {
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
            +question_count int
            +xp_reward int
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
            +String difficulty: QuestionDifficulty
            +int order
        }

        %% proposed — not implemented yet

        class QuestionDifficulty {
            <<enumeration>>
            EASY = 'easy'
            MEDIUM = 'medium'
            HARD = 'hard'
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
            +String status: QuizAttemptStatus
            +JSON answers
            +DateTime started_at
            +DateTime completed_at
            +int time_taken_seconds
            +calculate_score() int
        }

        %% proposed — not implemented yet

        class QuizAttemptStatus {
            <<enumeration>>
            IN_PROGRESS = 'in_progress'
            COMPLETED = 'completed'
            TIMED_OUT = 'timed_out'
        }

        class Badge {
            +int id
            +String name
            +String slug
            +String description
            +String emoji
            +String category: BadgeCategory
            +int xp_required
            +int stories_read_required
            +int quizzes_passed_required
            +int streak_required
            +String color
            +String icon_url
            +bool is_active
            +bool is_secret
            +DateTime created_at
        }

        %% proposed — not implemented yet

        class BadgeCategory {
            <<enumeration>>
            READING = 'reading'
            QUIZ = 'quiz'
            SOCIAL = 'social'
            EXPLORATION = 'exploration'
            SPECIAL = 'special'
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
            +String timezone
            +DateTime created_at
            +DateTime updated_at
            +xp_for_next_level int
            +xp_progress float
            +add_xp(amount) void
            +update_streak() void
        }

        class XPTransaction {
            <<proposed>>
            +int id
            +User user
            +int amount
            +String source: XPTransactionSource
            +String description
            +String reference
            +DateTime created_at
        }

        %% proposed — not implemented yet

        class XPTransactionSource {
            <<enumeration>>
            QUIZ_COMPLETION = 'quiz_completion'
            STORY_COMPLETED = 'story_completed'
            AUDIO_NARRATION = 'audio_narration'
            VIDEO_GENERATION = 'video_generation'
            CONTRIBUTOR_PUBLISH = 'contributor_publish'
            MANUAL_ADJUSTMENT = 'manual_adjustment'
        }

        class Certificate {
            +int id
            +User user
            +String certificate_type: CertificateType
            +String title
            +String description
            +DateTime issued_at
            +String certificate_number
            +int stories_read
            +int quizzes_passed
            +int level_achieved
            +String pdf_url
            +save() void
            +generate_pdf() void
        }

        %% proposed — not implemented yet

        class CertificateType {
            <<enumeration>>
            READING = 'reading'
            QUIZ = 'quiz'
            EXPLORER = 'explorer'
            CONTRIBUTOR = 'contributor'
        }
    }

    namespace Notification {
        class Notification {
            +int id
            +User user
            +String kind: NotificationKind
            +String title
            +String body
            +Story story
            +String story_title
            +String story_slug
            +String dedupe_key
            +bool is_read
            +DateTime read_at
            +DateTime created_at
            +mark_read(commit) bool
        }

        %% proposed — not implemented yet

        class NotificationKind {
            <<enumeration>>
            NEW_STORY = 'new_story'
            TRENDING = 'trending'
            STREAK = 'streak'
            BADGE = 'badge'
            ANNOUNCEMENT = 'announcement'
            SYSTEM = 'system'
        }
    }

    namespace Moderation {
        class ModerationReview {
            <<proposed>>
            +int id
            +Story story
            +User reviewer
            +String status: ModerationReviewStatus
            +String decision: ModerationDecision
            +String notes
            +DateTime created_at
            +DateTime updated_at
        }

        %% proposed — not implemented yet

        class ModerationReviewStatus {
            <<enumeration>>
            PENDING = 'pending'
            IN_REVIEW = 'in_review'
            APPROVED = 'approved'
            REJECTED = 'rejected'
        }

        %% proposed — not implemented yet

        class ModerationDecision {
            <<enumeration>>
            PENDING = 'pending'
            APPROVED = 'approved'
            APPROVED_WITH_RESTRICTIONS = 'approved_with_restrictions'
            REJECTED = 'rejected'
            ARCHIVED = 'archived'
        }
    }

    namespace Recommendation {
        class Recommendation {
            <<proposed>>
            +int id
            +User user
            +Story story
            +float score
            +String reason
            +String strategy
            +DateTime created_at
            +DateTime expires_at
        }

        class UserInterest {
            <<proposed>>
            +int id
            +User user
            +StoryCategory category
            +String region
            +String language: StoryLanguage
            +float score
            +DateTime updated_at
        }
    }

    namespace Social {
        class Comment {
            <<proposed>>
            +int id
            +User user
            +Story story
            +Text content
            +Comment parent
            +bool is_approved
            +DateTime created_at
            +DateTime updated_at
        }

        class Collection {
            <<proposed>>
            +int id
            +User user
            +String name
            +String description
            +bool is_public
            +DateTime created_at
        }

        class CollectionItem {
            <<proposed>>
            +int id
            +Collection collection
            +Story story
            +DateTime added_at
        }
    }

    namespace Analytics {
        class UserEvent {
            <<proposed>>
            +int id
            +User user
            +String event_type: UserEventType
            +String entity_type
            +int entity_id
            +JSON metadata
            +DateTime timestamp
            +String session_key
        }

        %% proposed — not implemented yet

        class UserEventType {
            <<enumeration>>
            STORY_VIEWED = 'story_viewed'
            STORY_COMPLETED = 'story_completed'
            STORY_LIKED = 'story_liked'
            STORY_SHARED = 'story_shared'
            QUIZ_STARTED = 'quiz_started'
            QUIZ_COMPLETED = 'quiz_completed'
            QR_SCANNED = 'qr_scanned'
            ARTIFACT_VIEWED = 'artifact_viewed'
            AUDIO_PLAYED = 'audio_played'
            VIDEO_PLAYED = 'video_played'
        }
    }

    namespace AI {
        class AIService {
            <<interface>>
            +name String
            +execute(request) AIResponse
        }

        class StoryGenerationService {
            +generateStory(prompt, language) AIResponse
            +buildNarrationScript(artifact) Text
        }

        class StoryRecommendationService {
            +recommend(user, limit) List~Recommendation~
        }

        class TranslationService {
            +translateStory(story, target) StoryTranslation
            +validateGlossary(source, target) List~String~
        }

        class ContentModerationService {
            +moderateContent(text) AIResponse
            +classify(text) AIResponse
        }

        class CulturalValidationService {
            +validateCulturalContent(story) AIResponse
            +flagCulturalConcerns(story) List~String~
        }

        class AIRequest {
            <<proposed>>
            +int id
            +User user
            +String request_type: AIRequestType
            +String prompt
            +String language
            +String status: AIRequestStatus
            +int tokens_used
            +String error_message
            +DateTime created_at
            +DateTime completed_at
        }

        class AIResponse {
            <<proposed>>
            +int id
            +AIRequest request
            +Text content
            +String model
            +float confidence
            +DateTime created_at
        }

        %% proposed — not implemented yet

        class AIRequestType {
            <<enumeration>>
            STORY_GENERATION = 'story_generation'
            STORY_RECOMMENDATION = 'story_recommendation'
            TRANSLATION = 'translation'
            CONTENT_MODERATION = 'content_moderation'
            CULTURAL_VALIDATION = 'cultural_validation'
            NARRATION = 'narration'
        }

        %% proposed — not implemented yet

        class AIRequestStatus {
            <<enumeration>>
            PENDING = 'pending'
            PROCESSING = 'processing'
            COMPLETED = 'completed'
            FAILED = 'failed'
        }
    }

    namespace Media {
        class MediaGenerationJob {
            <<abstract>>
            +int id
            +User user
            +String job_type: MediaJobType
            +String status: JobStatus
            +String provider
            +String external_job_id
            +int progress_percent
            +String error_message
            +String engine
            +String origin_kind: MediaOriginKind
            +DateTime created_at
            +DateTime updated_at
            +DateTime started_at
            +DateTime completed_at
            +is_ready bool
            +is_processing bool
        }

        %% proposed — not implemented yet

        class MediaJobType {
            <<enumeration>>
            AUDIO = 'audio'
            VIDEO = 'video'
            VR = 'vr'
            IMAGE = 'image'
        }

        %% proposed — not implemented yet

        class JobStatus {
            <<enumeration>>
            PENDING = 'pending'
            PROCESSING = 'processing'
            COMPLETED = 'completed'
            FAILED = 'failed'
        }

        %% proposed — not implemented yet

        class MediaOriginKind {
            <<enumeration>>
            HUMAN_RECORDING = 'human_recording'
            SYNTHETIC = 'synthetic'
            UNKNOWN = 'unknown'
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
            +String status: JobStatus
            +FileField audio_file
            +String audio_url
            +int duration
            +int file_size
            +String error_message
            +DateTime created_at
            +DateTime updated_at
            +DateTime completed_at
            +String engine
            +String origin_kind: MediaOriginKind
            +is_ready bool
            +is_synthetic bool
            +attribution String
        }

        class VideoGenerationJob {
            +int id
            +User user
            +Story story
            +String luma_job_id
            +String prompt
            +String luma_request_id
            +String status: JobStatus
            +int progress_percent
            +String video_url
            +String thumbnail_url
            +int duration
            +String error_message
            +DateTime created_at
            +DateTime updated_at
            +DateTime started_at
            +DateTime completed_at
            +String engine
            +String origin_kind: MediaOriginKind
            +is_ready bool
            +is_processing bool
            +is_synthetic bool
            +attribution String
        }
    }

    namespace Web {
        class WebUserSettings {
            +int id
            +User user
            +String language: en or fr
            +String theme: light, dark or system
            +DateTime updated_at
        }
    }

    %% ══ Relationships ══════════════════════════════════════════════════
    %% Composition (*--) is used only where the child cannot exist without
    %% the parent. AudioNarrationJob and VideoGenerationJob are deliberately
    %% NOT composed under MediaGenerationJob: both are independent rows with
    %% no foreign key to a parent job, so they generalise from a shared
    %% abstract concept rather than being contained by it.

    %% ── Story core ──
    Story --> StoryStatus : has
    Story --> StoryLanguage : has
    Story --> StoryOrigin : has
    Story --> StoryConsent : has
    Story --> StoryLicence : has
    StoryFlag --> FlagReason : has
    User "1" --> "*" Story : authors
    Story "*" --> "*" User : co_authors
    User "1" --> "*" StoryBookmark : creates
    Story "1" --> "*" StoryBookmark : has
    User "1" --> "*" StoryLike : creates
    Story "1" --> "*" StoryLike : has
    User "1" --> "*" StoryFlag : creates
    Story "1" --> "*" StoryFlag : has
    Story "1" --> "*" StoryShare : has
    User "1" --> "*" ReadingProgress : tracks
    Story "1" --> "*" ReadingProgress : has
    StoryCategory "*" --> "*" Story : categories
    Story "1" --> "*" StoryTranslation : has
    User "0..1" --> "*" StoryTranslation : translates

    %% ── Museum ──
    Museum "1" *-- "*" MuseumFloor : floors
    MuseumFloor "1" *-- "*" DisplayCase : cases
    Museum "1" --> "*" Artifact : holds
    MuseumFloor "0..1" --> "*" Artifact : locates
    DisplayCase "0..1" --> "1" Artifact : displays
    Artifact --> ArtifactCategory : has
    Artifact --> ArtifactContentType : has
    User "1" --> "*" Artifact : creates
    Artifact "1" --> "*" QRCodeScan : has
    User "0..1" --> "*" QRCodeScan : performs
    Artifact "*" --> "*" Story : related_stories

    %% ── Gamification ──
    Quiz "1" --> "1" Story : tied_to
    Quiz "1" *-- "*" QuizQuestion : contains
    QuizQuestion --> QuestionDifficulty : has
    QuizAttempt --> QuizAttemptStatus : has
    Badge --> BadgeCategory : has
    Certificate --> CertificateType : has
    User "1" --> "*" QuizAttempt : attempts
    Quiz "1" --> "*" QuizAttempt : has
    User "1" --> "*" UserBadge : earns
    Badge "1" --> "*" UserBadge : granted_as
    User "1" --> "1" UserProfile : has
    User "1" --> "*" Certificate : receives
    User "1" --> "*" XPTransaction : accrues
    XPTransaction --> XPTransactionSource : has

    %% ── Notification ──
    User "1" --> "*" Notification : receives
    Notification --> NotificationKind : has
    Story "0..1" --> "*" Notification : referenced_by

    %% ── Moderation ──
    Story "1" --> "*" ModerationReview : reviewed_by
    User "0..1" --> "*" ModerationReview : reviewer
    ModerationReview --> ModerationReviewStatus : has
    ModerationReview --> ModerationDecision : has

    %% ── Recommendation ──
    User "1" --> "*" Recommendation : receives
    Story "1" --> "*" Recommendation : recommended_as
    User "1" --> "*" UserInterest : has
    StoryCategory "0..1" --> "*" UserInterest : about
    StoryLanguage "0..1" --> "*" UserInterest : in

    %% ── Social ──
    User "1" --> "*" Comment : writes
    Story "1" --> "*" Comment : has
    Comment "0..1" --> "*" Comment : replies_to
    User "1" --> "*" Collection : owns
    Collection "1" *-- "*" CollectionItem : contains
    Story "1" --> "*" CollectionItem : collected_as

    %% ── Analytics ──
    User "0..1" --> "*" UserEvent : emits
    UserEvent --> UserEventType : has

    %% ── AI ──
    AIService --> AIRequest : records
    AIService --> AIResponse : produces
    User "0..1" --> "*" AIRequest : issues
    AIRequest "1" --> "0..1" AIResponse : answers
    AIRequest --> AIRequestType : has
    AIRequest --> AIRequestStatus : has
    AIService <|-- StoryGenerationService
    AIService <|-- StoryRecommendationService
    AIService <|-- TranslationService
    AIService <|-- ContentModerationService
    AIService <|-- CulturalValidationService

    %% ── Media ──
    User "1" --> "*" AudioNarrationJob : creates
    Story "1" --> "*" AudioNarrationJob : has
    Artifact "1" --> "*" AudioNarrationJob : has
    User "1" --> "*" VideoGenerationJob : creates
    Story "1" --> "*" VideoGenerationJob : has
    AudioNarrationJob --> JobStatus : has
    VideoGenerationJob --> JobStatus : has
    AudioNarrationJob --> MediaOriginKind : attributed_as
    VideoGenerationJob --> MediaOriginKind : attributed_as
    MediaGenerationJob --> JobStatus : has
    MediaGenerationJob --> MediaOriginKind : attributed_as
    MediaGenerationJob --> MediaJobType : has
    AudioNarrationJob --|> MediaGenerationJob : is_a
    VideoGenerationJob --|> MediaGenerationJob : is_a

    %% ── Web ──
    User "1" --> "1" WebUserSettings : has
```

---

## Authorization classes (backend)

Preserved from the source file, unchanged: same classes, same operations, same
generalization, same note. Every gate in the system is one of these. Role
checks are **hierarchical** (`in (...)` against the documented role strings);
ownership is **object-level**. Sources: `stories/views.py`, `qr_codes/views.py`,
`api/views_analytics.py`, `media_app/views.py`, `web/views.py`,
`qr_codes/views.py`.

```mermaid
classDiagram
    title Griot 2.0 — Authorization classes

    class IsAuthenticated {
        <<DRF builtin>>
        +has_permission(bool)
    }

    class IsContributorOrAbove {
        +has_permission(bool)
        %% role in (contributor, institution_manager, admin)
    }

    class IsInstitutionManagerOrAbove {
        +has_permission(bool)
        %% role in (institution_manager, admin)
    }

    class IsAdminOrManager {
        +has_permission(bool)
        %% role in (institution_manager, admin)
        %% used by ALL seven analytics endpoints + story moderation
    }

    class IsAuthenticatedOrReadOnly {
        +has_permission(bool)
        %% SAFE_METHODS OR authenticated (gamification app; DRF default)
    }

    class IsStoryOwnerOrReadOnly {
        +has_object_permission(bool)
        %% SAFE_METHODS OR obj.author == user OR role in (manager, admin)
    }

    class IsOwnerOrReadOnly {
        +has_object_permission(bool)
        %% SAFE_METHODS OR obj.user == user
    }

    IsContributorOrAbove --|> IsAuthenticated
    IsInstitutionManagerOrAbove --|> IsAuthenticated
    IsAdminOrManager --|> IsAuthenticated
    IsStoryOwnerOrReadOnly --|> IsAuthenticated
    IsOwnerOrReadOnly --|> IsAuthenticated
    IsAuthenticatedOrReadOnly --|> IsAuthenticated

    note for IsAdminOrManager "Implemented gate is WIDER than the documented Admin-only rule for analytics."
```

The `qr_codes` worklist endpoints added in Phase 5 reuse
`IsInstitutionManagerOrAbove` unchanged — reading the worklist is curator-only
because it names unpublished artifacts, so it is a manager gate even though it
does not mutate anything.

---

## Frontend classes (Flutter/Dart)

Preserved from the source file, with three corrections that the source file's
own consistency check asked for:

* **`AuthRepository` was declared twice**, identically, in the same block. It is
  declared once here.
* **Nine classes were referenced but never declared** — `TokenPair`,
  `UserStats`, `StoryStats`, `GamificationStats`, `QRStats`,
  `EngagementSummary`, `OfflineRequestRepository`, `LocalGamificationRepository`
  and `LocalLibraryRepository`. All nine exist in `frontend/lib`, so they are
  declared here rather than invented.
* **`AdminApiService.getModerationQueue()` was typed `List~ModerationItem~`.**
  No `ModerationItem` exists; the real return type is `List~FlaggedStory~`
  (`features/admin/models/moderation_models.dart`). Corrected.

```mermaid
classDiagram
    title Griot 2.0 — Frontend Class Diagram

    namespace Core_Network {
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

        class RetryInterceptor {
            -int _maxRetries
            +onError() void
        }

        class AppError {
            <<sealed>>
            -network / -auth / -validation / -offline / -unknown
        }

        class AppErrorMapper {
            +appErrorFromDio(dioException) AppError
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

        class OfflineRequestRepository {
            +enqueue(request) int
            +pending() List
            +markSynced(id) void
            +clear() void
        }
    }

    namespace Core_Data {
        class LocalStoryRepository {
            <<SQLite>>
            +Future getStories(...) List~StoryModel~
            +Future createStory(...) StoryModel
            +Future updateStory(...) StoryModel
            +Future toggleBookmark(slug) bool
            +Future toggleLike(slug) bool
            +Future flagStory(slug,reason,details) void
            +Future updateReadingProgress(...) void
        }

        class LocalGamificationRepository {
            <<SQLite>>
            +Future getQuizzes() List
            +Future submitAnswer(...) Map
            +Future finishQuiz(...) Map
            +Future getLeaderboard() List
        }

        class LocalLibraryRepository {
            <<SQLite>>
            +Future getRecentStories() List~StoryModel~
            +Future getBookmarks() List~StoryModel~
            +Future getContinueReading() List~StoryModel~
        }
    }

    namespace Auth {
        class AuthRepository {
            <<interface>>
            +Future~bool~ isAuthenticated
            +Future~String?~ accessToken
            +Future~String?~ refreshToken
            +Future clearTokens() void
            +Future login(username,password) TokenPair
            +Future register(...) UserModel
            +Future refreshTokens() TokenPair
            +Future getMe() UserModel
            +Future updateProfile(...) UserModel
            +Future deleteAccount() void
            +Future logout() void
        }

        class ServerAuthRepository {
            +Future login() TokenPair
            +Future getMe() UserModel
            +Future register() UserModel
        }

        class LocalAuthRepository {
            <<SQLite + secure storage>>
            +Future~bool~ isAuthenticated
            +Future getMe() UserModel
        }

        class OfflineAuthRepository {
            +registerQueued() Future
        }

        class OfflineUserRepository {
            <<SQLite>>
            +upsertUserFromServer() Future
        }

        class TokenPair {
            +String accessToken
            +String refreshToken
            +DateTime expiresAt
        }

        class LoginScreen {
            +build() Widget
        }

        class RegisterScreen {
            +build() Widget
        }

        class ProfileScreen {
            +TextEditingController _firstNameController
            +TextEditingController _lastNameController
            +bool _isEditing
            +build() Widget
        }

        class RoleBadge {
            +UserRole role
            +build() Widget
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
            +canContribute bool
            +canGenerateMediaFor(int authorId) bool
        }

        class AuthStatus {
            <<enumeration>>
            initial
            unauthenticated
            authenticated
            pendingSync
            loading
            error
        }
    }

    namespace Stories {
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

        class StoryRepository {
            <<interface>>
            +Future getStories(...) List~StoryModel~
            +Future getStory(slug) StoryModel
            +Future createStory(...) StoryModel
            +Future updateStory(...) StoryModel
            +Future deleteStory(slug) void
            +Future getMyStories() List~StoryModel~
            +Future getBookmarks() List~StoryModel~
            +Future toggleBookmark(slug) bool
            +Future toggleLike(slug) bool
            +Future flagStory(...) void
            +Future updateReadingProgress(...) void
        }

        class StoryListNotifier {
            +StoryListState state
            +loadStories() Future
            +refresh() Future
            +loadMore() Future
            -_loadFromCache() Future
        }

        class StoryListState {
            <<sealed>>
            +InProgress()
            +Ready()
            +Failure()
        }

        class StoriesScreen {
            +TextEditingController _searchController
            +build() Widget
        }

        class StoryDetailScreen {
            +build() Widget
        }

        class StoryFormScreen {
            +TextEditingController _titleController
            +TextEditingController _contentController
            +TextEditingController _summaryController
            +TextEditingController _tagsController
            +TextEditingController _regionController
            +TextEditingController _culturalContextController
            +TextEditingController _moralLessonController
            +TextEditingController _sourceController
            +build() Widget
        }

        class StoryCard {
            +StoryModel story
            +build() Widget
        }
    }

    namespace Gamification {
        class GamificationApiService {
            <<SQLite facade>>
            +listQuizzes() List
            +getQuiz() Quiz
            +submitAnswer(...) void
            +finishQuiz(...) QuizAttempt
            +getLeaderboard() List
        }

        class LibraryApiService {
            <<SQLite facade>>
            +getRecentStories() List~StoryModel~
            +getBookmarks() List~StoryModel~
            +getContinueReading() List~StoryModel~
        }

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
    }

    namespace Admin {
        class AdminApiService {
            +getDashboardSummary() DashboardSummary
            +getUsers(search) List~AdminUser~
            +getModerationQueue() List~FlaggedStory~
            +getConsentQueue() List~ConsentReviewStory~
            +moderateStory(slug, action, notes) void
            +recordStoryConsent(...) void
            +getQrWorklist() QrWorklist
            +generateQrCodes(slugs) QrWorklistGeneration
        }

        class AdminUser {
            +int id
            +String username
            +String email
            +String firstName
            +String lastName
            +String role
            +String roleDisplay
            +String institution
            +String dateJoined
            +bool isActive
        }

        class DashboardSummary {
            +UserStats users
            +StoryStats stories
            +GamificationStats gamification
            +QRStats qrCodes
            +EngagementSummary engagement
        }

        class UserStats {
            +int totalUsers
            +int activeUsers30d
            +List growth
        }

        class StoryStats {
            +int totalStories
            +int pendingReview
            +Map storiesByStatus
        }

        class GamificationStats {
            +int totalQuizzesTaken
            +float passRate
            +List topUsers
        }

        class QRStats {
            +int totalScans
            +int publishedArtifacts
        }

        class EngagementSummary {
            +int unresolvedFlags
            +RecentActivity recentActivity7d
            +int totalReadingTime
        }

        class RecentActivity {
            +int newUsers
            +int newStories
            +int quizAttempts
            +int qrScans
            +int shares
        }

        class FlaggedStory {
            +int storyId
            +String slug
            +String title
            +String status
            +String authorUsername
            +List flags
        }

        class ConsentReviewStory {
            +String slug
            +String title
            +String declaredOrigin
            +String provenanceNotes
        }

        class QrWorklist {
            +List entries
            +int total
            +int generated
            +bool truncated
            +unlabelled List
        }

        class QrWorklistEntry {
            +int id
            +String slug
            +String title
            +String category
            +String museumName
            +bool isPublished
            +String deepLink
            +int scanTotal
            +bool hasQrCode
        }

        class QrWorklistGeneration {
            +List generated
            +List missing
            +bool skipped
        }

        class ModerationSection {
            +Widget build() Widget
        }

        class QrWorklistSection {
            +Widget build() Widget
        }
    }

    namespace Artifacts {
        class ArtifactsProvider {
            +Future listArtifacts() List
        }

        class RegionModel {
            +String slug
            +String name
            +String language
            +String description
        }

        class RegionProvider {
            +Future regions() List~RegionModel~
        }
    }

    namespace Media {
        class AudioApiService {
            +generateNarration(storyId) void
            +checkStatus(jobId) void
        }

        class AudioNarrationNotifier {
            <<Riverpod>>
            +play() void
            +pause() void
            +stop() void
        }

        class OfflineAudioService {
            +cacheAudio() void
            +playCached() void
        }

        class VideoApiService {
            +createJob(storyId, prompt) void
            +pollStatus(jobId) void
        }

        class VideoStatusPoller {
            +Timer _timer
            +start(jobId) void
        }
    }

    namespace Navigation {
        class AppRouter {
            <<go_router>>
            +String location
            +goToStory(slug) void
            +goToArtifact(slug) void
            +routeTo(deepLinkKind, slug) void
        }

        class MainShell {
            +int currentIndex
            +int destinationCount
            +build() Widget
        }

        class AppDeepLink {
            <<enumeration>>
            story / artifact / quiz / profile / library / scan
        }
    }

    namespace Settings {
        class SettingsScreen {
            +SwitchValue _audioSync
            +build() Widget
        }

        class WhatsAppFeedbackService {
            +openWhatsApp() Future
        }
    }

    class ApiClientConsumer {
        <<feature services/packages>>
        +admin_api_service     -> /api/analytics + /api/stories/moderation_queue/
        +audio_api_service     -> /api/media/audio + status
        +video_api_service     -> /api/media/videos + status
        +qr_api_service        -> /api/artifacts/lookup/ + scans
        +sharing_service       -> /api/stories/{slug}/share
        +offline_auth_repository -> /api/auth/register (queued)
        +story_repository      -> /api/stories (online-first mirror)
        +artifacts_provider    -> /api/artifacts
        +region_provider       -> /api/categories (discover)
        +qr_worklist_provider  -> /api/artifacts/qr/worklist/
    }

    %% ── Core wiring ──
    ApiClient --> AuthInterceptor : uses
    ApiClient --> OfflineQueueInterceptor : uses
    ApiClient --> RetryInterceptor : uses
    ApiClient --> ConnectivityService : depends
    OfflineSyncManager --> ConnectivityService : listens
    OfflineSyncManager --> ApiClient : replays requests
    OfflineSyncManager --> OfflineRequestRepository : reads queue
    AuthInterceptor --> AuthRepository : uses
    AuthInterceptor --> AppErrorMapper : maps failures
    ApiClientConsumer --> AppErrorMapper : maps failures

    %% ── Auth ──
    AuthProvider --> AuthRepository : uses
    AuthProvider --> AuthStatus : tracks
    AuthWrapper --> AuthProvider : watches
    ProfileScreen --> AuthProvider : watches
    ProfileScreen --> RoleBadge : displays
    RoleBadge --> UserModel : reads role
    ProfileScreen --> UserModel : displays
    AuthRepository <|-- ServerAuthRepository
    AuthRepository <|-- LocalAuthRepository
    AuthRepository <|-- OfflineAuthRepository
    ServerAuthRepository --> ApiClient : POST /api/auth/token/
    ServerAuthRepository --> TokenPair : returns
    ServerAuthRepository --> UserModel : returns
    LocalAuthRepository --> UserModel : returns
    OfflineAuthRepository --> OfflineRequestRepository : enqueues

    %% ── Stories ──
    StoryRepository <|-- LocalStoryRepository
    StoryListNotifier --> StoryRepository : uses
    StoryListNotifier --> StoryListState : emits
    StoryRepository --> ApiClient : online-first (GET covers/media)
    StoryRepository --> LocalStoryRepository : offline mirror (SQLite upsert)
    StoriesScreen --> StoryListNotifier : watches
    StoryDetailScreen --> StoryRepository : reads
    StoryFormScreen --> StoryRepository : saves
    StoryCard --> StoryModel : displays
    StoryListState --> StoryModel : carries

    %% ── Gamification / library ──
    GamificationApiService --> LocalGamificationRepository : delegates
    LibraryApiService --> LocalLibraryRepository : delegates
    GamificationScreen --> QuizPlayerWidget : contains
    GamificationScreen --> BadgeCard : displays
    BadgeCard --> Badge : reads

    %% ── Admin ──
    AdminApiService --> ApiClient : uses
    AdminApiService --> AdminUser : returns
    AdminApiService --> DashboardSummary : returns
    AdminApiService --> FlaggedStory : returns
    AdminApiService --> ConsentReviewStory : returns
    AdminApiService --> QrWorklist : returns
    AdminApiService --> QrWorklistGeneration : returns
    DashboardSummary --> UserStats : composes
    DashboardSummary --> StoryStats : composes
    DashboardSummary --> GamificationStats : composes
    DashboardSummary --> QRStats : composes
    DashboardSummary --> EngagementSummary : composes
    EngagementSummary --> RecentActivity : composes
    QrWorklist --> QrWorklistEntry : contains
    QrWorklistGeneration --> QrWorklistEntry : names
    ModerationSection --> FlaggedStory : displays
    QrWorklistSection --> QrWorklistEntry : displays

    %% ── Artifacts ──
    ArtifactsProvider --> ApiClient : uses
    RegionProvider --> ApiClient : uses
    RegionProvider --> RegionModel : returns

    %% ── Media ──
    VideoApiService --> ApiClient : uses
    AudioApiService --> ApiClient : uses
    VideoStatusPoller --> VideoApiService : polls
    AudioApiService --> AudioNarrationNotifier : notifies
    OfflineAudioService --> AudioNarrationNotifier : caches

    %% ── Navigation ──
    AppRouter --> AppDeepLink : maps moved URL to route
    MainShell --> AppRouter : hosts

    %% ── Settings ──
    SettingsScreen --> WhatsAppFeedbackService : uses
```

---

## Web UI classes (Django `web` app)

The server-rendered web interface reuses the backend models above; these are its
web-only classes. Preserved from the source file, with `WebLoginView` and
`WebLogoutView` promoted from being listed inside `web_views` to being declared
as the classes they are (`backend/web/views.py`), and the QR worklist actions
added in Phase 5 included.

```mermaid
classDiagram
    title Griot 2.0 — Web UI Classes (web app)

    %% WebUserSettings is the same class as in the backend domain block above.
    %% Mermaid has no cross-block import, so re-declaring it here is what keeps
    %% this block self-contained; the count script reports it as the one
    %% intentional cross-block duplicate.
    class WebUserSettings {
        +int id
        +User user
        +String language
        +String theme
    }

    class WebLoginView {
        +form_valid(form) void
        +get_success_url() str
    }

    class WebLogoutView {
        +get_success_url() str
    }

    class web_views {
        <<module (thin)>>
        +home_view(request)
        +stories_view(request)
        +story_detail_view(request, slug)
        +story_form_view(request, slug)
        +library_view(request)
        +artifact_list_view(request)
        +artifact_detail_view(request, slug)
        +gamification_view(request)
        +quizzes_view(request)
        +quiz_play_view(request, quiz_id)
        +profile_view(request)
        +admin_dashboard_view(request)
    }

    class web_services {
        <<module (business logic)>>
        +home_data(user)
        +stories_data(user, *, search, language, category_slug, region, sort)
        +story_detail_data(user, slug)
        +artifact_list_data(category)
        +artifact_detail_data(user, request, slug)
        +gamification_data(user)
        +quiz_play_data(user, quiz_id)
        +admin_dashboard_data()
        +resolve_ui_language(code)
        +toggle_story_like(user, story)
        +flag_story(user, story, reason, details)
        +start_quiz(user, quiz)
        +finish_quiz(user, quiz)
        +moderate_story(user, story, action, notes)
        +generate_story_audio(user, story, language)
        +generate_story_video(user, story, prompt)
        +qr_worklist_data(limit)
        +generate_qr_for_artifacts(slugs, persist)
        +register_user(*, username, email, password, password2, role)
    }

    class web_actions {
        <<module>>
        +story_like(request, slug)
        +story_bookmark(request, slug)
        +story_flag(request, slug)
        +story_share(request, slug)
        +story_progress(request, slug)
        +story_save(request, slug)
        +story_delete(request, slug)
        +story_generate_audio(request, slug)
        +story_generate_video(request, slug)
        +artifact_generate_audio(request, slug)
        +artifact_generate_qr(request, slug)
        +artifacts_generate_qr(request)
        +story_video_status(request, slug)
        +story_moderate(request, slug)
        +story_record_consent(request, slug)
        +story_request_consent(request, slug)
        +set_language(request)
        +quiz_start(request, quiz_id)
        +quiz_answer(request, quiz_id, question_id)
        +quiz_finish(request, quiz_id)
        +profile_update(request)
        +profile_delete(request)
        +register(request)
    }

    class StoryTemplates {
        <<files>>
        base.html
        home.html
        stories.html
        story_detail.html
        story_form.html
        library.html
        artifacts.html
        artifact_detail.html
        gamification.html
        quizzes.html
        quiz_play.html
        profile.html
        admin_dashboard.html
        partials/language_switch.html
    }

    web_actions --> web_views : redirects to
    web_views --> web_services : delegates business logic
    web_views --> StoryTemplates : renders
    web_views --> WebUserSettings : reads per-user prefs
    web_views --> WebLoginView : uses
    web_views --> WebLogoutView : uses
    web_services --> Story : same models as the API
    web_services --> WebUserSettings : reads and persists language
    web_services --> Artifact : QR worklist source
    web_services --> AudioNarrationJob : generates via TTS
    web_services --> VideoGenerationJob : generates via Luma AI
    web_actions --> Artifact : generates QR codes for
    web_actions --> Story : records consent and moderates
```
