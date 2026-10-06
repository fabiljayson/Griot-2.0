You are working on my **Griot AI** project, a cultural heritage platform for preserving and promoting African/Cameroonian cultural heritage through interactive storytelling.

## Project context

The current architecture is:

- **Flutter** — mobile frontend
- **Django + Django REST Framework** — backend/API
- **PostgreSQL** — production database
- **Unity + OpenXR** — VR application
- **Griot AI** — AI storytelling/Q&A layer
- QR codes — physical artifact → digital experience
- 3D cultural artifacts and virtual museum environments

Important: **There is NO React frontend in the current Griot implementation. Do not introduce React or modify the architecture to use React.**

The goal is to add a separate **Unity VR application** that can be launched from the existing Flutter application and communicate with Django.

The desired architecture is:

```text
                    GRIOT AI
                       │
        ┌──────────────┴──────────────┐
        │                             │
     Flutter                      Unity VR
     Mobile                       Application
        │                             │
        │ Android Deep Link            │ HTTPS
        │                             │
        └──────────────┐       ┌──────┘
                       ▼       ▼
                    Django REST API
                          │
             ┌────────────┼────────────┐
             ▼            ▼            ▼
         PostgreSQL     Griot AI    3D/Object
                                    Storage
```

The preferred launch flow is:

```text
Flutter
   │
   │ User taps "Explore in VR"
   ▼
Django
   │
   │ Request short-lived VR launch token
   ▼
Flutter
   │
   │ griotvr://launch?token=XXX&experience=42&artifact=108
   ▼
Android
   │
   ▼
Unity VR
   │
   │ Validate launch token
   ▼
Django REST API
   │
   │ Retrieve VR experience
   ▼
Unity
   │
   ▼
Virtual Museum / Artifact Experience
```

## CRITICAL WORKFLOW RULE

Before modifying anything:

1. Inspect the existing repository.
2. Identify the current Flutter architecture.
3. Identify the existing authentication implementation.
4. Identify the current Django project structure.
5. Identify existing API clients/services.
6. Identify the existing artifact/story models.
7. Identify whether a VR-related structure already exists.
8. Identify Android package/application ID and manifest configuration.
9. Identify the existing environment/configuration strategy.
10. Identify the current development/build setup.

Do NOT immediately start changing files.

First provide me with:

### A. Current architecture assessment

Explain:

- Flutter architecture currently used
- Django architecture currently used
- authentication flow
- API communication flow
- relevant existing models
- relevant existing providers/notifiers/services
- Android configuration
- where the Unity integration should be inserted

### B. Proposed changes

Give me a precise file-by-file implementation plan.

For example:

```text
Flutter
├── lib/...
│   ├── services/vr_service.dart
│   ├── models/vr_experience.dart
│   └── ...
│
└── android/app/src/main/AndroidManifest.xml

Django
├── apps/vr/
│   ├── models.py
│   ├── serializers.py
│   ├── views.py
│   ├── urls.py
│   └── ...
```

Do not assume these exact paths exist. Adapt them to the actual repository.

Unity should be treated as a **separate application/project**, not embedded into Flutter unless inspection shows a compelling existing reason.

---

# Required implementation

After I approve the plan, implement the following.

## 1. Django VR domain

Create/adapt a VR application/module containing concepts such as:

### VRExperience

Potential fields:

```text
id
title
description
slug
thumbnail
scene_identifier
is_active
created_at
updated_at
```

### VRArtifact

Potential relationship:

```text
VRExperience
    │
    └── VRArtifact
             │
             └── Cultural Artifact
```

Do not duplicate existing artifact data if the project already has an Artifact model.

Reuse existing models where appropriate.

A VR experience should be able to reference:

- cultural artifact
- museum
- region
- story
- 3D asset
- environment
- narration
- language
- metadata

---

# 2. Django API

Implement REST endpoints appropriate to the existing API conventions.

At minimum:

```text
POST /api/v1/vr/launch/

GET /api/v1/vr/experiences/<id>/

GET /api/v1/vr/artifacts/<id>/

POST /api/v1/vr/sessions/

POST /api/v1/vr/sessions/<id>/complete/
```

Adapt URLs to the existing project's routing conventions.

The API response for a VR experience should provide enough information for Unity to load the correct experience.

Example conceptual response:

