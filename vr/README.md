# Griot VR — Unity application

The standalone VR client for Griot AI. It is launched from the Flutter app by a
`griotvr://launch?token=…` deep link, exchanges that single-use token with the
Django API for a VR-scoped JWT, and then loads an experience.

```
Flutter ──griotvr://launch?token=…──► Unity ──HTTPS──► Django REST API
```

**This repository does not contain build artefacts.** `Assets/`, `Packages/`
and `ProjectSettings/ProjectVersion.txt` are versioned; `Library/`, `Temp/`,
`Logs/`, `Build/` and `UserSettings/` are not (see `.gitignore`). Unity
regenerates the remaining `ProjectSettings/*.asset` files the first time the
project is opened.

## Requirements

| | |
|---|---|
| Unity | 6000.0 LTS (see `ProjectSettings/ProjectVersion.txt`) |
| Target | Android, Meta Quest (standalone), ARM64, IL2CPP |
| XR | OpenXR + XR Interaction Toolkit |
| Backend | Griot Django API over HTTPS |

## First-time setup

1. **Open the project** in Unity Hub with the Editor version in
   `ProjectSettings/ProjectVersion.txt`. Let Unity resolve packages from
   `Packages/manifest.json`. If the Package Manager reports a package version
   that does not exist for your Editor, update that entry through
   *Window → Package Manager* — the versions in the manifest are the ones this
   project was written against, not the only ones that work.
2. **Run the automated setup**: *Tools → Griot → Setup VR Project*. It applies
   Force Text serialisation + visible meta files, the Android player settings
   (package `org.africanteller.griotvr`, IL2CPP, ARM64, min API 29, Linear
   colour space, Vulkan/GLES3), Active Input Handling = Input System Package,
   the four build scenes (Bootstrap → Loading → CameroonHeritageMuseum →
   Museum), points `Assets/Materials` at the shader matching the active
   render pipeline (Standard or URP/Lit — the materials serialize both
   property sets, so either answer keeps their colours), the OpenXR loader
   with Meta Quest Support + the Oculus Touch profile, and installs the
   locomotion rig into `Bootstrap`: it copies the XRI **Starter Assets**
   sample into `Assets/Samples/`, instantiates the `XR Origin (XR Rig)`
   prefab (teleport, snap turn, optional smooth locomotion, ray/direct/poke
   interactors per hand) and attaches `VRPlayerController` +
   `VRTeleportController`. Restart the Editor if Unity asks about the
   input-handling change.
3. **Read the Console report.** Everything the setup could not automate (it
   needs the XR Plug-in Management panel to have been opened once before it
   can assign the loader) is listed with the exact panel to open — nothing is
   skipped silently. Re-run the menu after fixing; *Tools → Griot → Add XR
   Origin To Open Scene* repeats only the rig/locomotion step for the scene
   you have open, and *Tools → Griot → Setup Locomotion and Interaction* runs
   just that step for `Bootstrap`.
4. **API config** *(Milestone 6)*: optional. *Assets → Create → Griot → API
   Config*, set `Base Url` to the deployed API (`https://…/api`), and assign
   it to the bootstrap component. No credential is stored in this asset or in
   the project — the only token the app ever holds arrives at runtime through
   the deep link. Without an asset the app uses a runtime default: the
   deployed API on device, and the offline **mock stub** in the Editor, so
   pressing Play exercises the whole connection pipeline without ever
   contacting production. Without a launch link the app boots into the
   Cameroon Heritage Museum scene on its local, sourced content.

## Verify the deep link before building the app

The handoff is the part most likely to need a second iteration, so test it on a
device as soon as the project builds:

```bash
adb install -r build/griotvr.apk

# Cold start (app not running): Unity reads Application.absoluteURL
adb shell am start -a android.intent.action.VIEW \
  -d "griotvr://launch?token=TESTTOKENVALUE0123456789&experience=1&artifact=1"

# Warm start (app already running): Application.deepLinkActivated fires
adb shell am start -a android.intent.action.VIEW \
  -d "griotvr://launch?token=TESTTOKENVALUE0123456789&experience=1"
```

