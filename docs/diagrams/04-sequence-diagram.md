# Sequence Diagrams — Griot 2.0

> **Updated 2026-09-23:** Auth is **online-first** (`AuthRepository` →
> `ServerAuthRepository` obtains real JWT pairs from `/api/auth/token/`; the
> legacy SQLite/secure-storage session only kicks in as an offline fallback).

## 1. Authentication Flow

```mermaid
sequenceDiagram
    title Authentication Flow (Online-first Login + Token Refresh)

    participant U as User
    participant App as Flutter App
    participant AW as AuthWrapper
    participant AR as AuthRepository
    participant SR as ServerAuthRepository
    participant AI as AuthInterceptor
    participant API as Django REST API
    participant DB as Database

    Note over U,DB: === Login Flow — online path ===

    U->>App: Open App
    App->>AW: Build AuthWrapper
    AW->>AR: Check stored tokens
    AR-->>AW: No tokens found
    AW->>U: Show LoginScreen

    U->>App: Enter credentials & tap Login
    App->>AR: login(username, password)
    AR->>SR: login(username, password)
    SR->>API: POST /api/auth/token/
    API->>DB: Validate credentials (5/min throttle)
    DB-->>API: User found
    API-->>SR: {access, refresh} tokens (SimpleJWT 30m / 7d)
    SR-->>AR: TokenPair
    AR->>AR: Store tokens in secure storage
    AR-->>App: AuthState.authenticated
    App->>AW: Rebuild
    AW->>U: Show HomeScreen

    Note over U,DB: === Offline fallback path ===

    U->>App: Login while offline (or API down)
    App->>AR: login(username, password)
    AR->>SR: login() — connection fails
    SR-->>AR: Network error (AppError.network)
    AR->>AR: Fall back to LocalAuthRepository
    AR-->>App: AuthState.authenticated (offline session)
    AW->>U: Show HomeScreen

    Note over U,DB: === Subsequent Authenticated Request ===

    U->>App: Navigate to Stories
    App->>API: GET /api/stories/
    AI->>AI: Inject Bearer token
    AI->>API: GET /api/stories/ (with token)
    API->>DB: Query stories
    DB-->>API: Stories list
    API-->>App: 200 OK + stories JSON
    App->>U: Display story list

    Note over U,DB: === Token Refresh on 401 (rotate + blacklist) ===

    App->>API: GET /api/stories/bookmarks/
    AI->>API: Bearer token (expired)
    API-->>AI: 401 Unauthorized
    AI->>AR: refreshTokens()
    AR->>API: POST /api/auth/token/refresh/
    API->>DB: Validate + blacklist old refresh token
    DB-->>API: Valid refresh token
    API-->>AR: New access + rotated refresh token
    AR->>AR: Update stored tokens
    AI->>API: Retry GET /api/stories/bookmarks/ (new token)
    API-->>App: 200 OK + bookmarks JSON
    App->>U: Display bookmarks
```

## 2. Story Reading + Progress Tracking

```mermaid
sequenceDiagram
    title Story Reading & Progress Tracking (online-first + mirror)

    participant U as User
    participant SS as StoriesScreen
    participant SD as StoryDetailScreen
    participant SR as StoryRepository
    participant API as Django REST API
    participant LSR as LocalStoryRepository (SQLite mirror)
    participant Cache as Story Cache

    U->>SS: Open Stories (online)
    SS->>SR: fetchStories()
    SR->>API: GET /api/stories/
    API-->>SR: Stories list
    SR->>LSR: Upsert all rows (slug-keyed mirror)
    LSR-->>SR: Mirror updated
    SR-->>SS: Display stories
    U->>SS: Tap story card

    SS->>SD: Navigate to StoryDetail
    SD->>SR: fetchStory(slug)
    SR->>API: GET /api/stories/{slug}/
    API-->>SR: Story detail
    API->>API: Increment view_count
    SR->>LSR: Upsert story cover/content
    SR-->>SD: Display story content
    SD->>U: Render Markdown content

    Note over U,Cache: === Offline: last synced mirror served ===

    U->>SS: Open Stories (offline)
    SS->>SR: fetchStories()
    SR->>API: GET /api/stories/ — connection fails
    SR->>LSR: Read mirror from SQLite
    LSR-->>SR: Cached stories (never-overwritten local data)
    SR-->>SS: Display stories from mirror
    U->>SD: Open saved story
    SD->>Cache: getFromCache(storyId)
    Cache-->>SD: Cached story content
    SD->>U: Display from cache

    Note over U,Cache: === Reading Progress (local-first, best-effort sync) ===

    U->>SD: Scroll down (25%)
    SD->>SR: updateProgress(slug, 25%)
    SR->>SR: Write to local ReadingProgressRepository
    SR->>API: POST /api/stories/{slug}/progress/ (best-effort)
    API-->>SR: Progress saved

    U->>SD: Bookmark story
    SD->>SR: toggleBookmark(slug)
    SR->>SR: Optimistic local write
    SR->>API: POST /api/stories/{slug}/bookmark/
    API-->>SR: {bookmarked: true}
    SR-->>SD: Update UI
```

## 3. QR Code Scan → Artifact Detail

```mermaid
sequenceDiagram
    title QR Code Scan → Artifact Detail Flow

    participant U as User
    participant QS as QR Scanner
    participant AD as ArtifactDetailScreen
    participant QR as QR API Service
    participant API as Django REST API

    U->>QS: Open QR Scanner
    QS->>QS: Initialize camera
    QS->>U: Show scanner overlay

    U->>QS: Scan QR code
    QS->>QS: Decode QR → slug
    QS->>QR: lookupArtifact(slug)
    QR->>API: GET /api/artifacts/lookup/?slug={slug}
    API->>API: Record QRCodeScan (device, IP, GPS)
    API-->>QR: Artifact detail JSON
    QR-->>AD: Navigate to artifact

    AD->>AD: Display artifact info
    AD->>U: Show title, image, description

    AD->>QR: fetchRelatedStories(artifactId)
    QR->>API: GET /api/artifacts/{id}/
    API-->>QR: Artifact with related stories
    QR-->>AD: Related stories list
    AD->>U: Show related stories

    U->>AD: Tap related story
    AD->>AD: Navigate to StoryDetailScreen
```