```json
{
  "id": 42,
  "title": "Bamoun Heritage Gallery",
  "description": "...",
  "scene_identifier": "bamoun_gallery",
  "artifacts": [
    {
      "id": 108,
      "name": "Traditional Mask",
      "model_url": "...",
      "story_id": 12
    }
  ]
}
```

Do not expose private storage credentials or sensitive information.

---

# 3. Secure VR launch authentication

Do NOT put:

- Django passwords
- refresh tokens
- permanent API keys
- secret keys

inside the deep link.

Implement a **short-lived, single-purpose VR launch token**.

Preferred conceptual flow:

```text
Flutter
   │
   │ POST /vr/launch/
   ▼
Django
   │
   ├── authenticate user
   ├── validate experience
   ├── create short-lived launch token
   └── return launch information
   ▼
Flutter
   │
   ▼
griotvr://launch?token=...&experience=42
   │
   ▼
Unity
   │
   ▼
Django validates token
```

The token should:

- expire quickly
- be scoped to VR
- preferably be single-use
- be associated with the authenticated user
- be invalid after expiration
- never contain unnecessary sensitive information

Use the project's existing authentication mechanism where possible.

---

# 4. Flutter integration

Add a clean VR service following the project's existing architecture.

The service should:

1. Request a VR launch token from Django.
2. Build the deep-link URI.
3. Launch the Unity VR application.
4. Handle the case where Unity is not installed.
5. Handle launch errors gracefully.

Conceptual usage:

```dart
await vrService.launchExperience(
  experienceId: experience.id,
  artifactId: artifact.id,
);
```

Do NOT hard-code authentication credentials.

Do NOT duplicate existing API clients if the project already has one.

Use the existing dependency injection/provider architecture.

---

# 5. Android deep link

Configure the Unity application's Android manifest to recognize:

```text
griotvr://launch
```

The Unity application should receive:

```text
token
experience
artifact
```

Example conceptual URI:

```text
griotvr://launch?token=ABC123&experience=42&artifact=108
```

Also consider Android App Links/HTTPS for a production implementation if appropriate.

Document why the chosen approach is being used.

---

# 6. Unity VR application

Create the Unity side as a **separate VR application**.

Use:

- Unity
- OpenXR
- C#
- Unity XR Interaction Toolkit where appropriate

The Unity project should contain logical modules such as:

```text
UnityProject/
│
├── Assets/
│   ├── Scenes/
│   ├── Scripts/
│   │   ├── Authentication/
│   │   ├── API/
│   │   ├── VR/
│   │   ├── Artifacts/
│   │   ├── Stories/
│   │   ├── Audio/
│   │   └── UI/
│   │
│   ├── Models/
│   ├── Materials/
│   ├── Audio/
│   └── Prefabs/
```

Adapt this structure if an existing Unity project already exists.

---

# 7. Unity deep-link receiver

Implement a C# component that:

1. receives the Android deep link
2. parses the URI
3. extracts the launch token
4. extracts experience ID
5. optionally extracts artifact ID
6. validates the data
7. contacts Django
8. retrieves the VR experience
9. loads the appropriate Unity scene

Conceptually:

```text
Deep Link
    ↓
DeepLinkManager
    ↓
LaunchData
    ↓
VRAuthService
    ↓
GriotApiClient
    ↓
VRExperienceService
    ↓
SceneLoader
```

Do not put API logic directly inside scene/UI scripts.

---

# 8. Unity API client

Create a reusable C# API layer.

For example:

```text
GriotApiClient
├── AuthenticateVR()
├── GetExperience()
├── GetArtifact()
├── AskGriot()
├── StartSession()
└── CompleteSession()
```

Use asynchronous requests.

Handle:

- HTTP errors
- timeout
- expired token
- no internet
- malformed responses
- unavailable experience

with appropriate user-facing VR error messages.

---

# 9. VR experience loading

Unity should NOT receive the entire 3D experience through the deep link.

The deep link only identifies the experience.

Unity should ask Django:

```text
GET /api/v1/vr/experiences/42/
```

Django returns metadata and asset references.

Then Unity loads:

```text
Experience
    │
    ├── Environment
    ├── Artifacts
    ├── Stories
    ├── Narration
    └── Interactions
```

---

# 10. Griot AI inside VR

The VR application should be able to interact with the existing Griot AI backend.

