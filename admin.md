# Flutter App — UI/UX Audit, Fix & Implementation Plan

You are working on my Flutter application. The current implementation has multiple UI, layout, asset, navigation, and functionality problems.

**IMPORTANT: DO NOT IMPLEMENT ANY CHANGES YET.**

Before modifying, creating, deleting, or refactoring any code, you must first inspect the existing Flutter application and generate a detailed **Plan of Work**.

After presenting the plan, **STOP and WAIT for my explicit confirmation**.

Do not begin implementation until I reply with something like **"Approved"**, **"Proceed"**, or **"Start implementation"**.

---

## 1. First: Perform a Complete Audit

Before proposing the implementation plan, inspect the existing project thoroughly.

Review:

* Flutter screens
* Widgets
* Routes/navigation
* Providers/state management
* Models
* Repositories
* API integration
* Image/asset loading
* Fonts
* Theme configuration
* Colors
* Gradients
* Responsive layouts
* Story screens
* History/progress UI
* Quiz functionality
* Discover Regions
* Artifacts
* Buttons and interactions
* Empty/error/loading states
* Any broken or placeholder components

Do not assume that a feature is implemented simply because a widget exists.

Verify that:

* Navigation actually works.
* Buttons actually trigger their intended actions.
* API endpoints are correctly connected.
* Images actually load.
* Assets actually exist.
* URLs are valid.
* Data is correctly mapped to widgets.
* Screens are reachable through navigation.
* Progress values are correctly calculated and displayed.
* Components are positioned correctly on different screen sizes.

---

# 2. Remove Stickers / Emoji / Decorative Icons

Remove all decorative "sticker" elements that were previously introduced into the Flutter application.

This includes:

* Sticker-like illustrations
* Decorative emoji used as UI elements
* Unnecessary floating decorative graphics
* Random decorative symbols
* Placeholder visual elements that do not belong to the web application's design system

Replace them with proper UI components and real typography where appropriate.

The Flutter application should look like a professional production application rather than a prototype.

---

# 3. Use Real Fonts

Remove inappropriate/default typography and ensure the Flutter application uses the **same typography/design language as the web application**.

First inspect the web application and identify:

* Font family
* Font weights
* Heading typography
* Body typography
* Button typography
* Letter spacing
* Line heights
* Text hierarchy

Then determine how this typography should be reproduced in Flutter.

If the project already contains the required font files, use them.

If fonts are referenced remotely or through another mechanism, verify the source and establish the correct implementation.

Do NOT arbitrarily choose a new font.

The goal is:

**Flutter typography = Web application typography**

---

# 4. Remove ALL Gradients

Audit the entire Flutter application for gradients.

Remove gradients from:

* Backgrounds
* Cards
* Buttons
* Headers
* Story components
* Progress components
* Navigation components
* Decorative containers
* Image overlays where unnecessary

Do not replace gradients with another visual effect unless it is required by the existing web design.

Follow the web application's actual color system.

Use solid colors, borders, elevation/shadows, spacing, imagery, and typography instead.

---

# 5. Follow the Web Application's Design System

The Flutter application must visually follow the existing web application.

Do NOT invent a new visual identity for Flutter.

Inspect the web application and identify:

### Colors

* Primary colors
* Secondary colors
* Background colors
* Surface colors
* Text colors
* Accent colors
* Borders
* States

### Typography

* Font family
* Font weights
* Heading sizes
* Body sizes
* Button sizes

### Components

* Cards
* Buttons
* Navigation
* Tabs
* Progress indicators
* Headers
* Image treatments
* Badges
* Sections

### Layout

* Spacing
* Padding
* Border radius
* Card proportions
* Content width
* Alignment
* Grid/list behavior

Then create or update the Flutter theme so the same design language is consistently used throughout the application.

Do not create screen-specific random styling.

---

# 6. Fix Missing Images

There is a major problem where images that were provided are not appearing in the Flutter application.

