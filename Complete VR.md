# GRIOT AI + VR — MILESTONE IMPLEMENTATION PROMPTS

## MILESTONE 0 — PROJECT AUDIT & ARCHITECTURE

### Objective

Before writing any code, inspect the existing Griot AI project and understand its current architecture.

### Prompt

```text
You are working on my existing Griot AI project.

IMPORTANT:
- The current frontend is Flutter.
- The current backend is Django + Django REST Framework.
- There is NO React frontend.
- Do NOT replace Django with FastAPI.
- Do NOT rewrite existing functionality.
- The new feature is a separate Unity VR client targeting Meta Quest.

Before changing any code, inspect the existing project.

Analyze:

1. Flutter project structure
2. Django project structure
3. Existing Django models
4. Existing REST API structure
5. Authentication implementation
6. User model
7. Story model
8. Artifact model
9. Region model
10. Quiz model
11. Progress/bookmark/like systems
12. Existing AI storytelling implementation
13. Existing media/file handling
14. Existing navigation
15. Existing theme/design system

Determine which existing models and APIs can be reused for VR.

Do NOT create duplicate models if equivalent models already exist.

Produce:

- Current architecture summary
- Relevant existing files
- Models that VR should reuse
- APIs that VR should reuse
- New components required for VR
- Proposed Unity/Django integration architecture
- Files that would eventually need modification

DO NOT modify files yet.

Wait for approval before making implementation changes.
```

### Success condition

You understand the existing system before touching it.

---

# MILESTONE 1 — UNITY VR PROJECT FOUNDATION

### Objective

Create the basic Unity VR application and make Meta Quest recognize it.

### Prompt

```text
Implement Milestone 1 of the Griot AI VR integration.

Create a separate Unity project named:

GriotVR

Target:

- Meta Quest 2
- Meta Quest 3
- Meta Quest 3S

Use:

- Unity
- OpenXR
- Meta Quest compatible Android configuration

Do NOT modify the existing Flutter or Django projects yet.

Configure:

1. Android build support
2. OpenXR
3. VR/XR plugin configuration
4. XR Origin
5. Main Camera
6. Left controller
7. Right controller
8. Basic VR input
9. Quest-compatible build settings

Create this structure:

Assets/GriotVR/
├── Scenes/
│   └── Bootstrap.unity
├── Scripts/
│   ├── Core/
│   └── VR/
├── Prefabs/
├── Materials/
├── Models/
├── Audio/
└── UI/

Create:

GriotVRBootstrap.cs
VRPlayerController.cs

The application must launch into a basic VR scene.

Do not implement Django integration yet.

Do not implement AI yet.

Do not implement multiplayer.

Do not implement casting.

Test that the application can build and run on the target Meta Quest headset.

At the end, report:

- Unity version
- Packages installed
- OpenXR configuration
- Android configuration
- Files created
- Build result
- Any remaining problems
```

### Success condition

🥽 Put on Quest → GriotVR launches → headset tracking works.

---

# MILESTONE 2 — VR MOVEMENT & INTERACTION

### Objective

Make the VR player comfortable and functional.

### Prompt

```text
Implement Milestone 2 of Griot AI VR.

Continue from the existing GriotVR Unity project.

Implement:

1. VR head tracking
2. Controller tracking
3. Teleportation
4. Snap turning
5. Optional smooth locomotion
6. Interaction ray
7. Object selection
8. Basic grab/select interaction

Create:

Scripts/VR/
├── VRPlayerController.cs
├── VRTeleportController.cs
└── VRInteractionManager.cs

Use Unity's XR interaction systems where appropriate rather than unnecessarily implementing low-level VR input.

VR comfort requirements:

- Teleportation must work.
- Snap turning must work.
- Smooth movement must be optional.
- Never force camera movement.
- Never shake the camera.
- Do not automatically move the player's viewpoint.

Create a simple test scene containing:

- Floor
- Several cubes
- Interactable objects

The user must be able to:

- Move around
- Turn
- Point at objects
- Select objects
- Grab/select test objects

Do not implement Django yet.

Do not implement AI yet.

Test on Meta Quest.
```

### Success condition

🥽 User can comfortably move around and interact with objects.

---

# MILESTONE 3 — CAMEROON HERITAGE MUSEUM

### Objective

Replace the test environment with the first Griot AI heritage environment.

### Prompt