## 4. Gamification: Quiz Flow (local SQLite)

> **Updated 2026-09-23:** on mobile, quizzes are served **locally** from SQLite
> (`GamificationApiService` → `LocalGamificationRepository`). The Django
> `/api/gamification/*` endpoints exist for the web client and are **not**
> consumed by the Flutter app; `getLeaderboard()` returns `[]`.

```mermaid
sequenceDiagram
    title Gamification — Local Quiz Take & Grading Flow

    participant U as User
    participant GS as GamificationScreen
    participant QP as QuizPlayerWidget
    participant GA as GamificationApiService
    participant LQ as LocalGamificationRepository (SQLite)
    participant DB as Local Database

    U->>GS: Open Gamification
    GS->>GA: fetchQuizzes()
    GA->>LQ: listQuizzes()
    LQ->>DB: SELECT from quizzes
    DB-->>LQ: Seeded quiz rows
    LQ-->>GA: Quiz list
    GA-->>GS: Display quizzes

    U->>GS: Select a quiz
    GS->>QP: Start QuizPlayer

    QP->>GA: startQuiz(quizId)
    GA->>LQ: loadQuestions(quizId)
    LQ->>DB: SELECT questions
    DB-->>LQ: Questions (incl. correct_answer, local only)
    LQ-->>GA: Question list
    GA-->>QP: Display first question

    Note over U,DB: === Answer Questions (local grading) ===

    loop For each question
        U->>QP: Select answer (A/B/C/D)
        QP->>GA: submitAnswer(question, option)
        GA->>GA: Compare with correct_answer (local)
        GA-->>QP: {is_correct, explanation}
        QP->>U: Display feedback
    end

    Note over U,DB: === Finish & Grade (local) ===

    U->>QP: Tap "Finish Quiz"
    QP->>GA: finishQuiz(quizId)
    GA->>LQ: recordAttempt(score, result)
    LQ->>DB: upsert into attempts table
    DB-->>LQ: Attempt saved locally
    LQ-->>GA: Result

    GA-->>QP: Display score
    QP->>U: Show results screen
```

## 5. Offline → Online Sync

```mermaid
sequenceDiagram
    title Offline Request Queue → Online Sync Flow

    participant U as User
    participant App as Flutter App
    participant CSM as ConnectivityService
    participant OQI as OfflineQueueInterceptor
    participant OReqRepo as OfflineRequestRepository
    participant OSM as OfflineSyncManager
    participant API as Django REST API

    Note over U,API: === User is Offline ===

    U->>App: Tap "Bookmark Story"
    App->>OQI: POST /api/stories/{slug}/bookmark/
    OQI->>CSM: Check connectivity
    CSM-->>OQI: isOnline = false
    OQI->>OReqRepo: saveRequest(method, path, body)
    OReqRepo-->>OQI: Request queued
    OQI-->>App: 202 Queued response
    App->>U: "Request queued for offline"

    U->>App: Tap "Like Story"
    App->>OQI: POST /api/stories/{slug}/like/
    OQI->>OReqRepo: saveRequest(...)
    OReqRepo-->>OQI: Queued
    OQI-->>App: 202 Queued

    Note over U,API: === Connectivity Restored ===

    CSM->>CSM: Connectivity restored!
    CSM->>OSM: Notify (isOnline = true)
    OSM->>OReqRepo: getPendingRequests()
    OReqRepo-->>OSM: [bookmark, like]

    loop For each pending request
        OSM->>OSM: markInProgress(requestId)
        OSM->>API: POST /api/stories/{slug}/bookmark/
        API-->>OSM: 201 Created
        OSM->>OReqRepo: markCompleted(requestId)
    end

    loop For each pending request
        OSM->>API: POST /api/stories/{slug}/like/
        API-->>OSM: 201 Created
        OSM->>OReqRepo: markCompleted(requestId)
    end

    OSM-->>App: Sync complete
    App->>U: "All pending requests synced"
```

## 6. AI Video Generation Flow

```mermaid
sequenceDiagram
    title AI Video Generation (Luma AI) Flow

    participant U as User
    participant VGS as VideoGenerationSheet
    participant VA as VideoApiService
    participant VP as VideoStatusPoller
    participant API as Django REST API
    participant Luma as Luma AI API

    U->>VGS: Tap "Generate Video"
    VGS->>VGS: Show generation form
    U->>VGS: Enter prompt & tap Generate
    VGS->>VA: generateVideo(storyId, prompt)
    VA->>API: POST /api/media/videos/
    API->>Luma: Submit video generation job
    Luma-->>API: Job ID
    API-->>VA: 201 Created (job details)
    VA-->>VGS: Job submitted

    VGS->>VP: Start polling(jobId)
    VP->>API: GET /api/media/status/video/{jobId}/

    loop Polling (every 10s)
        API-->>VP: {status: "processing", progress: 45%}
        VP-->>VGS: Update status badge
        VGS->>U: Show progress (45%)
    end

    API-->>VP: {status: "completed", video_url: "..."}
    VP-->>VGS: Video ready!
    VGS->>U: Show video player

    U->>VGS: Tap play
    VGS->>VGS: Open VideoPlayerWidget
    VGS->>U: Play video
```