Investigate this carefully.

For every missing image:

1. Find where the image is referenced.
2. Determine whether it is:

   * A local asset
   * A remote URL
   * An API-provided image
   * A storage/CDN URL
3. Verify that the URL actually works.
4. Verify that the asset exists if it is local.
5. Verify Flutter asset configuration in `pubspec.yaml`.
6. Verify API serialization/deserialization.
7. Verify the image URL being returned by the backend.
8. Check whether the URL needs transformation or a base URL.
9. Check HTTP/HTTPS issues.
10. Check authentication requirements.
11. Check image caching/loading behavior.

Do not simply add a placeholder image.

The actual supplied images must be properly connected and displayed.

Create a reusable image-loading mechanism with appropriate:

* Loading state
* Error state
* Placeholder
* Network handling
* Caching where appropriate

---

# 7. Fix History Progress Percentage

The history progress percentage currently overlaps the story title.

This must be redesigned.

The progress percentage must have its own clearly defined layout area.

For example, depending on the existing web design:

* progress indicator below the title
* progress indicator beside metadata
* progress indicator inside a dedicated progress row
* progress indicator within the story card

But do NOT allow it to overlap text.

Verify the layout on:

* Small phones
* Normal phones
* Large phones
* Landscape where applicable

The title must remain readable regardless of its length.

Also verify that the percentage value itself is correct.

Do not hardcode the progress percentage.

---

# 8. Fix "Take Quiz"

The **Take Quiz** button currently does not function.

Trace the complete flow:

```text
Take Quiz button
        ↓
onPressed
        ↓
navigation/action
        ↓
quiz route/screen
        ↓
quiz data
        ↓
questions
        ↓
answers
        ↓
result
```

Identify exactly where the flow breaks.

Verify:

* Button callback
* Route registration
* Navigation
* Required parameters
* Quiz API
* Quiz model
* Question loading
* Answer submission
* Result handling
* Loading/error states

The button must perform the intended action.

Do not simply make the button visually clickable.

---

# 9. Discover Regions

The **Discover Regions** section requires a complete audit.

Every region must have an image that is specifically related to that region.

For example, each region card should use a meaningful image representing:

* Culture
* Landscape
* Heritage
* Architecture
* People
* Traditions
* Landmarks

Do NOT use the same generic image for every region.

Verify the complete region data flow:

```text
Region data
    ↓
Region model
    ↓
API response
    ↓
Image URL
    ↓
Flutter widget
```

Each region should have:

* Name
* Relevant image
* Description where applicable
* Correct navigation
* Correct data

If region images already exist in the backend, connect them correctly rather than creating unnecessary duplicates.

---

# 10. Artifacts Screen

The **Artifacts screen is missing/not properly implemented**.

Inspect the existing project to determine:

* Whether an artifact model already exists
* Whether artifact API endpoints already exist
* Whether artifact repositories already exist
* Whether artifact data is already available
* Whether routes already exist
* Whether there are existing artifact-related widgets

Then plan the proper implementation of the Artifacts screen.

The screen should follow the same visual language as the web application.

It should not be implemented as an isolated design.

If artifact data already exists, reuse the existing architecture.

---

# 11. Audit Everything Else

The issues above indicate that there may be additional broken or poorly positioned components.

Therefore, perform a broader UI/UX and functionality audit.

Check:

### Navigation

* Bottom navigation
* Drawer/navigation
* Deep links
* Back navigation
* Routes
* Missing screens

### Home

* Sections
* Cards
* Images
* Buttons
* Spacing

### Stories

* Story list
* Story details
* Progress
* Bookmarks
* Audio
* Images
* Navigation

### History

* Progress
* Titles
* Dates
* Cards
* Empty state

### Quiz

* Entry
* Questions
* Answers
* Progress
* Results

### Discover

* Regions
* Images
* Cultural content
* Navigation

### Artifacts

* Listing
* Details
* Images
* Metadata

### Profile