```text
Implement Milestone 3 of Griot AI VR.

Create the first Griot AI VR environment:

Cameroon Heritage Museum

Create:

Scenes/
└── CameroonHeritageMuseum.unity

Environment components:

- Museum entrance
- Main hall
- Floor
- Walls
- Ceiling
- Artifact areas
- Pedestals
- Information areas
- Navigation space
- Lighting

Use the Griot AI visual identity where appropriate:

Primary Indigo:
#1E2B58

Bronze:
#C68B29

Do not use excessive gradients.

The environment should feel like a respectful African/Cameroonian cultural museum, not a generic sci-fi environment.

Create:

Scripts/Environment/
├── HeritageEnvironment.cs
└── EnvironmentLoader.cs

Create reusable prefabs:

Prefabs/
├── MuseumRoom.prefab
├── ArtifactPedestal.prefab
└── InformationPanel.prefab

Prioritize:

- VR performance
- Stable frame rate
- Low-poly/optimized assets
- Efficient lighting
- Comfortable navigation

Do not implement Django yet.

Do not hard-code large amounts of cultural information.

At this stage the environment only needs placeholder artifact locations.

Test the complete environment on Meta Quest.
```

### Success condition

🏛️ Quest → enter a recognizable Griot AI Cameroon heritage museum.

---

# MILESTONE 4 — FIRST CULTURAL ARTIFACT

### Objective

Add the first real interactive artifact.

### Prompt

```text
Implement Milestone 4.

Add the first cultural artifact to the Griot AI VR museum.

Use:

Ndop Textile

IMPORTANT:
Do not invent historical information.
Use verified content from the existing Griot AI project if available.

Create:

Scripts/Artifacts/
├── ArtifactInteractable.cs
├── ArtifactController.cs
└── ArtifactSpawner.cs

Create an artifact pedestal.

The artifact must:

1. Be positioned correctly.
2. Have an appropriate collider.
3. Be interactable.
4. Highlight when targeted.
5. Display its name.
6. Display a cultural description.
7. Open a VR information panel.

The UI should look like:

--------------------------------
Ndop Textile

[Description]

[Learn More]
[Close]
--------------------------------

Use world-space UI.

Make text large enough to read comfortably in VR.

The artifact data should eventually come from Django, but for this milestone use a clean local data structure that can later be replaced by API data.

Do not hard-code the API into the artifact component.

Test interaction on Meta Quest.
```

### Success condition

🧵 User approaches artifact → points at it → selects it → information appears.

---

# MILESTONE 5 — DJANGO VR API

### Objective

Now connect the VR system to the existing Django backend.

### Prompt

```text
Implement Milestone 5.

IMPORTANT:
First inspect the existing Django project.

Reuse existing:

- User model
- Story model
- Artifact model
- Region model
- Authentication
- Existing API conventions

Do NOT create duplicate cultural models.

Create only VR-specific models if they are genuinely necessary.

Potential models:

VRExperience
VRLocation
VRArtifact
VRProgress

Adapt these to the existing architecture.

Implement Django REST endpoints for:

GET VR experiences
GET VR experience details
GET VR artifacts
GET VR locations
GET VR progress
POST/PATCH VR progress

Use the project's existing authentication mechanism.

Create serializers, views/viewsets, URLs, permissions and tests following the existing Django architecture.

Do not modify Flutter yet.

Do not modify Unity yet except where API contract documentation is needed.

Provide example JSON responses for Unity.

Do not expose secrets.

Run Django tests.

Report:

- Models created
- Existing models reused
- Endpoints created
- Authentication behavior
- Example API responses
- Test results
```

### Success condition

🖥️ Django can provide all data required by the VR client.

---

# MILESTONE 6 — UNITY ↔ DJANGO CONNECTION

### Objective

Replace local placeholder artifact data with real backend data.

### Prompt

```text
Implement Milestone 6.

Connect GriotVR Unity to the existing Django REST API.

Create:

Scripts/Network/
├── GriotApiClient.cs
├── ApiModels.cs
└── AuthManager.cs

The API client must support:

GET
POST
PATCH

Implement:

GET /api/v1/vr/experiences/{id}/

or the equivalent endpoint created by the Django implementation.

Unity must:

1. Authenticate securely.
2. Request the VR experience.
3. Deserialize the response.
4. Load the environment.
5. Load artifact metadata.
6. Place artifacts according to backend data.
7. Display artifact information.

Do not hard-code cultural content into Unity.

Do not put Django secrets or AI API keys inside Unity.

Handle:

- Timeout
- HTTP errors
- Authentication failure
- Expired token
- Missing artifact
- Backend unavailable

Create a mock API mode for development.

Test:

Django running
↓
Unity
↓
API request
↓
Artifact data
↓
VR artifact displayed
```

