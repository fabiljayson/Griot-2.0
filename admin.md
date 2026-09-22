# Griot 2.0 Flutter UI — Critical Visual & Layout Fixes

You are working on the **Griot 2.0 / African Storyteller Flutter application**.

There are several serious UI and asset-rendering problems that must be investigated and fixed properly.

**Do NOT immediately rewrite the screens.**

First inspect the existing implementation, understand how the data flows through the application, identify the actual causes, then propose a repair plan before making changes.

---

# CURRENT PROBLEMS

## 1. SHARE SCREEN — BROKEN ICONS

The Share screen currently displays broken/missing icons.

The problem is NOT acceptable as a final UI state.

Investigate:

* Which icons the Share screen uses.
* Whether they are Flutter `IconData`.
* Whether they come from an icon package.
* Whether they are SVG assets.
* Whether they are PNG/WebP assets.
* Whether the assets actually exist.
* Whether the asset paths are correct.
* Whether `pubspec.yaml` declares the assets.
* Whether the icons are loaded dynamically.
* Whether an icon/font package is missing.
* Whether a recent UI refactor replaced valid icons with invalid references.

### Important

Do NOT replace broken icons with random symbols, stickers, emojis, Unicode characters, or placeholder graphics.

Use proper Flutter icons or the project's actual visual assets.

If the design system already uses a specific icon style, preserve it.

---

# 2. REWARD / GAMIFICATION SCREEN — BOTTOM OVERFLOW

The Reward/Gamification screen currently produces:

```text
BOTTOM OVERFLOWED BY 62 PIXELS
```

This is a real layout bug and must be fixed at its source.

Do NOT simply:

```dart
overflow: ...
```

or hide the content.

Do NOT reduce everything arbitrarily until the warning disappears.

Investigate the actual widget tree.

Look for:

* `Column`
* `Row`
* `Container`
* `SizedBox`
* fixed heights
* fixed widths
* `Expanded`
* `Flexible`
* `ListView`
* `SingleChildScrollView`
* nested scroll views
* `GridView`
* `Wrap`
* bottom padding
* SafeArea
* keyboard/inset handling
* responsive constraints

Determine which widget is causing the 62-pixel overflow.

The final screen must work on:

* small Android phones
* normal Android phones
* larger phones
* different aspect ratios
* portrait orientation

The solution should be responsive rather than hard-coded for one screen size.

---

# 3. STORY IMAGES ARE MISSING

This is a major problem.

The Story UI currently appears without the story images that were provided/intended for the application.

Do NOT leave blank image areas.

Do NOT replace the images with generic placeholders unless the backend genuinely has no image.

Trace the entire image pipeline.

---

## Investigate the backend response

Inspect the actual Story API response.

Determine:

```text
Story
 ↓
image field
 ↓
serialized JSON
 ↓
Flutter model
 ↓
StoryRepository
 ↓
StoryProvider / Notifier
 ↓
StoryCard / StoryDetailScreen
 ↓
Image widget
```

Verify that the backend actually returns the image URL.

Check:

* serializer
* model field
* API response
* absolute vs relative URL
* HTTP vs HTTPS
* media URL
* Django `MEDIA_URL`
* production media host
* CORS
* authentication requirements
* Flutter JSON parsing
* nullable image handling

Do not assume the Flutter UI is the problem.

---

# 4. ARTIFACT IMAGES ARE MISSING

The Artifact screens have the same problem.

The artifact images should actually appear.

Trace:

```text
Artifact
 ↓
Django model
 ↓
Serializer
 ↓
API response
 ↓
Flutter Artifact model
 ↓
Repository
 ↓
Provider/state
 ↓
Artifact UI
 ↓
Image widget
```

Determine exactly where the image URL is lost.

Check whether the backend returns something like:

```json
{
  "image": "...",
  "image_url": "...",
  "photo": "..."
}
```

or another field.

Use the actual API schema instead of guessing.

---