* User information
* Settings
* Logout
* Navigation

### Global UI

* Theme
* Typography
* Buttons
* Cards
* Spacing
* Responsive behavior
* Loading states
* Error states
* Empty states

---

# 12. Architecture

Do not solve problems by randomly patching individual screens.

Before implementation, determine whether there are systemic problems such as:

* Inconsistent theme usage
* Duplicate widgets
* Hardcoded data
* Incorrect API mapping
* Broken repository architecture
* Incorrect state management
* Missing routes
* Incorrect asset configuration
* Inconsistent spacing
* Screen-specific styling

Prefer reusable solutions.

For example:

```text
App Theme
   ↓
Design Tokens
   ↓
Reusable Components
   ↓
Feature Screens
```

rather than:

```text
Screen A → random colors
Screen B → different colors
Screen C → different typography
Screen D → different card style
```

---

# 13. Before Implementation — Required Deliverable

After completing the audit, DO NOT modify the code.

Instead, provide me with a structured:

# PLAN OF WORK

The plan must contain:

## Phase 1 — Audit

List the problems you found.

For each problem provide:

* File/location
* Problem
* Root cause
* Proposed solution
* Priority

Use:

```text
P0 = Critical / broken functionality
P1 = Major UI/functionality issue
P2 = Visual improvement
P3 = Minor polish
```

## Phase 2 — Design System

Explain:

* Web colors that will be reused
* Font that will be used
* Typography hierarchy
* Component rules
* Gradient removal strategy
* Spacing rules

## Phase 3 — Assets & Images

Explain:

* Which images are missing
* Which URLs are broken
* Which assets are incorrectly configured
* How image loading will be fixed
* How region images will be connected

## Phase 4 — Navigation & Functionality

Explain:

* Take Quiz fix
* Artifacts screen
* Region navigation
* Other broken routes
* Other broken buttons

## Phase 5 — Layout & Responsiveness

Explain:

* History progress fix
* Overlapping elements
* Cards
* Spacing
* Responsive behavior

## Phase 6 — Architecture

Explain any required:

* Provider changes
* Repository changes
* Model changes
* API changes
* Routing changes
* Shared widget changes
* Theme changes

## Phase 7 — Testing

Provide a testing checklist covering:

* Android
* Different screen sizes
* Navigation
* Images
* Quiz
* Regions
* Artifacts
* History
* API failures
* Loading states
* Empty states
* Offline behavior where applicable

---

# 14. Important Rules

### DO NOT IMPLEMENT YET.

The first response after inspecting the project must ONLY contain:

1. Audit findings
2. Root causes
3. Proposed architecture/design approach
4. Detailed Plan of Work
5. Files that would need modification
6. Files that would need creation
7. Potential risks/dependencies
8. Testing strategy

Then stop.

Wait for my explicit confirmation.

Do NOT:

* Modify files
* Create files
* Delete files
* Run automated refactors
* Change dependencies
* Change the theme
* Change routes
* Change APIs
* Commit changes

until I approve the plan.

---

# Success Criteria

After implementation is eventually approved, the Flutter app should:

* Match the web application's visual language.
* Use the correct real font.
* Contain no unnecessary stickers/emoji decorations.
* Contain no unwanted gradients.
* Display the supplied images correctly.
* Use verified image URLs/assets.
* Display history progress without overlapping titles.
* Make Take Quiz fully functional.
* Display every Discover Region with its relevant image.
* Include a properly implemented Artifacts screen.
* Have working navigation.
* Have consistent spacing and typography.
* Have responsive layouts.
* Have functional loading/error/empty states.
* Reuse the application's existing architecture rather than introducing unnecessary duplication.

**Again: INSPECT FIRST → GENERATE THE PLAN → WAIT FOR MY CONFIRMATION → ONLY THEN IMPLEMENT.**
I added UI SAmple in the folder UI Model, inspire from it to build and modify the UI of the project, there is also a logo picture use it for the ap logo