### Success condition

🌐 Change artifact data in Django → Unity receives the changed data.

---

# MILESTONE 7 — GRIOT AI STORYTELLER IN VR

### Objective

Bring the actual Griot AI storyteller into VR.

### Prompt

```text
Implement Milestone 7.

Add:

"Ask Griot AI"

to the artifact information panel.

Flow:

User selects artifact
↓
Selects "Ask Griot AI"
↓
VR sends request to Django
↓
Django validates artifact
↓
Django uses existing Griot AI storytelling system
↓
AI generates grounded response
↓
Django returns response
↓
Unity displays response

Create:

Unity:
Scripts/AI/
└── VRStoryteller.cs

Django:
Use the existing AI implementation if available.

Do NOT put any AI provider API key inside Unity.

The AI must be grounded in verified Griot AI cultural content.

If reliable information is unavailable, the AI should clearly indicate that rather than inventing facts.

The VR UI should include:

Loading state
AI response
Close button

Handle:

- AI timeout
- API failure
- Empty response
- Network failure

Do not implement voice yet.
```

### Success condition

🤖 User selects an artifact → asks Griot AI → receives an intelligent cultural explanation inside VR.

---

# MILESTONE 8 — AI VOICE / NARRATION

### Objective

Allow Griot AI to speak.

### Prompt

```text
Implement Milestone 8.

Add voice narration to the Griot AI VR storyteller.

Architecture:

Unity
↓
Django
↓
AI-generated text
↓
Text-to-Speech service
↓
Audio
↓
Unity AudioSource

Create:

Scripts/AI/
└── NarrationManager.cs

The narration system must be provider-independent.

Create an abstraction such as:

INarrationService

Do not hard-code a specific TTS provider.

Unity must not contain TTS API secrets.

Implement:

[Listen]
[Stop]
[Replay]

The audio should use spatial/3D audio where appropriate.

Add graceful failure:

"If narration is temporarily unavailable, the text response is still available."

Test narration on Meta Quest.
```

### Success condition

🔊 Griot AI can tell the user the story aloud inside VR.

---

# MILESTONE 9 — VR PROGRESS SYNCHRONIZATION

### Objective

Synchronize VR exploration with the user's Griot AI account.

### Prompt

```text
Implement Milestone 9.

Connect VR exploration progress to Django.

Track meaningful events:

- Entered VR experience
- Viewed artifact
- Completed artifact
- Completed room
- Completed experience

Do NOT send network requests every frame.

Create:

Unity:
Scripts/Progress/
└── VRProgressManager.cs

Django:
VRProgress endpoint

Synchronize:

experience_id
artifact_id
completion_percentage
last_seen_at
completed

When the user returns to the experience, retrieve their previous progress.

Display:

VR Experience
Progress: 65%

Do not duplicate the existing Flutter progress system unnecessarily.

Reuse existing user identity and progress architecture where appropriate.
```

### Success condition

📊 Explore in VR → leave → return → previous progress is restored.

---

# MILESTONE 10 — FLUTTER → VR LAUNCH

### Objective

Allow users to enter VR from the Griot AI mobile application.

### Prompt

```text
Implement Milestone 10.

Add a VR entry point to the existing Flutter application.

Example:

Discover
↓
Heritage Experience
↓
Explore in VR

The Flutter app should:

1. Verify authentication.
2. Request a short-lived VR launch token from Django.
3. Request the selected VR experience.
4. Attempt to launch GriotVR.
5. Pass only temporary launch information.

Use a secure deep-link/app-link mechanism.

Conceptually:

griotvr://launch

Do NOT put permanent credentials in the URI.

Do not hard-code secrets.

If GriotVR is not installed, display a clear fallback message.

Do not modify existing Flutter navigation unnecessarily.

Follow the existing Flutter MVVM architecture.
```

### Success condition

📱 Flutter → tap **Explore in VR** → 🥽 GriotVR launches.

---

# MILESTONE 11 — QUEST CASTING

### Objective

Allow other people to watch the VR user's experience.

### Prompt

