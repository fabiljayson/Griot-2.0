# Prolificity Roadmap

**Date**: 2026-10-03 | **Baseline commit**: `ef2a8a8` | **Revision**: 3 (phasing reviewed)

A plan to raise output on all four axes we agreed on: shipping code faster,
producing more content, growing the community, and raising the quality floor.

Phases 1–3 are small enough to land as normal pull requests. Phases 4–6 are
expanded here in full task detail rather than deferred to separate specs — the
review asked for concrete work items, so that is what this document contains.
Each of 4–6 still needs a constitution check before implementation, but the
scope is no longer open.

**Revision 3 changed the phasing, not the work.** Four sequencing adjustments
out of the review:

1. The history-purge phase is split into **8a** (containment: rotate
   credentials, delete the on-disk backup, ignore the pattern — do it now) and
   **8b** (the actual rewrite, which waits on sign-off rather than on any
   engineering phase).
2. The shared translation model moved out of Phase 5 into a new **Phase 0**,
   because a cheap written decision was silently gating Phase 4's schema. Phase 4
   and Phase 5 are now parallel.
3. Phases 6 and 7 keep their scope, but the **dependency arrows were wrong**:
   moderation at volume needs the corpus, so 7 runs before 6.
4. Voice capture left Phase 4 for a **Phase 10** of its own.

### Where things stand

| Phase | State |
|---|---|
| 1. Artifact taxonomy | **Landed** at `ef2a8a8` |
| 2. Gates | **Landed** — ruff clean, coverage 84% / floor 80, crawler CI job, pre-commit config |
| 3. Gamification | **Landed** — one award service on three call sites, `streak_required`, certificates now issued |
| 8a. Contain the leak | **Done except rotation** — `.bak` deleted, ignore rule was already present; credential rotation is user-owned |
| Everything else | Not started |

Revision 3 was written against this state so the sequencing below is honest
about what is left rather than what was planned.

## Verified baseline

Every number here was measured on the dev database at `1b57e34`, not estimated.

| Signal | Value |
|---|---|
| Backend tests | 465 pass, 6 skipped |
| Flutter tests | 381 pass, `flutter analyze` clean |
| Crawler tests | 5 pass — **not run by CI** |
| `makemigrations --check` | Clean |
| `manage.py spectacular` | 0 errors |
| Users / profiles | 523 / 505 |
| Stories | **12** — all `language='en'`, `origin='seeded'`, `consent_status='not_requested'`, `status='published'` |
| Artifacts | **134 — 127 of them `category='other'`** |
| Quizzes / questions / attempts | 12 / 48 / 9 |
| Badges / awarded / certificates | 12 / **0** / **0** |
| Story flags | **0** |

Two numbers carry most of the argument below: **127/134 artifacts are
`other`**, and **0 badges have ever been awarded** despite 12 existing.

This table is **frozen at `1b57e34`**. Phase 1 has since landed and moved the
artifact counts; rather than track a moving number here, re-measure once after
Phase 9 and update in one pass.

---

## Phase 0 — Decisions before Phase 4 writes schema

**Added in revision 3.** This is not a build phase. It exists because a
decision that costs an afternoon was filed under "Phase 5, task 6", which made
Phase 5 an implicit blocker for Phase 4 and for any schema work at all.

1. **Shared translation model.** Stories must not be duplicated per language.
   Decide whether translation is a relation on `Story` (or a separate
   translation object), what happens to `Story.language` when one story exists
   in several languages, and how moderation queues stay single per story rather
   than tripling. Settle this **before Phase 4 touches schema and before the
   first non-English story is written** — after content exists, it is a data
   migration instead of a design choice.

Deliverable is a written decision in this document, not code. Everything from
Phase 4 onward reads it as an assumption.

### Decision (2026-10-03): `StoryTranslation`, a child of `Story`

**Alternatives considered:**

| Option | Why not |
|---|---|
| One `Story` row per language, linked by `translation_of` | The failure mode the task named: three rows, three moderation queues, three sets of counters to reconcile, and a flag on the French copy leaving the English one published. |
| A `translations` JSONField on `Story` | No per-language status, translator, or rights; nothing to review; unqueryable for "which languages is this available in"; and rewriting a key silently overwrites a translator's work — the habit Constitution IV forbids. |
| **`StoryTranslation` child model** | **Chosen.** One row per (story, language), its own review state and provenance, original row untouched. |

**The schema**

```python
class StoryTranslation(models.Model):
    story = FK(Story, related_name='translations')
    language = CharField(choices=Story.Language.choices)   # unique with story

    # Translated text — and only text. See "what does not move" below.
    title, summary, content, cultural_context, moral_lesson

    # The translation's own provenance: who did it, and how.
    translator = FK(User, null=True, blank=True)
    method = CharField(choices=human, machine_assisted, machine)
    provenance_notes = TextField(blank=True)

    # Its own review state — same choices as Story.Status.
    status = CharField(choices=draft, pending, published, rejected, archived)
    reviewer_notes = TextField(blank=True)

    created_at, updated_at, published_at
    # Meta: unique_together = ('story', 'language')
```

**Seven consequences the rest of the plan depends on**

1. **`Story` stays the single source row.** `view_count`, `like_count`,
   `bookmark_count`, `share_count`, `ReadingProgress`, `StoryFlag`,
   `StoryLike`, `StoryBookmark` and `StoryShare` all point at `Story` and stay
   there. Reading the French copy increments the same counter. Totals are never
   summed across languages, and Phase 6's load test measures one queue, not
   three.
