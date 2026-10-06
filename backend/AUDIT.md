# Project Audit — 2026-09-19

Full audit of the Griot 2.0 backend performed 2026-09-19 (Codebuff session).
Baseline: Django 5.2.4 / DRF 3.16 / Python 3.14, 141 tests.

## Checks performed

| Check | Result |
|---|---|
| `manage.py check` | 0 issues |
| `makemigrations --check --dry-run` | No migration drift |
| Test suite (`config.settings.test`) | 141 tests, 1 failure → fixed (see below), now OK |
| Hardcoded secrets scan | None found (env-var discipline holds) |
| SQL injection (`raw`/`extra`) / TLS (`verify=False`) | None found |
| `.gitignore` coverage | `db.sqlite3`, `server.log`, `staticfiles/` all ignored |
| Settings security | prod fail-fast on insecure key/hosts; auth throttle 5/min; JWT rotation+blacklist; analytics role-gated; health endpoints aggregate-only |

## Bug found & fixed

**`web/views.py::story_detail_view`** — the quiz lookup was nested inside the
`request.user.is_authenticated` block, so anonymous visitors never saw the
"Sign in to take quiz" card on story pages (breaking mobile parity and failing
`web.tests.QuizzesHubTests.test_story_shows_quiz_to_anonymous_visitors`).
Fix: hoist the quiz lookup above the auth branch. Suite is green.

## Findings & disposition

1. **Deprecated `artifacts` app still mounted** (duplicate QR landing page,
   empty models, README drift) → resolved by feature
   `specs/001-retire-artifacts-app` (runtime retirement + 301 redirect for
   printed QR codes; migration history preserved on disk).
2. **`dev.py` `ALLOWED_HOSTS` contained `'*'`** (host-header permissiveness)
   → resolved by feature 001: wildcard removed; test settings scoped to
   `testserver`/localhost/loopback; prod untouched (env-sourced).
3. **`test_quiz_api.py` at repo root** — standalone smoke script (guarded by
   `__main__`, safely import-discovered). OPEN (low priority): consider moving
   under an app or `scripts/` for consistency.
4. **No submission-approval workflow** — stories can be submitted for review,
   but no product path approves/rejects them (spec'd as feature
   `specs/002-story-submission-moderation`).

## Governance

The audit's security and testing observations are codified in the project
constitution (`.specify/memory/constitution.md`, v1.0.0): API/Web/Flutter
parity, security by default, test-first regression coverage, cultural data
integrity, observability.

---

# Audit — 2026-10-02

Full-project audit of the Griot 2.0 monorepo (Django backend, Flutter client,
crawler, CI/deploy config). Baseline: Django 5.2.17 / DRF 3.17.2 / Python 3.12.10
deployed, 3.14.7 local.

The 2026-09-29 pass below fixed real defects and its remediation holds up: no
SQL injection, no `verify=False`, no unparameterised queries, no secrets in
tracked files, correct permission wiring, and clean `IDOR` checks on the
profile-delete and moderation paths. This pass found the security posture sound
and the **process** around it weak. Findings were worked in severity order.

## Validation

| Check | Result |
|---|---|
| `manage.py check` (`config.settings.test`) | 0 issues |
| `makemigrations --check --dry-run` | No migration drift |
| Backend suite | **405 tests, OK (6 skipped)** |
| `flutter analyze --fatal-infos` | No issues found |
| Flutter suite | 320 tests, all passed |
| OpenAPI schema (`manage.py spectacular`) | **0 warnings, 0 errors** — was 48 issues |
| `pip-audit` | 1 advisory, unreachable — see R1, unchanged |

All of the above now runs in CI on every push and pull request
(`.github/workflows/ci.yml`), which is the actual fix behind the numbers.

## HIGH