# 5. DO NOT INVENT IMAGE URLs

This is extremely important.

Do NOT do things like:

```dart
'https://example.com/image.jpg'
```

Do NOT insert random internet images.

Do NOT use generic Unsplash images.

Do NOT create fake image URLs.

Do NOT silently replace real application images with placeholders.

The application already has intended story/artifact images.

Find where they are supposed to come from.

---

# 6. CHECK DJANGO MEDIA CONFIGURATION

Because this project uses Django, inspect:

```python
MEDIA_ROOT
MEDIA_URL
```

and the URL configuration.

Determine whether the API returns:

```text
relative URL
```

such as:

```text
/media/stories/example.jpg
```

or:

```text
absolute URL
```

such as:

```text
https://api.example.com/media/stories/example.jpg
```

Flutter must be able to resolve the URL correctly.

If the backend returns a relative path, verify that the Flutter API layer correctly converts it into a valid absolute URL.

For example:

```text
/media/story.jpg
```

must become something equivalent to:

```text
https://your-api-domain.com/media/story.jpg
```

when appropriate.

Do NOT hard-code this incorrectly.

Use the application's existing environment/base-URL configuration.

---

# 7. VERIFY IMAGE URLS DIRECTLY

Before changing Flutter UI code, inspect the API response.

For example, request the actual endpoint and inspect the JSON.

Determine:

```text
Does the backend return an image?
        │
        ├── YES → Flutter parsing/rendering problem
        │
        └── NO → Django serializer/backend problem
```

Then:

```text
Does the returned URL actually open?
        │
        ├── YES → Flutter image loading problem
        │
        └── NO → Django/media/storage/deployment problem
```

This distinction is critical.

---

# 8. CHECK FLUTTER IMAGE IMPLEMENTATION

Inspect whether the application uses:

```dart
Image.network(...)
```

or:

```dart
CachedNetworkImage(...)
```

or:

```dart
Image.asset(...)
```

or another image system.

Understand the existing implementation before modifying it.

If using network images, implement proper handling for:

* loading
* success
* failed request
* missing URL
* invalid URL

But do not hide a broken backend by showing placeholders indefinitely.

---

# 9. ASSET CONFIGURATION

Inspect:

```text
pubspec.yaml
```

and verify all intended local assets are declared.

Check:

```text
assets/
```

and related directories.

Verify:

* file names
* capitalization
* extensions
* relative paths
* case sensitivity
* Flutter asset declarations

Remember that Linux is case-sensitive.

For example:

```text
assets/images/Story.png
```

is NOT the same as:

```text
assets/images/story.png
```

Do not rename files unless necessary.

---

# 10. SHARE SCREEN FUNCTIONALITY

The Share screen must remain functionally correct.

Inspect:

* share buttons
* copy link
* WhatsApp/share integrations
* social sharing
* QR/share functionality
* native share functionality
* icon actions

Determine whether broken icons are purely visual or whether the underlying actions are also broken.

Do not fix only the appearance if the actions themselves are malfunctioning.

---

# 11. REWARD SCREEN FUNCTIONALITY

Do not only fix the overflow warning.

Verify that the Reward/Gamification screen still correctly displays:

* XP/progress
* badges
* achievements
* certificates where applicable
* leaderboard information
* quiz rewards
* user profile/gamification data

Use the actual models/providers/repositories already present in the application.

Do not replace real data with hard-coded demo values.

---

# 12. IMPORTANT — PRESERVE THE DESIGN SYSTEM

The project already has an established visual direction.

Continue using the existing application design system.

Do NOT introduce:

* random gradients
* stickers
* emojis
* arbitrary colors
* random icon styles
* unrelated fonts
* generic placeholder cards
* inconsistent shadows
* unrelated UI components

The Flutter application should visually match the existing Griot 2.0 web/application design.

Use the project's existing:

* colors
* typography
* spacing
* cards
* buttons
* iconography
* components
* design tokens