2. **`Story.language` keeps its current meaning: the language of the
   *original*.** It does not become "available in". All 12 seeded rows stay
   correct, and `?language=fr` plus its existing test keep meaning "French
   originals".
3. **A second parameter carries availability.** `?in_language=fr` returns
   stories readable in French — original *or* translated. Phase 5 builds this;
   it does not repurpose `?language=`.
4. **Translation does not fork moderation.** A `StoryTranslation` enters review
   only when someone submits it, and appears in a separate "translations
   awaiting review" view. The existing queue keeps showing one row per story. A
   translation may not publish while its original is unpublished, and cannot
   make an unpublished original visible.
5. **Fallback is explicit, never silent.** Ask for a story in Ewondo, find no
   translation, serve the original and mark the response `translated: false`.
   Telling a French reader they got a French story when they did not is the
   same class of dishonesty the provenance work in `ee3b0c9` exists to prevent.
6. **What does not move.** `slug` is stable because QR codes and deep links
   encode it (Constitution IV) — a translation shares the original's slug and
   URL. `region`, `tags`, `categories`, `origin`, `consent_status`,
   `rights_holder` and `licence` stay canonical on `Story`. Translations
   *inherit* the original's rights by default and may override them only with a
   `provenance_notes` entry saying on what basis. **Known limit, accepted for
   v1**: tags stay in the original language, so a French reader searching a
   French tag will not match.
7. **The translated set is `title`, `summary`, `content`, `cultural_context`,
   `moral_lesson`** — the prose a reader actually reads. `cultural_context` and
   `moral_lesson` are translated rather than shared because they are narrative,
   but the original is never overwritten.

**Cost.** One migration, one model, one serializer, one fallback branch per
reader — cheaper than untangling duplicated rows after content exists, which is
why this lands before Phase 4 rather than inside Phase 5.

**Deliberately open:** how a machine-assisted translation is *labelled* in the
UI. `method` records the fact; the reader-facing badge is Phase 5's call.

---

## Phase 1 — Split the artifact taxonomy

**Why first**: it is the cheapest fix in this plan and the largest single
quality gain in the data. It also unblocks browse, filtering, QR labelling,
and search, all of which are currently fed garbage.

**Review decision**: do the full field split now, not a minimal patch.

**Status (revision 3)**: landed at `ef2a8a8`. Note that *unblocking* a surface
is not the same as *delivering* it — see the deferral note under Tasks.

### The defect

`backend/qr_codes/management/commands/import_crawl_data.py:134` collapses
every crawler category into one bucket:

```python
category_map = {
    'kingdom': 'other', 'landmark': 'other', 'artifact': 'other',
    'legend': 'other', 'culture': 'other',
}
category = category_map.get(category, 'other')
```

This is a placeholder that was never filled in. The crawler *already* does
real keyword classification (`crawler/utils.py::classify_category` against
`config.CATEGORY_KEYWORDS`); the fine-grained signal is destroyed at the last
step of the import.

Underneath sits a deeper problem: **two taxonomies are forced through one
field.**

- The crawler emits *content type*: `Kingdom`, `Landmark`, `Artifact`, `Legend`,
  `Culture` — what kind of page it scraped.
- `Artifact.Category` is *material type*: `sculpture`, `textile`, `instrument`,
  `jewelry`, `pottery`, `mask`, `weapon`, `fabric`, `tool` — what the object is.

A mask is both. One field cannot hold both, which is why the mapping could
never be made correct.

### Tasks

1. **Add `Artifact.content_type`** with choices `kingdom`, `landmark`,
   `artifact`, `legend`, `culture`, plus `unknown` as an honest default for
   rows we cannot classify. Indexed, because browse *will* filter on it once
   Phase 9 settles what the taxonomy is for. Migrate. `category` keeps its nine
   existing values and choices untouched.
2. **Split the crawler classifier.** Rename `classify_category` to
   `classify_content_type` (its actual behaviour) and add
   `classify_material_type`. Rename `config.CATEGORY_KEYWORDS` →
   `CONTENT_TYPE_KEYWORDS` and add `MATERIAL_TYPE_KEYWORDS`. Update all four
   call sites in `crawler/extractors.py`; both keys are emitted.
3. **Backend classification module.** Add `backend/qr_codes/classification.py`
   holding the material keyword map and `classify_material(text)`, so the
   import command and the backfill share one implementation rather than the
   backend importing the standalone `crawler/` package.
4. **Replace `category_map`** in the import command:
   - `content_type` from the item, validated against `ContentType.choices`.
   - `category` from the item's `material_type`, or classified locally from
     title/description text when absent.
   - **Unknown values log a warning and increment a counter** rather than
     silently becoming `other`. The summary line reports the count.
   - `--strict` flag aborts the import on the first unknown value, for
     operators who would rather fail than import partial data.
5. **Backfill command** `reclassify_artifacts` re-runs classification over
   existing rows using `title` + `description` + `historical_significance`, so
   the fix is not forward-only. Supports `--dry-run` and `--limit`.
6. **Tests**: import one artifact per content type and per material type;
   unknown material logs and counts rather than silently defaulting; `--strict`
   aborts; backfill corrects a seeded `other` row; `content_type` defaults to
   `unknown` and is queryable.