| # | Finding | Resolution |
|---|---|---|
| H-1 | **The suite was red and nobody knew.** `users/tests.py::TokenTests.setUp` had been replaced by a debug `logging` call that read `self.user` before creating it, so both token tests errored with `AttributeError`. The same edit had also deleted `test_refresh_rotates_tokens` — the regression test pinning `ROTATE_REFRESH_TOKENS`/`BLACKLIST_AFTER_ROTATION`. | Fixture restored (now chaining `super().setUp()` so the auth throttle counter is cleared), rotation test restored and strengthened to assert the refreshed token differs from the spent one, debug logging removed. |
| H-2 | **No CI at all.** `.github/workflows/` held only a keep-alive ping. Nothing ran the backend suite, `flutter analyze`/`test`, or `pip-audit`. This is why H-1 sat unnoticed while this file reported "365 tests, OK" — the validation table was a manual claim, not an enforced gate. | New `ci.yml`: Django checks + migration drift + prod fail-fast guard + backend suite; `flutter analyze --fatal-infos` + suite; `pip-audit` (advisory-only, see R1). |
| H-3 | The broken test file also carried a **whole-file CRLF→LF conversion** — 1160 changed lines in a 577-line file, which buries a three-line bug fix in review. The repo has mixed EOL conventions and no `.gitattributes`. | Root `.gitattributes` added (`* text=auto eol=lf`, with CRLF preserved for `.bat`/`.cmd` and binaries excluded). Real content diff is now 12 insertions. |

## MEDIUM

