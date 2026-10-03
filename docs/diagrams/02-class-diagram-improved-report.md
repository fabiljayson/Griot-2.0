# `02-class-diagram-improved.md` — change report, assessment and validation

Companion to `02-class-diagram-improved.md`. The source of truth remains
`02-class-diagram.md`, which this work does **not** replace.

Every number below is produced by a script in this directory, not asserted:

```bash
python3 docs/diagrams/count_diagram_elements.py docs/diagrams/02-class-diagram.md
python3 docs/diagrams/count_diagram_elements.py docs/diagrams/02-class-diagram-improved.md
python3 docs/diagrams/export_class_diagram_mmd.py docs/diagrams/02-class-diagram-improved.md /tmp/mmd
(cd ~/tools && python3 -m mermaid2modelio.cli /tmp/mmd/<block>.mmd --dry-run)
```

---

## 1. Change report

| Feature | Added / modified classes | Reason |
|---|---|---|
| Translation | **Added** `StoryTranslation`; **modified** `Story` (`translation_for`) | `Story.language` holds one language, so a second version has nowhere to live. The brief asks for a side table rather than duplicated language columns inside `Story`. |
| Museum | **Added** `Museum`, `MuseumFloor`, `DisplayCase`; **modified** `Artifact` (+`museum`, +`located_on`, +`displayed_in`) | `Artifact.museum_name` / `floor` / `display_case` are three free-text fields that cannot be joined, filtered or constrained. Replaced with real relations **without deleting** the legacy strings, which stay for the data already in the dev database. |
| AI | **Added** `AIService` (`<<interface>>`), `StoryGenerationService`, `StoryRecommendationService`, `TranslationService`, `ContentModerationService`, `CulturalValidationService`, `AIRequest`, `AIResponse`, `AIRequestType`, `AIRequestStatus` | The platform is AI-powered but the model records no AI activity: no request is persisted, no provider, no token spend, nothing to audit. `media_app/services/tts.py` and `luma_ai.py` are the real TTS/Luma clients these generalise. |
| Recommendation | **Added** `Recommendation`, `UserInterest` | `stories_data()` sorts and filters; nothing ranks a story *for a reader*. `RecommendationService` consumes `UserInterest`. |
| QR | **Reused** `QRCodeScan` — **`QRScan` deliberately not added** | The brief's `QRScan` already exists as `QRCodeScan` with the same attributes (`user`, `artifact`, `device_type`, `latitude`, `longitude`) plus `created_at`, `ip_address` and `user_agent`. A second class would have been a pure duplicate. See §2. |
| Gamification | **Added** `XPTransaction`, `XPTransactionSource`; **reused** `Badge` and `UserBadge` — **`Achievement` / `UserAchievement` deliberately not added** | `Badge` already carries `name`, `description`, `icon` (`emoji`), `xp_reward` (`xp_required`) and a `condition` expressed as thresholds; `UserBadge` already carries `user`/`badge`/`earned_at`. The brief's names are duplicates. `XPTransaction` is genuinely missing: `UserProfile.total_xp` is a running total, so an XP grant cannot be audited or reversed. See §2. |
| Notification | **Added to the diagram**: `Notification`, `NotificationKind` — already implemented | `notifications/models.py` exists and is wired (fan-out, dedupe key, inbox API, scheduled digests) but the class was **absent from the diagram entirely**. Added with the members the code has. See §3 for the enum delta. |
| Moderation | **Added** `ModerationReview`, `ModerationReviewStatus`, `ModerationDecision` | `Story.status` + `reviewer_notes` is the *current* verdict on one story. There is no record of who reviewed what, when, or on what basis, and `StoryFlag` is a complaint rather than a decision. The consent work (`consent_attested_by`, `consent_attested_at`, `consent_basis`) proves the project already needs that record. |
| Comments | **Added** `Comment` | Nothing existed. `parent` gives the self-referencing reply tree the brief asks for. |
| Collections | **Added** `Collection`, `CollectionItem` (composition) | `StoryBookmark` is a single implicit "saved" list. A named, shareable collection is a different concept. |
| Media | **Added** `MediaGenerationJob` (`<<abstract>>`), `MediaJobType`; **modified** `AudioNarrationJob`, `VideoGenerationJob` — both now generalize from it | The brief asks for one `MediaGenerationJob`. `AudioNarrationJob` and `VideoGenerationJob` already exist and already share `status`/`error_message`/`progress`/`engine`. Adding a third table would have triplicated the polling logic. See §2 for why this is generalization and **not** composition. |
| Analytics | **Added** `UserEvent`, `UserEventType` | Analytics today aggregate denormalised counters (`view_count`, `like_count`, `share_count`) and `api/analytics.py` computes over them. That cannot answer DAU/MAU, engagement rate or "audio played" — all of which the brief lists. `UserEvent` is the missing fact table. |
| Repositories | **Modified** `AuthRepository`, `StoryRepository` (`<<interface>>`) + interface realizations | The brief asks for `AuthRepository`/`StoryRepository` interfaces with online/offline implementations. Both interfaces **and** their implementations already exist in the diagram; what was missing was the *relationship* between them, so `AuthRepository <|-- ServerAuthRepository` and friends were added. `OnlineStoryRepository` deliberately not added — see §2. |
| (not requested) | **Added** `StoryOrigin`, `StoryConsent`, `StoryLicence`, `ArtifactContentType`, `MediaOriginKind`, `streak_required`, `timezone` | The diagram's own header claims it was "reconciled with the implementation on 2026-09-22". It had drifted: `stories` migrations `0003`–`0005` added nine consent/provenance fields, `gamification/0004` added `Badge.streak_required` and `UserProfile.timezone`, and `qr_codes/0004` split `Artifact.category` from `content_type`. All are now modelled. |

