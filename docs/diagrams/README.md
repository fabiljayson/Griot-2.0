# Griot 2.0 — UML Diagrams

> Complete UML documentation for the Griot 2.0 African Teller platform.
> All diagrams are written in **Mermaid** syntax and can be rendered in GitHub, VS Code (with Mermaid extension), or the [Mermaid Live Editor](https://mermaid.live).

---

## 📋 Diagram Index

| # | Diagram | File | Description |
|---|---------|------|-------------|
| 1 | **Use Case** | [01-use-case-diagram.md](01-use-case-diagram.md) | All actors (Guest, Visitor, Contributor, Manager, Admin) and their use cases across all features |
| 2 | **Class** | [02-class-diagram.md](02-class-diagram.md) | Backend Django models and frontend Dart classes with full fields, methods, and relationships |
| 3 | **Package** | [03-package-diagram.md](03-package-diagram.md) | Frontend feature modules and backend Django app structure with dependency relationships |
| 4 | **Sequence** | [04-sequence-diagram.md](04-sequence-diagram.md) | 6 key user flows: Auth, Story Reading, QR Scan, Quiz, Offline Sync, Video Generation |
| 5 | **Communication** | [05-communication-diagram.md](05-communication-diagram.md) | Inter-component message flow for Story Reading, Auth, Offline Queue, QR Scan, Media Generation |
| 6 | **State** | [06-state-diagram.md](06-state-diagram.md) | State machines for Story Status, Quiz Attempt, Media Job, Offline Request, Auth State, Moderation |
| 7 | **Deployment** | [07-deployment-diagram.md](07-deployment-diagram.md) | System deployment architecture, dev vs production, infrastructure components |
| 8 | **Component** | [08-component-diagram.md](08-component-diagram.md) | High-level system components, internal structure, communication matrix, interface contracts |
| 9 | **Activity** | [09-activity-diagram.md](09-activity-diagram.md) | Business process flows: Registration, Story Creation, Quiz Taking, Offline Sync, QR Discovery, Video Generation |

---

## 🎯 Coverage Summary

### Actors Covered (Use Case)
- Guest (unauthenticated)
- Visitor (authenticated, role: visitor)
- Contributor (role: contributor)
- Institution Manager (role: institution_manager)
- Admin (role: admin)
- External: Luma AI, TTS Service

### Classes Modeled (Class)
- **Backend:** User, Story, StoryCategory, StoryBookmark, StoryLike, StoryFlag, StoryShare, ReadingProgress, Artifact, QRCodeScan, Quiz, QuizQuestion, QuizAttempt, Badge, UserBadge, UserProfile, Certificate, VideoGenerationJob, AudioNarrationJob
- **Frontend:** ApiClient, AuthInterceptor, ConnectivityService, OfflineSyncManager, AuthRepository, AuthProvider, StoryModel, StoryListNotifier, StoryRepository

### Packages Mapped (Package)
- Frontend: core (constants, database, network, offline, providers, theme) + features (auth, home, stories, library, qr_scanner, audio, video, gamification, sharing, admin)
- Backend: users, stories, qr_codes, gamification, media_app, api

### Flows Sequenced (Sequence)
1. Authentication (Login → Token Refresh)
2. Story Reading + Progress Tracking
3. QR Code Scan → Artifact Detail
4. Gamification Quiz Flow
5. Offline → Online Sync
6. AI Video Generation

### States Modeled (State)
1. Story Status Lifecycle (Draft → Pending → Published → Archived)
2. Quiz Attempt (InProgress → Completed/TimedOut)
3. Media Job (Pending → Processing → Completed/Failed)
4. Offline Request (Pending → InProgress → Completed/Failed)
5. Auth State (Initial → Loading → Authenticated/Unauthenticated)
6. Content Moderation (NoFlags → Flagged → UnderReview → Resolved)

### Activities Documented (Activity)
1. User Registration & Onboarding
2. Story Creation & Moderation
3. Quiz Taking & Gamification
4. Offline Sync Process
5. QR Code Scan → Artifact Discovery
6. AI Video Generation Process

---

## 🛠️ How to Render

### GitHub
All Mermaid diagrams render automatically in GitHub markdown files.

### VS Code
Install the **Mermaid Preview** extension (`bierner.markdown-mermaid`) to preview diagrams.

### Mermaid Live Editor
1. Copy the code block from any diagram file
2. Paste into [mermaid.live](https://mermaid.live)
3. Export as PNG, SVG, or PDF

### Command Line
```bash
# Install mermaid-cli
npm install -g @mermaid-js/mermaid-cli

# Render a diagram
mmdc -i 01-use-case-diagram.md -o use-case.png
```

---

*Generated August 10, 2026 — Griot 2.0 African Teller*