**Deliberately deferred to Phase 9**: wiring `content_type` into consumers.
Phase 1 ships a field nobody reads — `/artifacts/` still filters on `category`
(`backend/web/views.py:113`) and QR labels are still drawn from the material
taxonomy. Which of the two taxonomies a user should filter on is the same
question Phase 9 has to answer, so the wiring waits for that answer rather
than guessing twice.

### Done when

`Artifact.objects.filter(category='other').count()` is small, every remaining
one is genuinely `other`, and no test depends on `other` being a silent
fallback. Migration drift clean, suite green.

---

## Finding from Phase 1 implementation (2026-10-02)

Building this surfaced something bigger than the category map. **The 127
`other` rows are mostly not artifacts at all.**

They are travel-guide and reference entries — `electrical-outlets`,
`drivers-license`, `gratuities`, `the-currency`, `the-equatorial-zone`,
`cameroonian-food`, `bamileke-elephant-mask` sit alongside `geography` and
`photography`. The crawl importer has been writing a whole "About Cameroon"
guide into a table meant for museum objects, and `category='other'` was
masking that: the value that looked like a classification failure was
actually the *correct* answer for a row that should never have been there.

Three consequences:

1. **`category='other'` is not a bug to be eliminated.** It is the truthful
   answer for most of these rows. Phase 1 makes `content_type` carry the real
   signal (`landmark`, `culture`, `kingdom`) instead of hiding it, but the
   right end state is to stop storing reference articles as `Artifact` rows.
   That is now tracked in Phase 9.
2. **127 of 134 rows have an empty `description`.** The importer's
   `_short_description` returns `''` when the source has no usable first
   sentence, so the artifact detail page has nothing to show for these.
3. **Classification from stored prose is unreliable, and must be gated.**
   The first backfill attempt overwrote curated rows: `Bamoun Royal Mask`
   (`mask`) became `jewelry`, because its description mentions beads more
   often than it says "mask", and classified `Benoué National Park` as a
   `sculpture`. Fixed by (a) never reclassifying a row that already has a
   non-`other` category unless `--force` is passed, (b) excluding `story`
   from the classification text — it is historical prose that mentions every
   kind of object in the surrounding history, and (c) requiring a minimum
   score of 2 keyword hits before believing a match.

   **The general lesson for Phases 4–7: automated classification over prose
   should never overwrite curated data.** Every auto-classifier here runs at
   `min_score=2`, defaults to an honest `unknown`, and is refused by default
   on rows a human has already classified.

### Phase 9 — Decide what an Artifact is

**Added after Phase 1 implementation.**

1. **Classify the 127 rows** using the `content_type` now recorded: how many
   are landmarks, how many culture entries, how many are genuine objects
   that were merely mis-bucketed.
2. **Decide the home for non-artifact content.** Options: a separate
   reference/guide model; leave them as `Artifact` rows with
   `content_type` distinguishing them; or retire them. This is a product
   decision, not an engineering one.
3. **Stop the importer accepting them by default**, or point it at a
   content-type-appropriate destination. Right now it writes anything into
   `Artifact`.
4. **Fix the empty descriptions.** 127 rows render a detail page with no
   description because the source had no first sentence.
5. **Wire `content_type` into its consumers.** Phase 1 landed the field and
   nothing reads it: `/artifacts/` still filters on `category`
   (`backend/web/views.py:113`) and QR labels come from the material taxonomy.
   Whichever home task 2 picks, the browse filter and the QR label should read
   `content_type` — otherwise the taxonomy fix never reaches a user, which is
   the payoff Phase 1 was justified on.

---

## Phase 2 — Make the gates real

Every later phase adds code. These are the mechanisms that stop the same class
of defect as Phase 1 recurring unnoticed.

### Status — landed (revision 3)

| Gate | State |
|---|---|
| ruff | `ruff check .` clean under `backend/ruff.toml`. Pinned `ruff==0.16.10` in the new `backend/requirements-dev.txt`. 11 real E702s in `web/templatetags/web_extras.py` fixed; the rest of the in-flight diff was unused imports and dead locals. |
| coverage | **Measured 84%** on 4966 statements (migrations and test modules excluded), **floor set to 80** in `backend/.coveragerc`. Measured before set, as the task requires. |
| crawler CI | New `crawler` job in `ci.yml`, running `python -m unittest discover -p 'test_*.py'` from `crawler/`. |
| pre-commit | `.pre-commit-config.yaml` written: ruff + the migration drift check. Needs `pip install pre-commit && pre-commit install` per clone — that step is not run for you. |

| Verification | Result |
|---|---|
| `ruff check .` | All checks passed |
| `coverage report` | 84% (≥ 80 floor) |
| `makemigrations --check` | No changes detected |
| Backend suite | **486 tests, OK (6 skipped)** |
| Crawler suite | **5 tests, OK** |

### Tasks

1. **Run the crawler tests in CI.** `ci.yml` has backend, frontend, and deps
   jobs; the 5 tests in `crawler/test_*.py` run in none of them. Add a
   `crawler` job.
   - **Blocker resolved**: there was never a separate crawler *environment*
     problem — `crawler/requirements.txt` already declares `requests`,
     `beautifulsoup4`, `lxml`, and `httpx`. What was missing is that nothing in
     CI ever installed it or ran the tests, so they only passed on whichever
     machine happened to have those packages (here, `backend/.venv-linux`). The
     new job installs from `crawler/requirements.txt` into its own interpreter
     and runs with `crawler/` as the working directory, which is what puts
     `extractors`/`runner` on `sys.path` for the tests' `from extractors import …`.