### Deliberately **not** added, and why

The brief says "Identify duplicate concepts before adding new ones" and "Do
not duplicate existing classes". Four requested classes were refused:

| Requested | Why not | Maps to |
|---|---|---|
| `QRScan` | Already exists as `QRCodeScan` with a superset of the requested attributes. | `QRCodeScan` |
| `Achievement` | Already exists as `Badge`. `name`, `description`, `icon`, `xp_reward` and a threshold-based `condition` are all present. | `Badge` |
| `UserAchievement` | Already exists as `UserBadge` (`user`, `badge`, `earned_at`). | `UserBadge` |
| `OnlineStoryRepository` | `StoryRepository` is already the online-first implementation (it holds the `Dio` client and mirrors into `LocalStoryRepository`). A separate `OnlineStoryRepository` would split one class in two with no behavioural difference. | `StoryRepository` (online) + `LocalStoryRepository` (offline) |

### `StoryInteraction` (§16) — considered and declined

The brief invites a common `StoryInteraction` abstraction over
`StoryBookmark`, `StoryLike`, `StoryShare`, `ReadingProgress` and `StoryFlag`,
"only if it avoids meaningful duplication without making the model harder to
understand". The shared surface is `(user, story, created_at)` — three columns.
Everything that makes each class distinct is not shared: `note`,
`progress_percent`, `platform`, `ip_address`, `reason`, `resolved`,
`resolution_notes`.

In Django this means multi-table inheritance, which adds a join to *every*
interaction read — and interaction reads are the hottest queries on the site
(bookmarks, likes and progress are all read on page render). Three duplicated
columns are not worth a join on every page view. **Declined**, with the
reasoning recorded here rather than left silent.

---

## 2. UML relationship choices (§15)

Composition is used in exactly four places, all where the child's row cannot
exist without its parent and the parent owns its lifetime:

```
Museum       *-- MuseumFloor      1
MuseumFloor  *-- DisplayCase      1
Collection   *-- CollectionItem   1
Quiz         *-- QuizQuestion      1
```

