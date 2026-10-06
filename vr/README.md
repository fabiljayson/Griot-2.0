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
2. **Force text serialisation** (`Edit → Project Settings → Editor → Asset
   Serialization → Force Text`) and **visible meta files** for version control.
3. **Player settings**: *Android* → Package Name
   `org.africanteller.griotvr` (must match
   `frontend/lib/features/vr/vr_constants.dart` and the Flutter manifest's
   `<queries>`), Scripting Backend **IL2CPP**, Target Architectures **ARM64**,
   Minimum API Level **29**.
4. **XR Plug-in Management** → Android → enable **OpenXR**, then in
   *OpenXR → Feature Groups* enable **Meta Quest Support**.
5. **Scenes**: create `Bootstrap`, `Loading` and `Museum` scenes, add them to
   *Build Settings* in that order (Bootstrap at index 0), and put a GameObject
   with `GriotVrBootstrap` in `Bootstrap`.
6. **API config**: *Assets → Create → Griot → API Config*, set `Base Url` to
   the deployed API (`https://…/api`), and assign it to the bootstrap
   component. No credential is stored in this asset or in the project — the
   only token the app ever holds arrives at runtime through the deep link.

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

## Layout

```
Assets/
├── Scripts/
│   ├── Authentication/   deep link → LaunchData → VRAuthService → token
│   ├── API/              GriotApiClient, config, typed exceptions
│   ├── Models/           JSON shapes (mirrors vr/serializers.py)
│   ├── VR/               bootstrap, scene loading, session tracking
│   ├── Artifacts/        spawn and present a placed artifact
│   ├── Stories/          the story panel
│   ├── Audio/            narration playback
│   └── UI/               error panel, Ask Griot panel
├── Plugins/Android/      the `griotvr://launch` intent filter
├── Scenes/               Bootstrap, Loading, Museum
├── Prefabs/ Materials/ Audio/ Settings/
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