Both forms must reach `DeepLinkManager`. If neither does, the manifest override
in `Assets/Plugins/Android/AndroidManifest.xml` was not merged (check the merged
manifest under `Temp/StagingArea/`), or `launchMode` is the wrong one for the
form being tested.

A token of the shape above is *not* valid server-side — the exchange will
answer `invalid_token` (400). That is the correct outcome and still proves the
link arrived; use the real flow from the Flutter app for an end-to-end run.

## Verify movement and interaction (Milestone 2)

Always start Play from **Bootstrap** — the `XR Interaction Manager` is created
by `VRInteractionManager` on the persistent bootstrap object, so scenes
entered directly in Play mode have no manager. In the Editor the quickest check
is *Window → XR → XR Device Simulator* (enable it in *Project Settings → XR
Plug-in Management → XR Device Simulator*); on a Quest use *Build and Run*.

What must work in the Museum scene:

* **Tracking** — head and both controllers move the camera and ray.
* **Snap turning** — right stick, one step per flick; the rig rotates, never
  the camera alone.
* **Teleport** — point the thumbstick to raise the arc, aim at the floor
  (a `GriotTeleportArea`), release to move. Facing is preserved
  (`MatchOrientation.WorldSpaceUp`).
* **Smooth locomotion** *(optional, comfort setting)* — left stick walks the
  rig. To ship without it, disable the `Move` child under the rig's
  *Locomotion* group; snapping and teleporting keep working.
* **Select / grab** — aim a ray at a marker cube and press the trigger: the
  cube tints brand bronze (`#C68B29`), the controller gives a short haptic
  pulse, and releasing the trigger drops it. The cubes self-configure through
  `GriotInteractable`; the floor through `GriotTeleportArea`.

The camera is never shaken, zoomed or rotated directly by project code —
comfort rules from the milestone plan.

## Verify the museum environment (Milestone 3)

Play from **Bootstrap**: the rig loads into `CameroonHeritageMuseum` and
`EnvironmentLoader` places it at the *Player Spawn* in front of the entrance.
What must hold:

* **Room** — a 14 × 10 m gallery with an open doorway, indigo feature wall,
  six pedestals (pedestal 1, nearest the entrance on the left, hosts the first
  real artifact since Milestone 4; the other five still show the small indigo
  placeholder cube) and two information panels near the entrance.
* **Lighting** — warm accent lights over the pedestal rows plus an entrance
  fill; no real-time shadows (Quest budget). Materials are brand indigo
  `#1E2B58` and bronze `#C68B29`.
* **Movement** — teleport across the whole floor (`GriotTeleportArea`),
  snap turning, and the spawn faces into the room (+Z) so nobody arrives
  staring at a wall.
* **Console** — one line: `[GriotVR] Environment ready: Cameroon Heritage
  Museum (cameroon-heritage-museum).` Warnings about `playerSpawn` or an
  empty `environmentId` mean the `HeritageEnvironment` component on the
  scene root lost its references.

The scene is intentionally self-contained: it references no package scripts
except `GriotTeleportArea`, so it stays loadable while milestones land.
Re-run *Tools → Griot → Setup VR Project* after switching render pipelines —
its materials step re-targets the shaders.

## Verify the first artifact (Milestone 4)

Still from **Bootstrap**, walk or teleport to pedestal 1 (front left). What
must hold:

* **Artifact** — the indigo placeholder cube on pedestal 1 is gone; in its
  place stands a bronze-framed cloth with an always-visible name plate
  reading *Ndop Textile*. The visual is primitives + project materials — a
  stand-in until the real artifact assets arrive.
* **Point** — aim the ray at the frame: it tints brand bronze while hovered
  (`ArtifactInteractable`), same hover language as the marker cubes.