Aggregation is used **zero** times. The brief warns against using it "simply to
make the diagram look more complex", and no relationship in this model met its
bar — the honest answer is that there is none.

**`MediaGenerationJob` is a generalization, not a composition.** This is the one
place the obvious answer is wrong. `AudioNarrationJob` and `VideoGenerationJob`
are independent database rows with **no foreign key** to any parent job; either
can be created and completed without the other existing. A composed child
cannot exist without its part-owner, so `*--` would be false. They share a
*contract*, so they generalize from an abstract parent. Drawing them as
composition would have implied a lifetime dependency the code does not have.

---

## 3. Dangling endpoints found in the original file (§19)

The brief asks these be reported "instead of silently inventing the missing
class". Every one of them was checked against the source first — and all of
them turned out to be **real classes the diagram simply never declared**:

| Referenced but undeclared | Where referenced | Verdict |
|---|---|---|
| `OfflineRequestRepository` | `ApiClient._offlineRepository`, `ConnectivityService`, `OfflineQueueInterceptor`, and the relationship `OfflineSyncManager --> OfflineRequestRepository` | **Real** — `frontend/lib/core/database/repositories/offline_request_repository.dart`. Now declared. |
| `LocalGamificationRepository` | `GamificationApiService --> LocalGamificationRepository` | **Real** — `local_gamification_repository.dart`. Now declared. |
| `LocalLibraryRepository` | `LibraryApiService --> LocalLibraryRepository` | **Real** — `local_library_repository.dart`. Now declared. |
| `TokenPair`, `UserStats`, `StoryStats`, `GamificationStats`, `QRStats`, `EngagementSummary` | Referenced only as member *types* (`+Future login() TokenPair`, `+UserStats users`, …) | **All real** — `features/auth/models/user_model.dart`, `features/admin/models/analytics_models.dart`. Now declared. |
| `RecentActivity` | Not in the original; introduced when `EngagementSummary` was declared | **Real** — `analytics_models.dart:278`. Now declared. |
| `AppErrorMapper`, `appErrorFromDio` | Listed as a member *of* `AppError` | **Real, but mis-owned** — `core/network/app_error.dart:81` declares `abstract final class AppErrorMapper` as its own top-level type. Re-homed to its real owner. |
| `WebLoginView`, `WebLogoutView` | Listed as members of the `web_views` module | **Real classes** — `backend/web/views.py:202,227`. Promoted from members to declared classes. |
| `ModerationItem` | `AdminApiService.getModerationQueue() List~ModerationItem~` | **Does not exist.** The real return type is `List<FlaggedStory>` (`features/admin/models/moderation_models.dart`). Corrected — this is the one name that was genuinely wrong rather than merely undeclared. |

Two other defects in the original, both fixed:

* **`AuthRepository` was declared twice**, identically, in the same block — a
  duplicate class the brief's validation step 2 forbids. Declared once.
* **`WebUserSettings` is declared in two different blocks** (backend domain and
  web UI). This one is **retained deliberately** and flagged in the file:
  Mermaid has no cross-block import, so keeping each block self-contained
  requires the repetition. It is the only duplicate the improved file reports.

### Enum delta on `Notification`

The brief's `NotificationType` values do not match the code's `Notification.Kind`:

| Requested | Status |
|---|---|
| `SYSTEM` | **Present** (`Kind.SYSTEM`) |
| `BADGE_EARNED` | Present as `Kind.BADGE` |
| `STORY_PUBLISHED` | Present as `Kind.NEW_STORY` |
| `QUIZ_AVAILABLE`, `LEVEL_UP`, `STORY_APPROVED`, `STORY_REJECTED` | **Not implemented** |
| — | Implemented but not requested: `TRENDING`, `STREAK`, `ANNOUNCEMENT` |

The diagram shows the **implemented** enum, because the file's stated contract
is to be reconciled against the implementation. The four unimplemented kinds are
the gap, and they are the interesting one: a `LEVEL_UP` notification is exactly
what `UserProfile.level` changes and nothing tells anyone.