2. **Add `ruff`** for lint. `manage.py check` is a Django system check, not a
   lint. Budget for a cleanup commit separate from the enabling commit.
   - **Pin it first.** `ruff` is currently in neither `backend/requirements.txt`
     nor on `PATH` — an unpinned `pip install ruff` in CI will drift and fail a
     different way next month. Add it to requirements (or a dev-requirements
     file) in the enabling commit.
   - **State check**: the enabling config (`backend/ruff.toml`) and a first
     cleanup pass already exist as uncommitted working-tree changes. That diff
     currently touches 43 files / 553 lines, of which only ~205 differ when
     CR-at-EOL is ignored — line-ending normalization is mixed in with the real
     fixes, and one *applied* migration was edited. Split the normalization
     into its own commit (or add `.gitattributes`), keep `migrations/` out of
     autofix, and land the lint fixes reviewable.
3. **Add `coverage.py`** with `--fail-under`. **Measure first, set the floor
   second** — a threshold the repo fails on day one trains people to ignore
   red. Publish the current number in the log, floor slightly below, then
   ratchet.
4. **Pre-commit hooks** (`.pre-commit-config.yaml`) running ruff plus a Django
   migration check, so failures land before push.

---

## Phase 3 — Fix the dead gamification paths

12 badges exist, **0** awarded, **0** certificates, across 9 quiz attempts.
The entire rewards system is currently decoration.

### Tasks

1. **Diagnose before writing anything.** Trace `UserBadge` and `Certificate`
   creation from quiz completion. Determine which of: never called, called with
   an unsatisfiable predicate, or called but rolled back. **Write the finding
   down before deciding on a fix** — the answer determines whether this is a
   one-line bug or a design gap.
2. **Fix the trigger** in the shared service layer per Constitution I, so API
   and web behave identically.
3. **Tests for the award rules**: earning, not earning, idempotency (no
   double-award on replay), and threshold boundaries.
4. **Surface progress.** If badges are unreachable in the UI, that is a second
   defect — a user cannot chase what they cannot see.

### Finding from the Phase 3 diagnosis (2026-10-03)

**Task 1 answered: design gap, not a one-line bug.** Written before any fix was
decided, as the task requires.

**1. The sweep has never executed.** Both `UserBadge` write sites sit inside
`if attempt.passed:` (`gamification/views.py:205` and
`web/services.py:723-731`). Of the 9 quiz attempts in the dev database, **1
completed and it failed**; the other 8 are still `in_progress`. `attempt.passed`
has never once been true, so neither sweep has ever run its award branch.

**2. The predicates are not the problem.** Existing profile state already clears
most thresholds by a wide margin:

| Badge | Requires | Profiles that qualify today |
|---|---|---|
| First Steps | 1 story read | **503** |
| Rising Star | 100 XP | **501** |
| Quiz Rookie | 1 quiz passed | **376** |
| Story Seeker | 5 stories read | well clear (max observed 9) |

503 profiles qualify for First Steps and zero hold it. The thresholds are
satisfiable and satisfied — the sweep simply never runs against that state.

**3. The counters move on paths that contain no sweep at all.**
`web/services.py:636-642` increments `stories_read` on every completed read;
`streaks.grant_xp_and_stats` increments `total_xp` and `quizzes_passed`.
Neither calls any badge check. Reading stories — the app's main activity — can
never earn a reading badge, and 5 of the 12 badges are reading badges.

**4. `Certificate` has no write path at all.** `Certificate.objects.create`
appears nowhere in the codebase. The model, serializer, admin, read-only
viewset, and the PDF generator in `certificate_generator.py` all exist and all
read; nothing ever writes. 0 certificates is not a malfunction, it is the
absence of a feature that was built everywhere except the one place that would
produce one.

**5. Two further defects found while tracing:**

- **`Dedicated Reader` (badge 60) is unreachable by construction.** All three
  requirements are `0`, and every check is written `if badge.xp_required and
  profile.total_xp >= badge.xp_required`. `0` is falsy, so all three branches
  short-circuit false. A badge demanding nothing can never be earned — the
  exact inverse of its meaning, and silently so, because the row looks
  perfectly normal.
- **The two surfaces disagree, violating Constitution I.** The web sweep runs on
  *every* passing attempt (its own comment notes the profile is resolved before
  the payout branch precisely so retakes are covered). The API's `_check_badges`
  runs only inside the `not already_paid` branch — **first pass only**. The same
  capability, implemented twice, with different behaviour.

### Consequence for the fix

Because the answer was "design gap", this is not a patch. The shared rule
Constitution I already states — gamification "implemented once in
models/services and reused, never duplicated per surface" — is precisely what
the current code does not do. Any fix that edits the two existing copies in
place will have to keep them in sync forever, and the API/web divergence above
is the proof that this already failed once.

The fix therefore needs a single award service, called from every path that
moves a counter a badge can read — quiz completion on both surfaces *and* story
reading — plus a decision on whether `Certificate` gets a creation path at all.

### Status — landed (revision 3)

Decisions taken before writing code: one shared sweep (Constitution I already
mandated it), a real `streak_required` field rather than faking the streak as a
read count, and certificates issued on badge award.