* **Select** — press the trigger: a world-space information panel opens to
  the right of the artifact with the title, description, **Learn More**
  (expands to the historical significance and its source) and **Close**.
  Both buttons respond to the ray (`TrackedDeviceGraphicRaycaster` +
  `XRUIInputModule`; the first open creates the `EventSystem` if the rig
  didn't ship one).
* **Console** — `[GriotVR] Artifact ready: Ndop Textile (ndop-textile) on
  Artifact Areas.` No API calls: the text is local, sourced from the Mingei
  International Museum *Blue Gold* catalogue, and stored on the
  `ArtifactSpawner` component so Milestone 5 can swap it for the Django
  payload field-for-field.

## Verify the Unity ↔ Django connection (Milestone 6)

Two ways in, same pipeline:

* **Mock (no backend)** — press Play from **Bootstrap** with no API Config
  asset assigned. The runtime default turns mock mode on in the Editor; the
  stub payload flows through the exact same exchange → deserialize → merge
  path as a live one.
* **Live** — start the Django API, assign an API Config with its `Base Url`,
  and launch from the Flutter app (`Explore in VR`) so the deep link carries
  a real single-use token. On a device, test the cold-start and warm-start
  `adb` forms from the section above: a fake token correctly answers
  `invalid_token` and shows the error panel.

What must hold:

* **Console** — `[GriotVR] API config: …`, then `POST
  vr/launch/exchange/ → 200` and `[GriotVR] Experience loaded: '…' (N
  artifacts, scene '…')`. The token itself never appears in a log line.
* **Scene choice** — the environment comes from the payload's
  `scene_identifier` when the build contains that scene; otherwise the
  configured fallback loads with a warning, never a blank headset.
* **Artifact text** — pedestal 1 shows the payload's artifact (mock:
  the name plate reads *Ndop Textile (Mock)*). Change the artifact's
  `description` or `historical_significance` in the Django admin, relaunch
  from the phone, and the panel shows the new text — that is the milestone's
  success condition. Fields the curator left blank keep the scene's local
  sourced copy instead of going empty.
* **Viewed reporting** — opening an artifact while a session is active
  sends `PATCH vr/progress/` with the cumulative viewed list; with no
  session (local or mock-without-launch) no request is made at all.
* **Failures** — expired/used link, airplane mode, and an unreachable
  server each end in the world-space error panel with headset-readable
  copy (`AuthManager.UserMessageFor`), and the museum stays usable on
  scene-local content behind it.

## Mobile VR (SHINECON viewer + phone)

The same build target also runs the museum on a phone slipped into a
SHINECON passive viewer — gyroscope head tracking, side-by-side stereo,
gaze-and-tap input, no headset hardware. The Bootstrap component's
**Runtime Mode** picks the path:

| Mode | When it applies |
| --- | --- |
| `Auto` (default) | Live XR session → headset; any mobile platform → phone; desktop Editor → headset (historic default). |
| `MobileVR` | Forced — this is how the Editor simulates the phone. |
| `HeadsetVR` | Forced — ignore the phone even on Android. |

### Run it in the Editor (simulation)

1. Open **Bootstrap**, set **Runtime Mode → Mobile VR**, press Play.
2. Console prints `[GriotVR] EDITOR SIMULATION: head tracking is
   mouse-driven` — move the mouse to look, **WASD** to walk, single
   click (after ~0.3 s) to select, double click to recenter. The
   half-screen stereo pair and the reticle behave exactly as on device.

### Build and install the phone APK

1. `Tools → Griot → Mobile VR: Disable OpenXR for Android (Phone APK)` —
   OpenXR packages stay installed; only the Android loader assignment is
   removed so no XR session ever starts on the phone.
2. **Either** `Tools → Griot → Mobile VR: Build Phone APK` (one shot: runs
   the disable step, writes the scene list, outputs
   `Builds/GriotVR-Phone.apk`; also batch-invokable via `-executeMethod
   Griot.VR.EditorTools.GriotVrMobileBuild.BuildPhoneApk`) **or**
   `File → Build Profiles → Build` an APK manually (IL2CPP/ARM64 are
   project defaults). Then `adb install -r <apk>` on the HOT 60i (or any
   phone with a gyroscope, Android 8+). The debug-keystore signature is
   fine for sideloading; set a release keystore before Play Store
   distribution.