where available.

---

# 13. RESPONSIVE UI REQUIREMENT

The screens must be responsive.

Do not solve the reward overflow with a fixed layout that only works on your current emulator/device.

Test against different viewport sizes.

Pay particular attention to:

```text
small phones
medium phones
large phones
```

The UI should not produce:

```text
BOTTOM OVERFLOWED BY ...
RIGHT OVERFLOWED BY ...
```

warnings.

---

# 14. DEBUGGING METHOD

Follow this debugging order.

### Step 1 — Inspect

Find:

```text
ShareScreen
Reward/GamificationScreen
StoryCard
StoryDetailScreen
Artifact screens
StoryModel
ArtifactModel
StoryRepository
ArtifactRepository
API client
image utilities
pubspec.yaml
Django serializers
Django models
Django media configuration
```

### Step 2 — Trace the data

For stories:

```text
Django
 ↓
API
 ↓
JSON
 ↓
Flutter model
 ↓
Provider
 ↓
Widget
 ↓
Image
```

For artifacts:

```text
Django
 ↓
API
 ↓
JSON
 ↓
Flutter model
 ↓
Provider
 ↓
Widget
 ↓
Image
```

### Step 3 — Identify root causes

Do not guess.

Clearly identify whether each problem is caused by:

```text
Frontend
Backend
API contract
Asset configuration
URL construction
Storage
Responsive layout
Dependency
```

### Step 4 — Create a repair plan

Before modifying code, report:

```text
Problem
Root cause
Affected files
Required change
Potential side effects
Testing method
```

### Step 5 — WAIT FOR MY CONFIRMATION

Do not implement the changes yet.

First show me the diagnostic findings and repair plan.

---

# 15. AFTER I CONFIRM

Once I approve the plan:

1. Fix Share screen icons.
2. Fix Reward/Gamification bottom overflow.
3. Restore Story images.
4. Restore Artifact images.
5. Fix API/image URL handling if necessary.
6. Fix Django serializer/media configuration if necessary.
7. Fix Flutter model parsing if necessary.
8. Preserve existing functionality.
9. Run Flutter analyzer.
10. Run relevant tests.
11. Build/run the application.
12. Verify the affected screens.

---

# 16. FINAL ACCEPTANCE CRITERIA

The work is NOT complete until:

### Share

```text
✓ No broken icons
✓ Correct iconography
✓ Buttons/actions still work
✓ No placeholder stickers/emojis
```

### Rewards

```text
✓ No bottom overflow
✓ No horizontal overflow
✓ Responsive layout
✓ Real gamification data displayed
✓ Badges/rewards visible
✓ Existing functionality preserved
```

### Stories

```text
✓ Story images load
✓ Story cards display images
✓ Story detail displays images
✓ Correct backend URLs are used
✓ Failed images are handled gracefully
✓ No fake/random images
```

### Artifacts

```text
✓ Artifact images load
✓ Correct API image URL is used
✓ Artifact detail displays the image
✓ No fake/random images
✓ Missing images are handled correctly
```

### General

```text
✓ No Flutter overflow warnings
✓ No broken assets
✓ No unnecessary UI redesign
✓ No hard-coded demo data
✓ No fake URLs
✓ No emojis/stickers used as icon replacements
✓ Existing Griot 2.0 design system preserved
✓ Backend and frontend data flow remain consistent
```

---

# MOST IMPORTANT INSTRUCTION

Do not treat these problems as isolated visual bugs.

The missing Story and Artifact images may indicate a deeper problem in the:

```text
Django → API → Serializer → Flutter Model → Repository → Provider → Widget
```

pipeline.

The broken Share icons may indicate an asset/dependency/icon configuration problem.

The Reward overflow is a responsive layout problem.

**Diagnose each root cause instead of applying superficial visual patches.**

First inspect the existing implementation.

Then give me the complete diagnostic report and repair plan.

**Wait for my confirmation before implementing anything.**