1. **One service.** `gamification/services/awards.py::award_eligible_badges`
   is now the only implementation. Both surfaces call it at the same point in
   their flow, after the counters have been written; the API's `_check_badges`
   and the web's inline copy are gone.
2. **Called from three places**, not two: API `finish`, web `finish_quiz`, and
   web `record_progress`. Reading badges are earnable for the first time. A
   failed quiz now sweeps *and* extends the streak on both surfaces — the web
   flow had drifted to counting only passes, which the API never did.
3. **`Badge.streak_required`** added by migration `0004`, with a data fix scoped
   to `slug='dedicated-reader'` so an operator's own badge is left alone.
   `Badge.clean()` now refuses a badge that demands nothing, and
   `seed_gamification` validates before creating. The dev database was migrated:
   `dedicated-reader` reads `streak_required=3`.
4. **Certificates get a writer.** A reading or quiz badge award issues the
   matching `Certificate`, keyed on `(user, type, title)` so a replay cannot
   mint a second copy. `EXPLORER` and `CONTRIBUTOR` are deliberately unwired —
   that is a product call this phase did not take.
5. **Task 4 — progress is now actually visible.** Both surfaces did render an
   earned/locked grid, but the API exposed only `xp_required`, so 9 of the 12
   badges reached Flutter as a bare locked icon with no threshold to chase, and
   the web template had no streak branch (it fell through to `Locked`). All four
   requirements are exposed by `BadgeSerializer`, rendered on web, and rendered
   in Flutter via `BadgeModel.requirementLabel` using the same precedence.

| Verification | Result |
|---|---|
| Backend suite | **501 tests, OK (6 skipped)** — 15 added |
| Coverage | **85%** (was 84%; floor 80) |
| `ruff check .` | All checks passed |
| `makemigrations --check` | No changes detected |
| Flutter | `analyze --fatal-infos` clean, **381 tests passed** |
| Dev database | `0004` applied, `dedicated-reader` repaired |

The four `AwardWiringTests` target the paths that did not sweep before this
change: story read, API finish on a failed attempt, web finish on a failed
attempt, and the streak-on-failure parity gap. The `BadgeAwardTests` cover the
rules the old code could not express at all (streak thresholds) or got wrong
(all-zero badges).

---

## Phase 4 — Stories are the bottleneck

134 artifacts, **12 stories**. Artifacts are supporting cast; stories are what
a reader opens the app for. The story model is also the richest (`language`,
`region`, `cultural_context`, `moral_lesson`, `origin`, `provenance_notes`,
`consent_status`, `rights_holder`, `licence`, `recorded_at`) and is entirely
unexercised by real data: all 12 rows are `origin='seeded'`,
`consent_status='not_requested'`.

Phase `002-story-submission-moderation` built the review lifecycle. This is
about getting real people through it.

### Tasks

1. **Constitution check** before implementation, per `002`.
2. **Consent capture.** The guard added in `ee3b0c9` blocks publishing when
   consent is withheld, but no flow ever *collects* consent. Build the
   recording step: who attested, when, on what basis, and store it against
   `consent_status` / `rights_holder` / `licence`.
3. **Contributor-facing submission.** The review queue exists for moderators;
   verify an ordinary contributor can submit, see status, and act on a
   rejection reason. Add the missing path if not.
4. **Provenance backfill** for the 12 seeded stories — at minimum `origin` and
   `provenance_notes` — so the model reflects reality rather than `seeded`.

**Moved out in revision 3**: contributor-recorded audio is now Phase 10. Phase
4 is consent capture, the contributor submission path, and provenance — a
coherent unit that needs no cross-phase design decision, because Phase 0 already
settled the one that mattered. Task 2 does add three fields; they are local to
`Story` and cannot destabilise anything else.

### Task 1 — Constitution check: PASS

| Principle | Status | Notes |
|---|---|---|
| I. API/Web/Flutter Parity | ✅ PASS | `resolve_status` is one rule called by both the API serializer and `web.services.save_story`. The two had already drifted: the API's read-only `status` silently discarded the identical `status: 'pending'` Flutter sends. Rejection reason now flows to API, web, and the Flutter model. The consent gap first recorded here is closed: both halves of the record now exist on **all three** surfaces — `record_consent` is one shared service called by an API action and a web action, and the *worklist* it reads from is one query (`consent_review_queue`) rather than three filters that could drift. |
| II. Security by Default | ✅ PASS | A contributor may set only `draft`/`pending`, enforced in the shared service rather than per surface; `consent_status` stays read-only to contributors; consent recording is moderator-gated server-side, not in the view. |
| III. Test-First Regression Coverage | ✅ PASS | 37 new tests: submit guard, reason visibility on all four viewer roles, both consent steps, withdrawal, provenance backfill, the consent queue (permissions, membership, payload), the web panel's role split, and the Flutter screen's mandatory basis. Migrations committed with the model change. |
| IV. Cultural Data Integrity | ✅ PASS | Backfill scoped to `origin='seeded' AND provenance_notes=''` — it cannot touch a curated record. Withdrawing consent **archives** the story rather than failing or leaving it published. |
| V. Observability & Operational Honesty | ✅ PASS | `consent_attested_by/at/basis` make the decision attributable; the seeded note says plainly that no community consent was sought. |

### Four defects the tasks were hiding

