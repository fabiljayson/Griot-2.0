# Use Case Diagram — Griot 2.0

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
        usecase "Play Offline Audio" as UC_OFFLINE_AUDIO
    }

    package "Video" {
        usecase "Generate AI Video" as UC_GEN_VIDEO
        usecase "Watch Video" as UC_WATCH
        usecase "Poll Video Status" as UC_POLL_VIDEO
    }

    package "Gamification" {
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

    package "Admin" {
        usecase "View Analytics Dashboard" as UC_ANALYTICS
        usecase "Moderate Content" as UC_MODERATE
        usecase "View Moderation Queue" as UC_MOD_QUEUE
        usecase "Resolve Flags" as UC_RESOLVE
    }

    package "Offline" {
        usecase "Save Story Offline" as UC_SAVE_OFFLINE
        usecase "Read Offline" as UC_READ_OFFLINE
        usecase "Sync Pending Requests" as UC_SYNC
    }

    Guest --> UC_BROWSE
    Guest --> UC_SEARCH
    Guest --> UC_READ
    Guest --> UC_VIEW_BM
    Guest --> UC_GEN_QR
    Guest --> UC_SCAN
    Guest --> UC_ARTIFACT
    Guest --> UC_TTS
    Guest --> UC_WATCH
    Guest --> UC_TRENDING
    Guest --> UC_POPULAR
    Guest --> UC_DISCOVER

    Visitor --|> Guest
    Visitor --> UC_REG
    Visitor --> UC_LOGIN
    Visitor --> UC_PROFILE
    Visitor --> UC_BOOKMARK
    Visitor --> UC_LIKE
    Visitor --> UC_FLAG
    Visitor --> UC_PROGRESS
    Visitor --> UC_LIB
    Visitor --> UC_CONTINUE
    Visitor --> UC_VIEW_BM
    Visitor --> UC_RECENT
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
    Visitor --> UC_DEL_ACC

    Contributor --|> Visitor
    Contributor --> UC_CREATE_STORY
    Contributor --> UC_EDIT_STORY
    Contributor --> UC_GEN_TTS
    Contributor --> UC_GEN_VIDEO
    Contributor --> UC_POLL_VIDEO

    InstitutionManager --|> Contributor
    InstitutionManager --> UC_CREATE_ART
    InstitutionManager --> UC_MODERATE
    InstitutionManager --> UC_MOD_QUEUE
    InstitutionManager --> UC_RESOLVE

    Admin --|> InstitutionManager
    Admin --> UC_DEL_STORY
    Admin --> UC_ANALYTICS
    Admin --> UC_DEL_ACC
```

## Use Case Descriptions

| Use Case | Actor(s) | Description |
|---|---|---|
| Register Account | Guest | Create a new account with username/email/password |
| Login | Guest | Authenticate and receive JWT tokens |
| Browse Stories | Guest, Visitor, Contributor, Manager, Admin | List and view published stories |
| Search Stories | All | Full-text search across stories with filters |
| Read Story | All | View story content in Markdown reader |
| Create Story | Contributor+ | Submit a new cultural story |
| Edit Story | Owner, Manager, Admin | Modify existing story content |
| Bookmark Story | Authenticated | Save story to personal library |
| Like Story | Authenticated | Toggle like on a story |
| Flag Story | Authenticated | Report content for moderation |
| Track Reading Progress | Authenticated | Save scroll position and completion |
| View Curated Feeds | All | Access trending/popular/discover feeds |
| Scan QR Code | All | Scan museum artifact QR code |
| View Artifact | All | View artifact details and related stories |
| Create Artifact | Manager, Admin | Add new artifact to catalog |
| Generate QR Code | Manager, Admin | Create QR code for an artifact |
| Listen to TTS | All | Play audio narration of a story |
| Generate Audio Narration | Contributor+ | Request TTS generation |
| Generate AI Video | Contributor+ | Request Luma AI video generation |
| Take Quiz | Authenticated | Complete a story quiz |
| View Badges | All | Browse earned/available badges |
| View Leaderboard | Authenticated | See top users by XP |
| View Certificate | Authenticated | Download heritage certificate |
| Share Story | All | Share to social platforms |
| View Analytics Dashboard | Admin | View platform metrics |
| Moderate Content | Manager, Admin | Review flagged content |
| Save Story Offline | Authenticated | Cache story for offline reading |
| Read Offline | Authenticated | Read cached content without internet |
| Sync Pending Requests | System | Replay queued offline requests |
