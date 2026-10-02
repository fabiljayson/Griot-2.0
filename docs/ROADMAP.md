# Prolificity Roadmap

**Date**: 2026-10-02 | **Baseline commit**: `1b57e34` | **Revision**: 2 (reviewed)

A plan to raise output on all four axes we agreed on: shipping code faster,
producing more content, growing the community, and raising the quality floor.

Phases 1–3 are small enough to land as normal pull requests. Phases 4–6 are
expanded here in full task detail rather than deferred to separate specs — the
review asked for concrete work items, so that is what this document contains.
Each of 4–6 still needs a constitution check before implementation, but the
scope is no longer open.

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

---

## Phase 1 — Split the artifact taxonomy

**Why first**: it is the cheapest fix in this plan and the largest single
quality gain in the data. It also unblocks browse, filtering, QR labelling,
and search, all of which are currently fed garbage.

**Review decision**: do the full field split now, not a minimal patch.

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
   rows we cannot classify. Indexed, because browse filters on it. Migrate.
   `category` keeps its nine existing values and choices untouched.
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

---

## Phase 2 — Make the gates real

Every later phase adds code. These are the mechanisms that stop the same class
of defect as Phase 1 recurring unnoticed.

### Tasks

1. **Run the crawler tests in CI.** `ci.yml` has backend, frontend, and deps
   jobs; the 5 tests in `crawler/test_*.py` run in none of them. Add a
   `crawler` job.
   - Blocker first: there is **no crawler environment**. Those tests only run
     under `backend/.venv-linux/bin/python`, because `bs4`/`lxml`/`httpx` live
     there. Add `crawler/requirements-dev.txt` or document the shared
     interpreter explicitly. Today the fact is undocumented and breaks for
     anyone else.
2. **Add `ruff`** for lint. `manage.py check` is a Django system check, not a
   lint. Budget for a cleanup commit separate from the enabling commit.
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
5. **Voice capture.** Oral tradition has a sound dimension the current model
   only half-represents (`AudioNarrationJob` exists for TTS). Decide whether
   contributor-recorded audio is in scope; if yes, this is the schema for it.

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
6. **Shared translation model.** Stories must not be duplicated per language.
   Model translation as a relation on `Story`, or the same tale ends up in
   three rows and three moderation queues. Decide this **before** the first
   non-English story is written, not after.

---

## Phase 6 — Community and moderation at real volume

0 story flags, 0 badges, 9 quiz attempts: the engagement loop has never run
with real traffic, so its behaviour under load is unknown.

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

---

## Phase 7 — Seed data at volume

**Added after review.** The corpus is thin in a way that limits what can be
demonstrated and tested: 12 stories, 9 quiz attempts, 0 flags, 0 badges.

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
   real code paths* (Phase 3, Phase 6), not by inserting rows directly. A
   seeded `UserBadge` would hide exactly the bug Phase 3 exists to find.

---

## Phase 8 — Purge the leaked database from history

**Added after review.** `backend/db.sqlite3.bak-20261002-180422` is
untracked as of `1b57e34`, but it remains in history at `54ef15c` containing
523 users and their password hashes. Ignoring the pattern prevents recurrence;
it does not remove what is already published.

### Tasks

1. **Rotate the affected credentials first.** Any password hashes that reached
   a remote are compromised regardless of what happens to the file. This is
   the step that actually protects users, and it must happen *before* the
   rewrite, because the rewrite invalidates nothing on its own.
2. **Rewrite history** (`git filter-repo`, or BFG) to purge
   `db.sqlite3.bak-*` from every commit.
3. **Force-push** and have collaborators re-clone. Destructive and
   irreversible — needs explicit sign-off, and anyone with a stale clone will
   re-push the blob on their next push.
4. **Verify** `git log --all --diff-filter=A -- '*sqlite3*'` returns nothing.
5. **If the repo was ever public**, assume the hashes are already in someone's
   clone and treat step 1 as the actual remediation.

---

## Sequencing

| Phase | Leverage | Cost | Depends on |
|---|---|---|---|
| 1. Artifact taxonomy | Very high | Low–Med | — |
| 2. Gates | High | Low | — |
| 3. Gamification | High | Low–Med | — |
| 4. Stories | Very high | High | constitution check |
| 5. Multilingual (2 tracks) | Very high | High | 5.6 decides 4's schema |
| 6. Community at volume | Medium | Medium | 4 |
| 7. Seed data | Medium | Low–Med | 3, 6 |
| 8. History purge | High (security) | Low | credential rotation |
| 9. What an Artifact is | High | Med | Phase 1 |

Phases 1–3 are independent and can run in any order or in parallel. Phase 8 is
low effort and should be scheduled early rather than deferred indefinitely,
but step 1 (credential rotation) is a decision that belongs to the user, not
the schedule.

**Critical path**: Phase 5 task 6 (shared translation model) must be decided
before Phase 4 writes non-English stories, or the schema will have to change
after content exists.

**Recommended first move**: Phase 1. Roughly a day, fixes a defect actively
degrading the data, and Phase 2's linter would otherwise run against a
codebase that still had the bug in it.

## Still excluded

- **Performance work.** Nothing in the last audit pointed at a real bottleneck;
  Fix 4 already took the analytics dashboard from 124 queries to 38. Revisit if
  Phase 6 load testing surfaces something.