1. **The API could not submit a story at all.** `status` was in
   `read_only_fields`, so the Flutter client's "submit for review" button sent
   `status: 'pending'`, had it discarded, and reported **"Story submitted for
   review"** while the row stayed a draft. The web form passed `status`
   straight through, so the same click worked there. Nobody could have noticed
   from the app: the failure was silent on the only surface that failed.
2. **A rejected contributor was never told why.** Moderators write the reason
   into `reviewer_notes`; it appeared in no serializer, no template, and no
   Flutter model. The field is described as "internal notes", yet it is what
   `moderate` stores as the rejection reason — so the reason existed and was
   read by nobody.
3. **No flow collected consent.** `consent_status` could only be changed by the
   admin. There was no "I asked" step and no "here is the answer" step.
4. **Even after the endpoints existed, no surface could reach them.** The first
   pass of this phase added `POST /consent/` and `web:story-record-consent` and
   stopped there — `web/actions.py` had both POST handlers and **no form**, and
   Flutter had no call at all. So the phase shipped a server-validated field
   that no moderator anywhere could see or change: all 12 seeded stories sat at
   `not_requested` with no way out and no worklist to find them by. Defect 3 was
   not fixed by adding endpoints; it was fixed by adding a queue and two forms.

### Status — landed (revision 3)

1. **One status rule.** `stories/services.py` (new, as spec `002` originally
   planned) holds `resolve_status`, `request_consent` and `record_consent`.
   Both surfaces call it; neither implements it.
2. **Consent is two steps.** Author records `not_requested → pending` (API
   `request-consent/`, web `…/request-consent/`); moderator records the answer
   with `consent_attested_by`, `consent_attested_at` and a **required**
   `consent_basis`. Migration `stories/0004` adds the three fields.
3. **Withdrawing consent archives the story.** The model already refuses to
   save published + withheld, so raising would have made consent impossible to
   withdraw; leaving it published was not an option. The record is kept.
4. **Rejection reason is visible** to the author and moderators only, on API
   (`reviewer_notes`), web (a review-state banner), and Flutter
   (`StoryModel.reviewerNotes` + `_ReviewStateBanner`).
5. **Provenance backfilled.** Migration `stories/0005` fills the 12 seeded rows'
   empty `provenance_notes`, scoped so it can never touch curated data;
   `seed_stories` writes the same note on insert and backfills on re-run.
   `origin='seeded'` is left exactly as it is — Phase 7 task 3 depends on it.
6. **A moderator has somewhere to work.** `GET /api/stories/consent-queue/`
   (`IsAdminOrManager`) lists the stories still awaiting a decision, using
   `stories.services.consent_review_queue` — one definition of "awaiting",
   because a worklist that each surface filters for itself is three things to
   keep correct. The payload carries the contributor's declared origin,
   provenance notes, rights holder and licence: the decision is about the text,
   and a moderator shown only a title and a status dropdown is signing for a
   tradition they have not read the provenance of.
7. **Flutter gets the moderator screen.** `ConsentReviewScreen` (from the admin
   dashboard app bar) lists the queue, and `ConsentFormSheet` records a
   decision. Two rules the sheet enforces visibly, because a "pick a status"
   control implies neither: **a basis is mandatory**, and **choosing "withheld"
   on a published story archives it** — both stated before the tap, not after.
   The sheet owns the write rather than returning a value to its caller, so a
   failed save leaves the moderator's words on screen to retry; losing an
   attestation because a request timed out would mean re-interviewing somebody.
8. **The web story page gets the matching panel.** Same two halves, same split:
   the moderator gets the decision form, the author gets only "I have asked".
   `is_moderator` already existed in the context processor; neither half of the
   record was ever rendered.
9. **The author can say they asked, in the app.** `StoryRepository.requestConsent`
   → `StoryDetailNotifier.requestConsent`, surfaced as a `_ConsentActionBar` on
   the story page, gated by `StoryModel.canRequestConsent(user)` — author and
   contributor only, mirroring what the server answers 403 to. The provenance
   section already showed the *state*; it offered nothing to do about it.

| Verification | Result |
|---|---|
| Backend suite | **535 tests, OK (6 skipped)** — 37 new |
| `ruff check .` | All checks passed |
| `makemigrations --check` | No changes detected |
| Flutter | `analyze --fatal-infos` clean, **395 tests passed** |
| Dev database | `stories/0004`, `stories/0005` migrated |

### Gap carried out of Phase 4 — closed

This section recorded a product question instead of an answer:

> **No moderator consent screen in Flutter.** The API endpoint and the web action
> both exist; Flutter's only moderation surface is the flagged-stories section of
> the admin dashboard, and there is no moderator story browser to hang a consent
> form on. ... Deciding this needs a product call: does the Flutter app grow a
> moderator story list, or is consent recording a web-only job by design?

**Answered: the app grows one.** The reasoning that settled it was not parity for
its own sake. Consent is the only field in the schema whose absence means
*someone's permission was never asked about*, and a curator working from a phone
at a community meeting is closer to the community than a curator at a desk. A
web-only form makes the record depend on somebody remembering to open a laptop.

It also turned out the web half was not finished either — both POST handlers
existed with no form to submit them (defect 4 above). So the gap was not
Flutter-shaped; it was "no surface had a worklist", and both got one. Status
items 6–9.