| # | Finding | Resolution |
|---|---|---|
| M-1 | **Rate limits and JWT revocation were per-process.** No `CACHES` was configured anywhere, so DRF throttles (the 5/min auth budget, 10/min metrics), `config.rate_limit`, and the SimpleJWT blacklist all ran on a per-process `LocMemCache`. Under `--workers N` every limit is silently multiplied by N, and a refresh token blacklisted by one worker still validates on another. | `CACHES` in `base.py` is now `REDIS_URL`-driven (Django's built-in `RedisCache`, 2 s socket timeouts, `KEY_PREFIX`), falling back to `LocMemCache` with a loud stderr warning whenever `DEBUG` is off. `Procfile` dropped `--workers 2` → `1` so the deployed limit matches the configured one, with the reason documented in both files. `config/settings/test.py` pins `LocMemCache` so the suite never depends on a developer's `REDIS_URL`. |
| M-2 | **A production server with no `LUMA_API_KEY` faked success.** `get_luma_service()` fell back to `MockLumaAIService`, which marks jobs `completed` and points `video_url` at an unplayable `storage.example.com` placeholder — spending the caller's daily quota and reporting a finished render that plays nothing. Nothing distinguished "no key because we are developing" from "no key because nobody set it". | Two switches, because there are two different questions. `LUMA_ALLOW_MOCK` (defaults to `DEBUG`) decides whether the mock may answer *at all* when nothing is configured; with no key and no opt-in, `get_luma_service()` raises `VideoProviderError` (still caught everywhere as `LumaAIError`) naming `LUMA_API_KEY` and `FAL_API_KEY`. `VIDEO_ALLOW_MOCK_FALLBACK` (defaults on) is the broader, newer one: whether the mock may stand in when *every* live provider is out of credits, so a spent balance answers instead of 502ing — set it to `0` to restore the strict gate. Whichever path serves it, the job is stamped `provider='mock'` / `engine='luma-mock'` and `store_video_asset` refuses to chase the placeholder, so nothing fake is ever credited to a vendor. All five call sites honour the strict path: create returns 502 with the job marked FAILED, cancel still succeeds locally, poll returns stored state instead of 500, and both web paths report an honest error. Pinned by `media_app/tests_luma_config.py` (`LumaServiceResolutionTests`, `LumaAPIViewTests`, `LumaWebServiceTests`, `MockFallbackTests`) and `media_app/tests_video_providers.py::VideoServiceFactoryTests`. |
| M-3 | **Video generation was wired to a retired vendor endpoint.** `POST https://api.lumalabs.ai/dream-machine/v1` answers `403 Not authenticated` for *every* bearer token, valid or not: the product moved to `https://agents.lumalabs.ai/v1` with a mostly different payload (`model`, `type`, `video.duration` as the strings `"5s"`/`"10s"`, image input as `video.start_frame` rather than `image_url`), no cancel route (`DELETE` → `405`), and presigned output URLs that expire in an hour. Every render 502'd with a message that pointed at authentication, and the key was not the problem. | `LumaProvider` rewritten against the Agents API and verified against the live host — 401 bad key, 400 unknown model, 402 no credits, 422 for a missing prompt (whose `detail` is a *list*, not a string). Duration is snapped rather than rejected, `cancel_job` degrades to a documented no-op, and `_first_output_url` reads the `output` array. Because a single vendor retiring an endpoint is precisely what surfaced this, submit now runs an ordered chain: `LumaProvider` → `FalProvider` (fal.ai queue API, `Authorization: Key`, `COMPLETED` read as failed when `error` is present, model id packed into the job id) → `MockVideoProvider`. `ProviderUnavailable` advances, `ProviderRejected` stops. Jobs carry a new `provider` column (migration `0006` backfills existing rows) so polls and cancels route to the vendor that issued the id. Pinned by `media_app/tests_luma_transport.py` and `media_app/tests_video_providers.py`. |

## LOW

| # | Finding | Resolution |
|---|---|---|
| L-1 | `django.views.static.serve` is mounted at `MEDIA_URL` in production. Safe against traversal, but not hardened: no caching, no `Range` support, no ETag — which matters for the audio and video this app serves. | Kept (Render's free tier has neither a disk nor a media service) but the trade-off is now written down at the route, along with the exit condition. Pinned by `config/tests/test_media_serving.py`, which asserts traversal is refused — so the decision has a test rather than a comment. |
| L-2 | **48 OpenAPI schema issues.** Integer pks published as `string`; ~20 unannotated serializer methods; and `APIView`s that built their serializer by hand without declaring `serializer_class`, which made the generator skip them entirely — `/api/users/me/`, all seven admin analytics endpoints, both media viewsets and the deep-link lookup were **absent from the published schema**. | All 48 cleared: return type hints on the serializer/model methods, `serializer_class` on the seven analytics views, `@extend_schema` response/parameter annotations on the health, lookup, redirect, leaderboard, media-status and `me` endpoints, and named `ENUM_NAME_OVERRIDES` for the colliding choice sets. Ids now publish as `integer` (verified in the generated schema, not just warning-free). Pinned by `config/tests/test_openapi_schema.py`. |
| L-3 | `web/test_security_poc.py` was a 534-line permanent regression suite whose classes were already named `...Regression`. Only the filename still said "PoC", and `artifacts/security-review.md` referenced class names that no longer existed. | Renamed to `web/test_security_regressions.py`; the historical review keeps its record and gains a note mapping the old names to the new ones and the command to run them. |
| L-4 | `test_quiz_api.py` sat at the backend root (open since the 2026-09-19 audit, finding 3). | Moved to `scripts/quiz_api_smoke.py` — out of unittest discovery's `test*.py` pattern entirely, and runnable from any directory. |
| L-5 | **Python version drift.** Local development ran 3.14.7 while `render.yaml` deployed 3.12.10, and nothing tested either. | CI pins 3.12.10, matching `render.yaml` exactly, with the coupling documented in both files and in `backend/README.md`. 3.14 still passes locally and is noted as such. |
| L-6 | `render.yaml` documented that an unset `LUMA_API_KEY` silently degrades video generation — a footgun documented but not fixed. | Fixed as M-2 above; the comment now describes the provider chain, that both keys must be unset to reach the mock, and `VIDEO_ALLOW_MOCK_FALLBACK=0` as the switch that makes it fail loudly instead. `backend/.env.example` documents the same knobs. |

## Corrections to the 2026-09-29 record

This file's earlier Validation table said "365 tests, OK". At the start of this
pass the suite actually ran **384 tests with 2 errors** — see H-1. Two other
claims were also wrong:

- **gTTS.** The 2026-09-29 entry cites "gTTS 2.5.4 (the current release)" but
  `requirements.txt` pinned **2.5.1**. Re-verified on PyPI: 2.5.4 is current and
  still pins `click>=7.1,<8.2`, so residual risk **R1 stands unchanged**.
- **Finding 4 (no submission-approval workflow) is resolved.** The workflow
  exists: `IsAdminOrManager` gates `moderation_queue` and `moderate` in the
  API, and `web/services.py::moderate_story` plus
  `web/actions.py::story_moderate` cover the web path, with `reviewer_notes`
  and the story `status` field carrying the outcome.

## Residual risk

**R1 — `click==8.1.8` / PYSEC-2026-2132.** Unchanged and still unreachable:
gTTS pins `click>=7.1,<8.2`, the app only imports gTTS's library entry point
and never reaches `click.edit()`, and resolving it needs either a gTTS that
relaxes the pin or dropping the dependency. The new `pip-audit` CI job is
`continue-on-error` for exactly this one advisory — it exists to tell you when
a *second*, genuinely exploitable one arrives.

---

# Remediation pass — 2026-09-29

Full-stack security remediation covering the Django backend, the Flutter client,
the crawler and CI/deploy configuration. Findings were worked in severity order
(P0 critical → P3 low). Every behavioural change below is covered by a
regression test; the counts in *Validation* are the numbers at the end of the
pass.

## Validation

| Check | Result |
|---|---|
| `manage.py check` (`config.settings.test`) | 0 issues |
| `makemigrations --check --dry-run` | No changes detected |
| Backend suite | 365 tests, OK (6 skipped) — was 309 at the start of this pass |
| `flutter analyze` | No issues found |
| Flutter suite | 320 tests, all passed |
| `pip-audit` (backend venv) | 1 residual advisory, unreachable — see R1 |

## P0 — critical

| # | Finding | Resolution |
|---|---|---|
| P0-1 | Demo seed data (known-credential users, artifacts, stories) shipped in release builds | Seed paths are gated on `kReleaseMode`; published builds start from an empty database. |
| P0-2 | Offline-registration passwords stored as plaintext in SQLite | `LocalCredentialHasher` (PBKDF2-HMAC-SHA256, per-record salt, versioned record format) is the only writer of local credentials. |
| P0-3 | `local_users` / `offline_users` had plaintext password columns | Schema **v8** removes the columns. Hashes live only in platform secure storage. |
| P0-4 | Pending offline registrations held the password in the database before sign-in | Passwords are held in `flutter_secure_storage` and removed on completion, on cancellation, and on logout. |
| P0-5 | A 401 from the server did not clear the local session, so the UI kept acting as signed-in | 401 is now authoritative: tokens are cleared and the session is invalidated. |
| P0-6 | Release signing config fell back to the debug keystore | The release `signingConfigs` block fails the build rather than falling back. |
| P0-7 | Queued offline requests persisted the `Authorization` header into SQLite | Credentials are stripped before an entry is queued and re-attached at send time. |

## P1 — high

| # | Finding | Resolution |
|---|---|---|
| P1-8 | "Quiz answers leak to the client" | **False positive.** Re-verified: the endpoint returns per-question correct/incorrect state only for the authenticated submitting user. Recorded here rather than changed; altering it would break answer feedback. |
| P1-9 | AI media generation was uncapped | `VIDEO_GENERATIONS_PER_USER_PER_DAY` and `AUDIO_NARRATIONS_PER_USER_PER_DAY` bound spend per account. |
| P1-10 | Outdated dependencies with published advisories | Django 5.2.17, DRF 3.17.2, simplejwt 5.5.1, Pillow 12.3.0, PyJWT 2.15.1, python-dotenv 1.2.3, requests 2.33.1. Crawler floors raised to `requests>=2.33.0` and `lxml>=6.0.0`. |
| P1-11 | Logout left user data on the device | `AppDatabase.wipeUserScopedData()` clears `local_users`, `offline_users`, `local_user_gamification`, `local_quiz_attempts`, `search_history` and `offline_requests` in one transaction; secure-storage credentials are deleted too. |
| P1-12 | Android auto-backup uploaded the app database | `data_extraction_rules.xml` and `full_backup_content` exclude the database and shared preferences. |

## P2 — medium

| # | Finding | Resolution |
|---|---|---|
| P2-13 | `X-Forwarded-For` trusted unconditionally and stored as `ip_address` | `config/client_ip.py::get_client_ip` walks the chain right-to-left and only believes a forwarded value when the socket peer is in `TRUSTED_PROXY_IPS` (empty by default). Unparseable entries are skipped, never returned. |
| P2-14 | Registration PII disclosure on duplicate email | **Partly false positive, partly real.** The replay branch returns the full user only when the request carries the account's exact username *and* password, so a wrong-password caller gets nothing — pinned by `RegistrationDoesNotLeakPII`. The real defect was that the lookup ran on raw `request.data` before validation, so a JSON `email` of a list or number raised `AttributeError` on an unauthenticated endpoint (a 500). `normalize_email` now type-guards and the malformed body falls through to normal validation. |
| P2-15 | Registration user enumeration | **Accepted, not fixed.** A distinct "email already registered" error is required for usable account creation UX. Mitigated by `AuthRateThrottle` at 5/min. |
| P2-16 | Compiled-in `http://` API base URL | `AppConstants.assertCleartextBaseUrlIsSafe()` runs at startup and throws when `RELEASE_BUILD=true` is combined with a cleartext origin. A release must build with `--dart-define=API_BASE_URL=https://… --dart-define=RELEASE_BUILD=true`. |
| P2-17 | No certificate pinning | **Not implemented — documented gap.** Pinning in a Flutter client that must survive certificate rotation risks bricking installs; the compensating control is the CSP plus HTTPS enforcement above. |
| P2-18 | `developer.log('Deep link received: $uri')` survived release builds and logged attacker-supplied URIs | All three deep-link log calls now use `debugLog`, which is compiled out of release. The URI is still parsed and routed. |
| P2-19 | Unbounded media download: whole body buffered in memory, no timeout, no size cap, no host check | `MediaDownloader` streams to disk with a 64 MiB cap, a 2-minute budget, a 30 s idle timeout, HTTPS-only outside debug, and an API-host allowlist. Partial files are deleted on failure. |
| P2-20 | Web build kept tokens in `localStorage` with no CSP | `SecureStorageFactory` centralises construction: session storage on web, optional RSA-OAEP wrap key via `--dart-define`, Keychain/EncryptedSharedPreferences defaults on native. `web/index.html` now ships a deny-by-default CSP with `script-src 'self'` and no `unsafe-inline`. |
| P2-21 | Luma AI requests had no timeout and no transport-error handling | `LiveLumaAIService` sets a `(10, 30)` connect/read timeout. `requests.RequestException` is translated to `LumaAIError` on submit (view returns 502 and marks the job failed) and degrades to `in_progress` on poll so the client's poll loop survives. |
| P2-22 | `/api/health/metrics/` returned exact record counts to an anonymous caller | Counts are rounded **up** to the next power of two (`_banded_count`), so monitors keep the order of magnitude while the exact total is not recoverable by differencing. A dedicated `metrics` throttle scope of 10/min was added. |
| P2-23 | `sync_local_users` copied password hashes verbatim from a developer SQLite file | `is_hash_safe_to_copy` accepts only a hash matching the deployment's preferred hasher. Raw digests, the unusable marker and empty values become `set_unusable_password()`; the account is still created and reported for a forced reset. |

## P3 — low

| # | Finding | Resolution |
|---|---|---|
| P3-24 | Inline `<script>` in `web/index.html` | Moved to `web/splash.js` so `script-src 'self'` needs no `'unsafe-inline'`. |
| P3-25 | Hardcoded WhatsApp feedback number interpolated unvalidated into a URL | Now `--dart-define=FEEDBACK_WHATSAPP_NUMBER` with a default, and `isValidWhatsAppNumber` rejects any value carrying URL structure before it reaches the link. |
| P3-26 | `String.hashCode` used for media cache filenames | Replaced with a SHA-256 of the URL. Dart's `String.hashCode` is unstable across runs and collides, which let two stories share one cached file. |
| P3-27 | `MeView.delete` returned a body with `204 No Content` | The body is removed; a 204 carries no payload by definition and clients disagreed about what to do with the extra bytes. |
| P3-28 | `view_count` incremented with a read-then-write | Now `F('view_count') + 1`, so concurrent readers no longer lose increments. |
| P3-29 | Deep-link slug was not validated before becoming a route argument | `AppDeepLink.isValidSlug` enforces the backend's `SlugField` grammar (Unicode letters/numbers, `-`, `_`) and a 250-char limit, rejecting traversal, separators and control characters. |
| P3-30 | Deep-link scheme never registered with the OS | Not reachable on any target, so not a code change. Intentional: the printed QR codes use `https://griot-ai.org/...`, which needs no scheme registration. |

## Residual risk

**R1 — `click==8.1.8` / PYSEC-2026-2132 (CVE-2026-7246).** Reported by
`pip-audit` and **not fixed**. `gTTS` 2.5.4 (the current release) pins
`click>=7.1,<8.2`, so there is no version to upgrade to. The advisory covers
`click.edit()`; the application reaches `gTTS` through `from gtts import gTTS`,
which does not import `click.edit`, and the app never calls it. Fixing this
requires either a `gTTS` that relaxes the pin or dropping the dependency.

**R2 — registration user enumeration** (P2-15) is accepted by design and
mitigated by throttling rather than eliminated.

**R3 — certificate pinning** (P2-17) is not implemented; see the rationale in
the P2 table.

## Still open from the 2026-09-19 audit

- Finding 3: `test_quiz_api.py` — **resolved** in the 2026-10-02 pass (L-4).
- Finding 4: story submission moderation — **resolved**, see the 2026-10-02
  corrections above.