---

## 4. Architecture assessment

### What was already good

* **The layering is honest.** `web/services.py` and `web/actions.py` are
  correctly thin adapters over shared domain logic, and the diagram showed that
  rather than hiding it behind fake layers.
* **The authorization model is small and correct.** Six DRF permission classes,
  all generalizing from `IsAuthenticated`, with role checks documented as the
  literal `in (...)` expressions the code uses. Preserved byte-for-byte.
* **Frontend/backend separation is real and worth keeping.** `*Model` vs model,
  `*Screen`/`*Notifier` vs model — the convention is consistent enough to read
  the diagram without a legend.
* **Provenance and consent modelling was ahead of its time.** `Story` carries
  `origin`, `provenance_notes`, `consent_status`, `consent_attested_by`,
  `consent_attested_at`, `consent_basis`, `rights_holder`, `licence` and
  `recorded_at`. Few projects model *who attested to a community's consent and
  when* at all.

### What was improved

1. **The diagram is now truthful about AI.** It claimed to be an AI platform and
   modelled no AI activity whatsoever — no request record, no provider, no
   token spend. `AIRequest`/`AIResponse`/`AIService` close that.
2. **Nine referenced classes are declared.** Three were dangling *relationship*
   endpoints, which means the diagram did not parse as valid UML.
3. **Consistency is structural, not aspirational.** Authorization, repositories
   and the two media jobs now use real generalization rather than
   `--> : uses` arrows.
4. **The model is packaged.** Twelve namespaces mirroring the Django apps and
   the Flutter feature folders, which is what keeps a 147-class diagram legible.

### Highest priority, in order

1. **`StoryTranslation`** — the multilingual phase cannot ship without it. Every
   other Phase 5 task depends on a place to put a second language version.