**Accepted limit.** The queue is a screen and a form, not a full moderation
workflow: it records consent, not the story's `status`. Approving, rejecting and
reasoning still happen on the web admin dashboard and via `resolve_status`. A
moderator working entirely on a phone can record what a community said but
cannot yet act on the publication decision that follows from it.

---

## Phase 5 — Multilingual, both tracks in parallel

`USE_I18N = True`, `LANGUAGE_CODE = 'en-us'`, and **zero project `.po` files**.
`Story.language` exists; all 12 stories are `'en'`.

**Review decision**: French and an indigenous language run **in parallel**,
neither deprioritised.

- **Track A — French.** The language of administration and schooling.
  Widest reach, most contributors soonest.
- **Track B — indigenous.** Ewondo, Duala, or Fulfulde. Truer to the project's
  purpose; proves the pipeline works for languages that do not map onto
  European orthography.

Running both is more load, and that is the accepted cost: Track A alone would
be faster, but Track B is the one that validates the claim the project makes.

### Tasks

1. `LOCALE_PATHS`, `LANGUAGES`, and a real `makemessages` run — commit the
   first `.po` files.
2. Extract strings from templates and DRF messages; today they are inline
   literals.
3. **Non-Latin orthography readiness.** If Track B picks Ewondo or Duala, test
   rendering and sorting with diacritics early — this is where translation
   pipelines usually break, and it is cheaper to find now than after
   translating.
4. Flutter side: `intl` + ARB, language switch, and **`Story.language` wired to
   the reader's choice** rather than being decorative metadata.
5. **Translation contributor workflow** — this is what makes it prolific rather
   than a one-off. Someone must be able to submit a translation without
   touching Django.
6. ~~**Shared translation model**~~ — **moved to Phase 0** in revision 3. It
   was sitting here while gating Phase 4's schema, which is the wrong direction
   for a dependency. This phase now starts from that decision already made.

---

## Phase 6 — Community and moderation at real volume

0 story flags, 0 badges, 9 quiz attempts: the engagement loop has never run
with real traffic, so its behaviour under load is unknown.

**Depends on 7.** Task 1 is a load test, and there is nothing to load until
Phase 7 has built the corpus. Tasks 2 and 3 do not need volume and can start
any time after Phase 4.

### Tasks

1. **Moderation at volume.** The queue is already `select_related`'d and adds 0
   extra queries (measured: 38 queries for 3 flagged stories, same as
   baseline) — an earlier audit claim of an N+1 here was disproven. What is
   untested is behaviour at realistic volume; the 6 tests added in `1b57e34`
   are a start, not a load test.
2. **Flag reasons.** The five reasons are fixed enums; confirm they match what
   contributors actually want to report, and that `other` captures a text field
   usefully.
3. **Contributor trust loop** — retention mechanics for people whose stories
   get moderated. A rejected contributor currently has no reason to return.
4. **Seeded demo data for the engagement loop.** `seed_all` should be able to
   produce flags, badge awards, and quiz attempts so the moderation and
   gamification paths are exercised in development. Marked synthetic via
   `origin`, so it never masquerades as real.

   **Scope note**: this is the *engagement artefacts* only — the story corpus
   they hang off comes from Phase 7, which runs first. Like Phase 7 task 4,
   these rows must be produced by exercising the real code paths, not inserted.
   Keeping the two phases separate is a review decision: 7 owns "enough
   content to demo", 6 owns "the loop behaves under traffic".

---

## Phase 7 — Seed data at volume

**Added after review.** The corpus is thin in a way that limits what can be
demonstrated and tested: 12 stories, 9 quiz attempts, 0 flags, 0 badges.

**Depends on 3 and 4.** Badge awards only arise from real code once Phase 3's
trigger is fixed, and story submissions only arise once Phase 4's contributor
path exists. Runs **before** Phase 6 — see the sequencing table.

### Tasks

1. **Scale `seed_stories` to ~60–80 stories** across all ten regions and
   multiple categories, with varied `language`, `cultural_context`, and
   `moral_lesson` values.
2. **Quizzes to match** — `ensure_story_quizzes` should cover every seeded
   story with a real question set, not 4 generic questions.
3. **Mark everything synthetic** via `origin` and `provenance_notes`. Seeded
   content must never be presentable as real oral tradition — that distinction
   is the point of the provenance work in `ee3b0c9`.
4. **Do not seed away the diagnostic signal.** Badges awarded, flags raised,
   and non-`other` artifact categories should be produced by *exercising the
   real code paths* (Phase 3's fixed award trigger, and the app's own flagging,
   submission, and quiz paths), not by inserting rows directly. A seeded
   `UserBadge` would hide exactly the bug Phase 3 exists to find.

---

## Phase 8 — The leaked database

**Added after review; split in revision 3.**
`backend/db.sqlite3.bak-20261002-180422` is untracked but **still on disk**
(1.9 MB, 523 users and their password hashes), and the blob entered history at
`ee3b0c9`, so it is present in every commit from there forward. Ignoring the
pattern prevents recurrence; it does not remove what is already published.

The split matters because the two halves run on different clocks. **8a is the
least expensive item in this document and the only one whose cost rises with
delay** — it needs no sign-off and no coordination. **8b is destructive,
irreversible, and waits on people**, not on phases. So 8a moves to the front of
the sequence and 8b moves to the back.

### 8a — Contain now

1. **Rotate the affected credentials first.** Any password hashes that reached
   a remote are compromised regardless of what happens to the file. This is
   the step that actually protects users, and it must happen *before* the
   rewrite, because the rewrite invalidates nothing on its own.