Example:

```text
User sees artifact
       │
       ▼
"Ask Griot"
       │
       ▼
Unity
       │
       ▼
POST /api/v1/ai/ask/
       │
       ▼
Django
       │
       ├── Artifact context
       ├── Story context
       ├── Cultural context
       └── RAG context
       │
       ▼
Griot AI
       │
       ▼
Django
       │
       ▼
Unity
```

The VR client should not directly call the LLM provider.

Keep AI credentials exclusively on the backend.

---

# 11. Voice

Design the VR architecture so Griot can eventually support:

```text
User voice
    ↓
Speech-to-text
    ↓
Django / Griot AI
    ↓
AI response
    ↓
Text-to-speech
    ↓
Unity audio
```

For the initial implementation, text interaction is acceptable if voice is not already implemented.

Do not introduce unnecessary complexity if the current project does not yet have STT/TTS.

---

# 12. VR session tracking

When Unity starts:

```text
POST /api/v1/vr/sessions/
```

Store:

```text
user
experience
start_time
```

When the user exits:

```text
POST /api/v1/vr/sessions/<id>/complete/
```

Store:

```text
end_time
duration
completion_status
progress
```

Integrate with the existing Griot progress/achievement system if one already exists.

---

# 13. Flutter UX

On the artifact details page, add:

```text
[ Explore in VR ]
```

The button should:

```text
tap
 ↓
check VR availability / configuration
 ↓
request launch token
 ↓
launch Unity
```

If Unity isn't installed:

```text
"VR experience isn't installed on this device."
```

Do not crash the Flutter application.

---

# 14. Architecture quality requirements

Follow these rules:

- Do not duplicate existing code.
- Do not create parallel authentication systems unnecessarily.
- Reuse existing API clients/services.
- Reuse existing Artifact/Story/User models.
- Follow the current project's naming conventions.
- Follow the current state-management architecture.
- Do not hard-code URLs or credentials.
- Use environment configuration.
- Keep secrets out of Git.
- Use HTTPS for production.
- Validate all IDs and tokens server-side.
- Never trust deep-link parameters.
- Keep Unity independent from Flutter internally.
- Keep Django as the authoritative backend.
- Do not connect Unity directly to PostgreSQL.
- Do not connect Flutter directly to PostgreSQL.
- Do not expose AI API keys to Flutter or Unity.

---

# 15. Required sequence diagram

Produce a sequence diagram for:

```text
User
Flutter
Django
Unity
Database
Griot AI
```

covering:

```text
1. User opens artifact
2. User taps Explore in VR
3. Flutter requests launch token
4. Django validates authentication
5. Django creates short-lived token
6. Flutter launches Unity deep link
7. Unity receives deep link
8. Unity validates token
9. Django returns VR experience
10. Unity loads scene
11. User interacts with artifact
12. Unity asks Griot AI
13. Django retrieves cultural context
14. Griot AI generates response
15. Django returns response
16. Unity displays/narrates response
17. Unity records session completion
18. Django updates progress
```

---

# 16. Required final architecture

The implementation must result in this architecture:

```text
                         USER
                           │
                           ▼
                     FLUTTER MOBILE
                           │
                  "Explore in VR"
                           │
                           ▼
                  Django Launch API
                           │
                  Short-lived Token
                           │
                           ▼
                   Android Deep Link
                           │
                           ▼
                      UNITY VR
                           │
                     HTTPS / REST
                           │
                           ▼
                  DJANGO REST API
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
      PostgreSQL       Griot AI        Object Storage
                           │
                    ┌──────┴──────┐
                    ▼             ▼
                   RAG           LLM
                           │
                           ▼
                         TTS
                           │
                           ▼
                      UNITY VR
```

---

# 17. What I expect from you before implementation

**Do not modify files immediately.**

First inspect the repository and give me:

### 1. Existing architecture

### 2. Relevant existing files

### 3. What can be reused

### 4. What needs to be created

### 5. Exact implementation plan

### 6. Risks/conflicts with the existing project

### 7. Proposed API contract

### 8. Proposed Flutter → Unity → Django flow

### 9. Proposed Unity project structure

### 10. Files that will be modified/created

Then **STOP and wait for my confirmation**.

Only after I explicitly approve the plan should you implement the changes.

Do not silently make architectural changes beyond this specification.