3. For a backend-free validation run, also toggle
   `Tools → Griot → Mobile VR: USE_MOCK_API (Android)` — it stubs the API
   and forces the phone runtime. **Clear it for real sessions.**
4. Launch by tapping **Explore in VR** in the Flutter app
   (`griotvr://launch` deep link, cold or warm start) or from the app
   icon (local scene content only, exactly like the headset flow).

### In the viewer

* **Calibration** — hold the phone straight ahead, then **double tap**
  the screen: that pose becomes forward, and the hint card disappears
  for the session. Double tap again any time to recenter.
* **Look and tap** — gaze settles the reticle on an artifact, marker or
  button; a single tap opens it. Bronze + larger = hover, flash =
  selected. Navigation rings float at the standing spots in front of
  every artifact — gaze one and tap to hop there (instant, no smooth
  locomotion).
* **No gyroscope?** — the app still boots (static diagnostic view) and
  shows `GriotVR requires a gyroscope for VR head tracking.` in the
  error panel instead of freezing silently.

### Restore the headset path

`Tools → Griot → Mobile VR: Enable OpenXR for Android (Headset APK)`
reassigns the loader; combined with Runtime Mode `Auto`/`HeadsetVR`
this is byte-for-byte the Milestone 1–6 Quest behaviour.

### Performance

Frame pacing on the phone defaults to **60 fps, vsync off**
(`MobileVRPerformanceSettings`). To tune it, create
*Assets → Create → Griot → Mobile VR Performance Settings* and assign it
to the Bootstrap component's **Mobile Performance Settings** field — no
code change needed.

Known hardware caveats (measured on device, not in CI): gyro axis
calibration can be corrected per device with the head tracker's
**Orientation Compensation** quaternion if a phone reports a rotated
frame; and frame timings must be profiled on the HOT 60i itself — the
Editor simulation says nothing about device thermal behaviour.

## Layout

```
Assets/
├── Scripts/
│   ├── Authentication/   deep link → LaunchData → VRAuthService → token
│   ├── Network/          GriotApiClient, AuthManager, API models, config, mock stub
│   ├── VR/               bootstrap, runtime seam (IGriotVRRuntime + headset impl), rig, teleport, interactables
│   ├── MobileVR/         phone runtime: stereo rig, gyro tracker, gaze, reticle, markers, tap input
│   ├── Environment/      HeritageEnvironment marker + EnvironmentLoader rig placement
│   ├── Artifacts/        spawn and present a placed artifact
│   ├── Stories/          the story panel
│   ├── Audio/            narration playback
│   └── UI/               error panel, Ask Griot panel
├── Plugins/Android/      the `griotvr://launch` intent filter, headtracking feature flags
├── Editor/               Tools → Griot setup menu + mobile build switches (OpenXR loader, USE_MOCK_API)
├── Scenes/               Bootstrap, Loading, CameroonHeritageMuseum, Museum
├── Prefabs/              MuseumRoom, ArtifactPedestal, InformationPanel
├── Materials/            museum surfaces + brand indigo/bronze (Standard & URP properties)
├── Audio/ Settings/
```

Rules the code holds to, because a headset is the least debuggable client in
the system:

* **No API calls from scene or UI scripts.** `GriotVrBootstrap` orchestrates;
  `GriotApiClient` is the only type that touches the network.
* **No secrets on the device.** `VRTokenStore` keeps the session token in
  memory only. It is never written to `PlayerPrefs`, a file, or a log line.
* **No direct database or model-provider access.** Django is authoritative.
* **Every failure is shown.** Offline, expired link, unavailable experience and
  malformed responses all end in `VrErrorPanel` with copy written for a person
  wearing a headset.