2. **Delete the file and ignore the pattern.** Remove
   `backend/db.sqlite3.bak-20261002-180422` from the working tree and add a
   `.gitignore` rule covering `db.sqlite3*` and `*.bak-*`. "Untracked" is not
   "deleted", and an ignore rule alone protects nothing that is already there.

### 8b — Rewrite later

_Behind explicit sign-off; not scheduled against any engineering phase._

1. **Rewrite history** (`git filter-repo`, or BFG) to purge
   `db.sqlite3.bak-*` from every commit.
2. **Force-push** and have collaborators re-clone. Destructive and
   irreversible — needs explicit sign-off, and anyone with a stale clone will
   re-push the blob on their next push.
3. **Verify** `git log --all --diff-filter=A -- '*sqlite3*'` returns nothing.
4. **If the repo was ever public**, assume the hashes are already in someone's
   clone and treat 8a step 1 as the actual remediation.

---

## Phase 10 — Voice capture

**Split out of Phase 4 in revision 3.** Oral tradition has a sound dimension
the current model only half-represents: `AudioNarrationJob` exists for TTS, but
there is no path for a contributor's own recording.

1. **Decide whether it is in scope at all.** This is a product question, and it
   was parked inside a phase that already had four unambiguous tasks. Answering
   it up front keeps Phase 4 shippable.
2. **If yes, this is the schema for it.** Language-specific, so it lands after
   Phase 0 has settled the translation model and after Phase 4's consent capture
   — a recording is a rights-holder artefact and consent is collected in 4.2.

---

## Sequencing

| # | Phase | Leverage | Cost | Depends on | State |
|---|---|---|---|---|---|
| 1 | **8a. Contain the leak** | High (security) | Very low | your go-ahead | Done — rotation outstanding |
| 2 | 1. Artifact taxonomy | Very high | Low–Med | — | **Landed** `ef2a8a8` |
| 3 | 2. Gates | High | Low | — | **Landed** |
| 4 | 3. Gamification | High | Low–Med | — | **Landed** |
| 5 | **0. Translation-model decision** | High | Very low | — | **Decided** |
| 6 | 4. Stories | Very high | High | 0, constitution check | **Landed** — consent gap closed |
| 7 | 5. Multilingual (2 tracks) | Very high | High | 0 | Not started |
| 8 | 7. Seed data | Medium | Low–Med | 3, 4 | Not started |
| 9 | 6. Community at volume | Medium | Medium | 4, 7 | Not started |
| 10 | 9. What an Artifact is | High | Med | 1 | Not started |
| 11 | 10. Voice capture | Medium | Med | 0, 4 | Not started |
| 12 | **8b. Rewrite history** | High (security) | Low | 8a + sign-off | Not started |

The `#` column is execution order. The label carries each phase's own number,
which no longer runs in sequence — Phase 9 was written mid-implementation, and
Phases 0 and 10 were added by this review — so read `#`, not the label.

**What revision 3 changed, and why:**

- **8a moved to the front.** It takes minutes, needs no engineering, and is the
  only item in this plan that gets worse the longer it waits. Everything else
  here is recoverable; leaked password hashes are not. 8b is deliberately last:
  it is irreversible and blocked on coordinating re-clones, not on code.
- **The old critical path is dissolved.** It read *"Phase 5 task 6 (shared
  translation model) must be decided before Phase 4 writes non-English stories"*
  — serialising an entire High-cost phase behind a decision that takes an
  afternoon. That decision is now Phase 0, so **Phases 4 and 5 run in parallel**
  and neither waits on the other.
- **The 6 ↔ 7 arrows were backwards.** The old table said 7 depends on 6, while
  6's headline task is a load test needing the corpus 7 builds. Both phases stay
  separate (review decision) but the arrow runs **7 → 6**. Phase 7 in turn needs
  3 — so badge awards come from the fixed trigger rather than a seeded row — and
  4, so there is a submission and flagging path to exercise.
- **Voice capture left Phase 4.** It was the one task in that phase with an
  unresolved *whether* rather than a *how*, sitting inside a phase already rated
  High cost.
- **Phase 1's consumer wiring moved to Phase 9**, because choosing which
  taxonomy a user filters on is the same question Phase 9 exists to answer.

**Recommended first move**: Phase 8a, today — no code, no sign-off, and the
highest-irreversibility item on the list. Second, finish Phase 2, which is now
done: ruff clean, coverage measured and gated, crawler tests in CI,
pre-commit config written. Phase 1 itself is done too; its payoff waits on
Phase 9. Next up is Phase 3.

One correction carried into the working tree: the earlier in-flight lint diff
concentrated all of its line-ending churn in a single file —
`backend/users/views.py` showed 349 changed lines, of which exactly 1 was
substantive. `.gitattributes` (`* text=auto eol=lf`) already normalises on
checkin, but that file's HEAD blob predates it and still carries CRLF, so its
next checkin will rewrite every line. The churn was reverted so the lint commit
stayed reviewable; the normalisation is a one-file commit whenever someone
wants it, never collateral inside a lint pass.

## Still excluded

- **Performance work.** Nothing in the last audit pointed at a real bottleneck;
  Fix 4 already took the analytics dashboard from 124 queries to 38. Revisit if
  Phase 6 load testing surfaces something.