2. **`AIRequest`/`AIResponse`** — TTS and Luma video are real, outbound,
   metered and currently unauditable. A `VideoGenerationJob` whose `engine`
   field the project already had to add *by hand* ("stamp the engine from
   whichever service actually answered") is the argument.
3. **`UserEvent`** — every analytics number on the dashboard is currently
   computed from denormalised counters, which cannot answer any of the eight
   questions the brief lists.
4. **`Museum` / `DisplayCase`** — the free-text location fields are a data-quality
   debt that grows with every artifact.
5. **`Notification.Kind` gaps** — four small additions, including `LEVEL_UP`.

### Remaining weaknesses

* **`Art.packages` is not converted.** Mermaid namespaces render as visual
  groupings, but `mermaid2modelio` reports `namespace maps to a UML Package
  (Skipped during UML conversion)`. The package organization in this file is
  therefore **presentation only** in the XMI export until that tool lands UML
  Packages. Flagged rather than hidden.
* **`QuizAttempt.answers` is a JSON column**, not an `Answer` entity. The brief's
  §15 lists `Question ◆── Answer`; no `Answer` class exists and none was
  invented. A JSON blob cannot be queried per-question, so this is a real
  modelling gap — but modelling it honestly needs a decision about whether a
  partially-answered attempt must be queryable, which the diagram cannot make
  for the project.
* **The `web` block still cross-references backend classes**, so it is not
  self-contained the way the other three blocks are.
* **The Dart `Future<T>` idiom is unrepresentable in UML Phase 5.** Every
  `Future login() TokenPair` produces a `conflicting return types 'Future' and
  'TokenPair'` warning. This is a tool limitation, pre-existing, and accounts
  for most of block 3's 87 warnings.

### Relationships that could **not** be safely modified

* **`Artifact.museum_name` → `Museum`.** The relationship is now modelled, but
  the legacy string stays and the two can disagree. Resolving it requires a data
  migration and a backfill decision (134 artifacts, free-text names, no
  reliable key) — an engineering decision, not a modelling one.
* **`Story.co_authors`.** Modelled as `"*" --> "*"` and annotated in the source
  as *unused by authorization*. Whether it is a real many-to-many, a pending
  feature, or a leftover cannot be determined from the diagram, and guessing
  would change its meaning.
* **`StoryCategory` ↔ `Story`.** A true M2M through a join table, but the brief
  forbids inventing a class the codebase does not have. Left as an association.

---

## 5. Validation (§19)

Run by `count_diagram_elements.py` on both files:

| Check | Original | Improved |
|---|---|---|
| 1. Every relationship endpoint refers to an existing class | **FAIL** — 3 dangling (`OfflineRequestRepository`, `LocalGamificationRepository`, `LocalLibraryRepository`) | **PASS** — 0 dangling |
| 2. Every class has a unique name | **FAIL** — `AuthRepository`, `WebUserSettings` | **PASS**, except the intentional cross-block `WebUserSettings` |
| 3. Every attribute belongs to an existing class | PASS | PASS |
| 4. Every operation belongs to an existing class | PASS | PASS |
| 5. Every generalization references valid parent/child | PASS — 6/6 | PASS — 17/17 |
| 6. Multiplicities are valid UML multiplicities | PASS | PASS |
| 7. No duplicate classes were created | FAIL (pre-existing) | No new duplicates introduced |
| 8. No duplicate relationships | PASS | PASS |
| 9. Existing functionality preserved | — | **PASS** — 0 of 92 classes dropped; 12 member deltas, all listed in §1/§3 as deliberate |
| 10. New features integrate with existing architecture | — | PASS — 4 requested classes reused, not duplicated (§2) |
| 11. Frontend and backend responsibilities distinguishable | PASS | PASS — separate blocks, backend-first naming convention preserved |
| 12. Compatible with PowerAMC/UML concepts | Partial | PASS structurally; `namespace`→Package not yet converted (see §4) |

Independent validation through the project's existing UML pipeline
(`~/tools/mermaid2modelio`), after exporting via
`export_class_diagram_mmd.py`:

| Block | Result |
|---|---|
| 01 Backend domain | **0 errors**, 72 types, 91 relationships, 35 warnings |
| 02 Authorization | **0 errors**, 7 types, 6 relationships, 1 warning |
| 03 Frontend | **0 errors**, 94 types, 68 relationships, 87 warnings |
| 04 Web UI | **0 errors**, 12 types, 13 relationships, 18 warnings |

Warning classes are all understood and pre-existing in kind: `<<enumeration>>`
not yet converted to a UML Enumeration (planned in the tool's Phase 6), Dart
`Future<T>` generics, `namespace` → Package, and `...` placeholder parameters.
**No validation errors in any block.**

---

## 6. Final statistics

Produced by `count_diagram_elements.py`. Counting rules are documented in that
file's docstring so they can be argued with; a member containing `(` is an
operation and everything else is an attribute.

```text
Original classes:        92
Final classes:          147

Original attributes:    410
Final attributes:       687

Original operations:    159
Final operations:       198

Original associations:   87
Final associations:     157
  (composition:            0 →   4)
  (aggregation:            0 →   0)

Original generalizations:  6
Final generalizations:   17

Duplicate class names:     2 →   1  (intentional, cross-block)
Dangling endpoints:        3 →   0
```

The original's counts match the figures quoted in the brief (92 classes, 410
attributes, 159 operations, ~84 associations, 6 generalizations) — the one
difference, 87 associations against "~84", is consistent with the brief's own
"approximately". Reproducing those numbers from the file is the evidence that
the improved file's numbers are measured the same way.

**Not regenerated:** `docs/diagrams/mermaid/02-class-diagram.0N.mmd` and
`docs/diagrams/xmi/02-class-diagram.0N.xmi` still describe the *original*
diagram. Regenerating them is a mechanical follow-up
(`export_class_diagram_mmd.py` produces the `.mmd`; the XMI step needs
`mermaid2modelio`), deliberately not done here so this change stays reviewable
as documentation only. The exports for the improved diagram belong in their own
commit, with the `.xmi` re-import into Modelio verified.