```text
Implement Milestone 11.

Do NOT build a custom VR video streaming server.

Use the native Meta Quest casting functionality.

The final architecture should be:

Unity
↓
Meta Quest
↓
Native Quest Casting
↓
PC / Phone / TV

The Django backend must NOT carry the VR video stream.

Document the supported casting workflow for:

- Development
- Demonstration
- Museum/public display

The VR application itself should remain responsible only for rendering the VR experience.

Verify that the headset view can be mirrored while the user explores the Griot AI museum.
```

### Success condition

📺 Someone outside the headset can watch the user's VR experience.

---

# MILESTONE 12 — VR PERFORMANCE & OPTIMIZATION

### Objective

Prepare the application for a reliable Quest demonstration.

### Prompt

```text
Implement Milestone 12.

Optimize GriotVR for Meta Quest.

Analyze:

- Frame rate
- CPU usage
- GPU usage
- Draw calls
- Texture memory
- Polygon counts
- Lighting
- Physics
- Garbage collection
- Network calls

Optimize:

- 3D models
- Materials
- Textures
- Lighting
- Colliders
- UI
- API requests

Use:

- Baked lighting where appropriate
- LOD where appropriate
- Occlusion culling where appropriate
- Texture compression
- Object pooling where useful

Do not introduce visual effects that significantly reduce VR performance.

Maintain comfortable VR movement.

Test on the target Quest headset.

Report performance measurements and remaining bottlenecks.
```

### Success condition

🥽 Stable, comfortable VR experience suitable for demonstration.

---

# MILESTONE 13 — SECURITY & ERROR HANDLING

### Objective

Make the integration production-safe.

### Prompt

```text
Implement Milestone 13.

Review the complete Griot AI VR integration for security.

Verify that Unity contains NONE of:

- Django SECRET_KEY
- Database password
- AI provider API key
- Admin credentials
- Permanent signing secrets

Implement:

- HTTPS
- Short-lived VR launch tokens
- Server-side authorization
- Token expiration
- API permission validation
- Request validation
- Rate limiting where appropriate

Handle:

- Offline mode
- Backend unavailable
- AI unavailable
- Expired token
- Invalid artifact
- Missing asset
- Corrupt API response

The application must never crash because a remote API is unavailable.

Produce a security review report.
```

### Success condition

🔐 VR integration does not expose backend or AI secrets and fails gracefully.

---

# MILESTONE 14 — COMPLETE END-TO-END DEMO

### Objective

Combine all previous milestones into one complete demonstration.

### Prompt

```text
Implement Milestone 14.

Perform an end-to-end test of Griot AI + VR.

The demonstration scenario must be:

1. User opens Griot AI Flutter.
2. User navigates to a heritage experience.
3. User selects "Explore in VR".
4. Flutter requests a temporary VR launch token.
5. GriotVR launches.
6. User enters the Cameroon Heritage Museum.
7. User moves through the museum.
8. User approaches the Ndop Textile.
9. Artifact highlights.
10. User interacts with it.
11. Information panel appears.
12. User selects "Ask Griot AI".
13. Django processes the AI request.
14. Griot AI generates a grounded cultural explanation.
15. Unity displays the response.
16. User selects "Listen".
17. Narration plays.
18. Artifact progress is recorded.
19. User exits.
20. Progress is synchronized.
21. User can cast the Quest view to a display.

Test the entire flow.

Fix integration problems without rewriting working architecture.

Produce a final architecture diagram and test report.
```

### Success condition

🔥 The complete Griot AI → VR → AI → narration → progress → casting workflow works.

---

# MILESTONE 15 — EXPANSION SYSTEM

### Objective

Make it easy to add many African heritage experiences.

### Prompt

```text
Implement Milestone 15.

Refactor the VR system so new heritage experiences can be added without modifying core Unity code.

The backend should define:

Experience
Room
Location
Artifact
Story
Media
Interaction

Unity should dynamically load the appropriate content.

The architecture should support future experiences such as:

- Cameroon Heritage Museum
- Foumban Cultural Experience
- Grassfields Kingdoms
- Ndop Textile Experience
- Traditional Architecture
- African Oral Storytelling Environment
- Historical Locations
- Virtual Museum Tours

Do not hard-code individual experiences into the core systems.

Create reusable:

- Experience loader
- Artifact loader
- Room loader
- Interaction system
- UI system
- Narration system
- Progress system

The goal is:

New experience added in Django
↓
Unity retrieves it
↓
Experience becomes available in VR

without rewriting the Unity application.
```

### Success condition

🌍 Griot AI can grow from one VR museum into a complete African heritage VR platform.