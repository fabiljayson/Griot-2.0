# Security Review — Web App + Backend

> **Note on running the tests named below.** This document is the original
> review record, so the class names, test names and sample output in it are
> preserved as they were on 2026-09-29. The suite has since been renamed and
> its classes renamed from `...PoC` to `...Regression` (they no longer assert
> vulnerable behaviour, so "PoC" was actively misleading):
>
> - File: `backend/web/test_security_poc.py` → **`backend/web/test_security_regressions.py`**
> - Classes: `WebQuotaBypassPoC` → `WebQuotaBypassRegression`,
>   `WebAuthControlsPoC` → `WebAuthControlsRegression`,
>   `WebOpenRedirectPoC` → `WebOpenRedirectRegression`,
>   `WebUnthrottledWritePoC` → `WebScanDedupeRegression`,
>   `WebXpFarmingPoC` → `WebXpFarmingRegression`
> - Test methods: `test_poc_NN_*` → descriptive names (e.g.
>   `test_poc_02_login_not_throttled` → `test_login_is_throttled_after_limit`)
>
> Run the current suite with:
>
> ```bash
> DJANGO_SETTINGS_MODULE=config.settings.test python manage.py test \
>     web.test_security_regressions -v 2
> ```
>
> `WebPositiveControls` kept its name.

**Scope:** `backend/web/` (Django server-rendered web interface, session auth) and
the `backend/` Django REST API and its apps.
**Explicitly out of scope:** `frontend/` (Flutter), `crawler/`, CI/deploy config.

| Field | Value |
| --- | --- |
| Date | 2026-09-29 |
| Commit audited | `84dc51a` (post-remediation) |
| Trust class | `trusted` — maintainer-controlled local source, read-only review |
| Runtime mode | read-only filesystem inspection + sandboxed test-database execution; no credentialed writes, no outbound network |
| Method | `common-security-audit` + `common-exploit-verification` + `common-owasp` |
| PoC suite | `backend/web/test_security_poc.py` (18 tests) — since renamed to `test_security_regressions.py`, see the note above |
| Remediation | **All six findings fixed** — see "Remediation status" below |
| Regression check | full backend suite `385 tests OK (skipped=6)` — no regressions |

## Verdict

Six findings, all reproduced against a live test database. The root cause
behind five of the six is structural: the web interface was written as a
**parallel implementation** of the API rather than as a thin adapter over it.
`web/services.py` re-implements ownership checks, media quota, password policy
and validation responses. Every control the API enforces, the web path
re-decides — and the web path is the one that was missed.

A seventh candidate (open redirect via backslash) was investigated and
**discarded as a false positive**; see "Filtered candidates".

**No P0.** No credential leakage, no unauthenticated data access, no injection,
no stored XSS, no privilege escalation. The highest-impact issue is
unbounded third-party spend (F-01).

**All six findings are now remediated.** The finding sections below are
retained as the record of what was wrong and why each fix takes the shape it
does; read them alongside "Remediation status" for the current state.

## Remediation status

Each finding was fixed at the layer that owns the rule, so the API and the web
path cannot drift again — the structural root cause, not just the six symptoms.

| ID | Status | Fix |
| --- | --- | --- |
| F-01 | Fixed | Quota logic extracted to `media_app/quota.py`; the API and all three web media actions now call the same helpers, so the daily caps cannot diverge. |
| F-02 | Fixed | New `config/rate_limit.py` provides a cache-backed `rate_limit` decorator for plain Django views. Applied to `WebLoginView` (POST only, budget reset on success) and to `register` (IP-keyed, budget **not** reset on success). Governed by the new `WEB_AUTH_ATTEMPTS_PER_MIN` setting, mirroring the API's `auth: 5/min`. |
| F-03 | Fixed | `register_user` and the API `RegisterView` now return one generic refusal that does not identify which field collided. |
| F-04 | Fixed | Both `register_user` and `RegisterSerializer` now call `validate_password()`, so `AUTH_PASSWORD_VALIDATORS` is actually enforced on the web and API paths. |
| F-05 | Fixed | Scan writes collapse to one row per viewer per artifact per `SCAN_DEDUPE_WINDOW_SECONDS` window, enforced in `config/rate_limit.py:first_in_window`. Also switched from raw `REMOTE_ADDR` to the trust-aware `get_client_ip`. |
| F-06 | Fixed | New `gamification/services/quiz_xp.py` provides a DB-backed `already_earned_quiz_xp` guard, used by both the web and API finish paths. The reward is first-pass-only; retakes still count as streak activity. |

Two things were deliberately **not** changed, and the reasoning is recorded in
the relevant sections: the backslash open redirect (false positive) and the
`growth_bars` template tag (live code, not dead — an earlier note in this
review had it wrong).

One latent bug was found and fixed while remediating F-06: the web
`finish_quiz` badge sweep referenced `profile`, which was only bound inside the
payout branch. Once the payout became conditional, a retake would have raised
`UnboundLocalError`; `profile` is now resolved before the branch.

| ID | Finding | Severity | CVSS | Component |
| --- | --- | --- | --- | --- |
| F-01 | Web media actions bypass the per-user daily spend caps | High | 6.5 (7.5) | `web/services.py:775,831,889` |
| F-02 | Web login/register have no rate limit | Medium | 5.3 | `web/views.py:200` |
| F-03 | Web registration enumerates accounts | Medium | 5.3 | `web/services.py:999,1001` |
| F-04 | Configured password validators are never invoked | Medium | 5.3 | `web/services.py:1003`, `users/serializers.py:39` |
| F-05 | Anonymous scan logging is unmetered | Medium | 5.3 | `web/services.py:356` |
| F-06 | Quiz XP is farmable by unlimited retakes | Low | 4.3 | `web/services.py:612,667` |

CVSS in parentheses for F-01 assumes open, unverified self-registration (which is
the actual state) makes the "authenticated" precondition effectively free.

---

## F-01 — Web media actions bypass the per-user daily spend caps

**Vulnerability:** CWE-770 / CWE-400 — allocation of resources without limits
**Platform:** backend
**Severity:** High · **CVSS: 6.5** `AV:N/AC:L/PR:L/UI:N/S:U/C:N/I:N/A:H`
(7.5 if the free-registration precondition in F-04 is applied)
**OWASP:** A04:2021 Insecure Design · API4:2023 Unrestricted Resource Consumption

The API enforces per-user daily caps. The web actions do not.

- API: `media_app/views.py:82` reads `VIDEO_GENERATIONS_PER_USER_PER_DAY`;
  `media_app/views.py:323` reads `AUDIO_NARRATIONS_PER_USER_PER_DAY`.
- Web: `web/services.py:775` (`generate_story_audio`), `:831`
  (`generate_artifact_audio`) and `:889` (`generate_story_video`) contain
  **no reference to either setting**.

The only guard on the web path is a dedupe (`story`+`language` for audio,
one *in-flight* job for video), which is bypassed by varying the story, the
language, or simply waiting for a job to leave the `PENDING` state.

### Proof of Concept

Preconditions: a session. Video needs `contributor`+ and ownership of the
story; audio needs **any** authenticated user, because
`generate_story_audio` permits narrating any `PUBLISHED` story. Registration is
open and unverified, so obtaining a session is free.

```bash
DJANGO_SETTINGS_MODULE=config.settings.test \
  .venv-linux/bin/python manage.py test \
  web.test_security_poc.WebQuotaBypassPoC -v 2
```

1. Pin the cap to 1/day: `@override_settings(VIDEO_GENERATIONS_PER_USER_PER_DAY=1)`
2. Log in as a contributor owning 6 stories; POST
   `actions/story/<slug>/generate-video/` once per story with `luma` mocked.
3. **Expected (with the cap):** 1 `PENDING` job. **Actual:** 6.

**Evidence:**
```
test_poc_01a_video_cap_ignored_by_web_action ... ok
  → 6 VideoGenerationJob rows under VIDEO_GENERATIONS_PER_USER_PER_DAY=1
test_poc_01b_audio_cap_ignored_by_web_action ... ok
  → 6 COMPLETED AudioNarrationJob rows under AUDIO_NARRATIONS_PER_USER_PER_DAY=1
```

### Impact

- **Direct financial loss.** Luma bills per generation. The cap that exists to
  bound this spend is not consulted on the web path, so an attacker with any
  contributor account can render without bound.
- **Third-party abuse → deployment ban.** `gTTS` calls Google Translate's
  public TTS endpoint. Sustained traffic from this deployment's IP risks
  getting the app cut off from an endpoint it does not pay for.
- **Disk exhaustion.** Every narration writes an MP3 under `MEDIA_ROOT`; on
  Render's free tier that is container-local and unbounded.

**Blast radius:** paid API budget; egress reputation; node disk.

### Remediation

Do not re-implement the cap — that is the bug. Move the quota check into one
module both paths import, so the ceiling has a single definition.

**As implemented:** the existing API logic was extracted into
`media_app/quota.py` (`within_daily_cap`, plus `video_within_cap` /
`audio_within_cap` and the two cap accessors). Both API sites in
`media_app/views.py` were switched to call it, so API behaviour is unchanged and
its existing 429 tests still pass, and all three web actions in
`web/services.py` now call the same helpers:

```python
if not quota.video_within_cap(user):
    return (
        f'You have reached your daily video limit of '
        f'{quota.video_cap()}. Please try again tomorrow.',
        'error',
    )
```

Ordering is preserved deliberately: the cache-hit check runs **first**, so
re-reading a story that already has a narration or video stays free and is
never throttled. The cap is only consulted once a real synthesis or paid render
is about to start. The window remains a rolling 24 hours.

Prefer additionally delegating both web actions to the DRF views in
`media_app/` so the two implementations cannot diverge again.

---

## F-02 — Web login and registration have no rate limit

**Vulnerability:** CWE-307 — improper restriction of excessive authentication attempts
**Platform:** backend
**Severity:** Medium · **CVSS: 5.3** `AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N`
**OWASP:** A07:2021 Identification and Authentication Failures · API4:2023

`REST_FRAMEWORK['DEFAULT_THROTTLE_RATES']` sets `'auth': '5/min'`, but that
only applies to DRF views. The web views are plain Django functions and
`MIDDLEWARE` (`config/settings/base.py:76`) contains no rate-limiting
middleware, so `WebLoginView` and `register` are unmetered.

### Proof of Concept

```bash
DJANGO_SETTINGS_MODULE=config.settings.test \
  .venv-linux/bin/python manage.py test \
  web.test_security_poc.WebAuthControlsPoC.test_poc_02_login_not_throttled
```

60 consecutive wrong-password POSTs to `accounts/login/`.

**Expected:** `429` after 5. **Actual:** 60 × `200` (login form re-rendered),
`user: null` in every `api.request` log line.

### Impact

Unlimited online password guessing against any known username, with no lockout,
delay or alerting. Amplified by F-04 (weak passwords are accepted at signup)
and F-03 (usernames are enumerable).

### Remediation

Add a rate-limit middleware to `MIDDLEWARE` in `base.py` (scoped to
`/accounts/login/` and `/accounts/register/`), or subclass `WebLoginView` and
`register` with a `SimpleRateThrottle` on the same `auth` budget so the web and
API paths share one limit. Also enable `django.contrib.auth`'s
`LoginAttempt` lockout via `AXES` or equivalent.

**As implemented:** new `config/rate_limit.py` supplies a cache-backed
`rate_limit` decorator for plain Django views (DRF throttles never reach them),
governed by a new `WEB_AUTH_ATTEMPTS_PER_MIN` setting so the web and API
budgets stay tunable together. It returns `429` with a `Retry-After` header
instead of running the view. Applied as:

- `@rate_limit('web_login', methods=('POST',))` on `WebLoginView.dispatch`, with
  `reset_client_budget` on successful login so a user who mistyped once is not
  locked out of their own account.
- `@rate_limit('web_register', methods=('POST',), key_by='ip')` on `register`.

Three details that are easy to get wrong and are pinned by tests:

- `methods=('POST',)` so rendering the login/registration form does not consume
  budget.
- **Login** resets its budget on success (a successful guess is the legitimate
  user's own). **Registration deliberately does not** — a successful signup is
  precisely what the control exists to bound, so clearing on success would let a
  caller mint unlimited accounts.
- `key_by='ip'` on registration. A successful signup logs the caller in, so the
  default auth-aware key would rotate to each freshly minted user's primary key
  and hand every attempt a new budget — the throttle would never fire.

Cache backing matches the existing DRF throttles (Django's default cache), so
no new infrastructure is introduced. With no `CACHES` configured that default is
a per-process `LocMemCache`, so under `gunicorn --workers N` the effective
allowance is N times the limit. Configure a shared cache (Redis/Memcached) for an
exact global limit — this caveat applies to the pre-existing DRF throttles too.

---

## F-03 — Web registration enumerates accounts

**Vulnerability:** CWE-204 — observable response discrepancy
**Platform:** backend
**Severity:** Medium · **CVSS: 5.3**
**OWASP:** A07:2021 · API3:2023 Broken Object Property Level Authorization

`web/services.py:999` returns `"That username is taken."` and `:1001` returns
`"A user with this email already exists."` The API was believed to be hardened
in the opposite direction — `RegisterView.create` returns a single generic
`"Account already exists. Sign in at /api/auth/token/."` — so the web form
appeared to reintroduce a disclosure the API had removed.

**Correction found during remediation:** that belief was wrong.
`users/views.py:76-85` returned `{"email": ["A user with this email already
exists."]}` on a non-replay collision, so the API disclosed the same fact. The
documented generic path only covers the *verbatim replay* branch. Both surfaces
are fixed below; the fix was not limited to the web form.

### Proof of Concept

```bash
DJANGO_SETTINGS_MODULE=config.settings.test \
  .venv-linux/bin/python manage.py test \
  web.test_security_poc.WebAuthControlsPoC.test_poc_03_registration_discloses_account_existence
```

POST `accounts/register/` with an existing `username` and a fresh `email`.

**Expected (matching the API):** a generic message. **Actual:** HTTP 400 whose
body contains `That username is taken`.

### Impact

An attacker enumerates valid usernames offline, then targets them with F-02.

### Remediation

In `web/services.py:register_user`, replace both messages with one generic
`"Unable to create the account with those details."`, and keep the specific
text out of the form context.

**As implemented (both surfaces):**

- `register_user` uses a single `GENERIC_COLLISION` string for the username
  check, the email check, and the `IntegrityError` race path — the last matters
  because a name one field would otherwise re-open the same oracle through a
  different code path.
- `RegisterView.create` now raises a generic `{'detail': ...}` instead of
  naming `email`, matching the intent the API already documented.

The per-field detail is dropped rather than softened: a message like "that looks
like an existing username" is just as revealing. Submitters' own input problems
(unknown username, short password, mismatch) still return specific messages —
those describe the caller's own input, not a fact about another account, so they
help without enumerating. The verbatim-replay branch is unchanged: it requires the
exact username *and* password, so it discloses nothing the holder of the
credential does not already have.

---

## F-04 — Configured password validators are never invoked

**Vulnerability:** CWE-521 — weak password requirements
**Platform:** backend (both web and API)
**Severity:** Medium · **CVSS: 5.3**
**OWASP:** A07:2021 · API2:2023 Broken Authentication

`config/settings/base.py:138` configures four validators —
`UserAttributeSimilarityValidator`, `MinimumLengthValidator`,
`CommonPasswordValidator`, `NumericPasswordValidator` — but **nothing in the
codebase calls `password_validation.validate_password()`**. Verified: no
occurrence outside the settings file.

Both registration paths hand-roll a length check instead:

- `web/services.py:1003` — `if len(password) < 8:`
- `users/serializers.py:39` — `min_length=8`

So the configured controls are dead configuration, and the effective policy is
"8 characters, anything".

### Proof of Concept

```bash
DJANGO_SETTINGS_MODULE=config.settings.test \
  .venv-linux/bin/python manage.py test \
  web.test_security_poc.WebAuthControlsPoC.test_poc_04_web_registration_accepts_password_validators_reject
```

For each of `password1`, `12345678`, `qwerty123`, `letmein1` the test first
asserts `validate_password()` **raises** (proving the control exists and would
block it), then asserts `register_user()` **accepts** it.

**Expected:** rejected. **Actual:** all four accounts created.

### Impact

Accounts are created with passwords from the standard common-password lists —
the exact credentials that credential-stuffing lists contain first. Combined
with F-02, this is a direct account-takeover path.

### Remediation

**As implemented** — both paths call Django's validator, and each converts the
exception into its own framework's error shape:

```python
# web/services.py — register_user()
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import (
    ValidationError as DjangoValidationError,
)

try:
    validate_password(password, user=None)
except DjangoValidationError as exc:
    errors.extend(exc.messages)

# users/serializers.py — RegisterSerializer
def validate_password(self, value):
    try:
        validate_password(value)
    except DjangoValidationError as exc:
        raise serializers.ValidationError(list(exc.messages)) from exc
    return value
```

Two deviations from the sketch above, both deliberate:

- `user=None` / no user instance is passed. `UserAttributeSimilarityValidator`
  is then a no-op, which is correct here: no `User` row exists yet, and
  constructing an unsaved one with the submitted username/email would only
  compare the password against values the caller already supplied. The
  similarity check is a real control on *password change*, not on signup.
- The redundant `len(password) < 8` check was **kept** in `register_user`, not
  deleted. It is now unreachable in practice (the configured
  `MinimumLengthValidator` rejects anything shorter first) but it costs nothing
  and removing it would change the user-facing wording. DRF's `min_length=8` on
  the field is likewise left in place for the same reason.

Covered by `WebAuthControlsRegression.test_registration_runs_password_validators`
and `test_registration_accepts_strong_password` on the web, plus
`test_long_but_common_password_rejected` and `test_strong_password_accepted` on
the API. The pre-existing `test_weak_password_rejected` only covered a 5-char
password, which was already rejected by the length rule, so it proved nothing
about this finding; the new tests use ≥8-char passwords that the configured
`CommonPasswordValidator` rejects.

---

## F-05 — Anonymous scan logging is unmetered

**Vulnerability:** CWE-770 — allocation of resources without throttling
**Platform:** backend
**Severity:** Medium · **CVSS: 5.3** `AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:L`
**OWASP:** API4:2023

`web/services.py:356` writes a `Scan` row on **every** `GET /artifact/<slug>/`,
with no session required and no throttle. The API caps anonymous traffic at
`120/min`; the web app has no equivalent.

### Proof of Concept

```bash
DJANGO_SETTINGS_MODULE=config.settings.test \
  .venv-linux/bin/python manage.py test \
  web.test_security_poc.WebUnthrottledWritePoC
```

40 anonymous GETs.

**Expected:** throttled. **Actual:** 40 `Scan` rows, `user=None`.

### Impact

Unbounded table growth from a single unauthenticated loop — storage exhaustion
and a cheap way to make scan analytics meaningless. On Render's free tier
(SQLite or a small Postgres, no persistent disk) this is a realistic
availability concern.

### Remediation

Rate-limit `artifact_detail_view` on the anonymous budget, and/or collapse
repeat scans from the same IP within a short window instead of inserting a row
per hit. Reuse `config/client_ip.py` to derive a trustworthy IP for that
deduplication.

**As implemented:** the second option — window dedupe, not a hard rate limit.
`config/rate_limit.py:first_in_window(scope, identity, window)` returns True only
the first time an identity is seen inside the window, and `artifact_detail_data`
writes a scan only then:

```python
scan_identity = f'{artifact.pk}:{client_identifier(request)}'
if first_in_window('artifact_scan', scan_identity, settings.SCAN_DEDUPE_WINDOW_SECONDS):
    artifact.scans.create(...)
```

Notes on the choices:

- Dedupe is keyed on **artifact + viewer**, not a global cap, so a user browsing
  several artifacts still gets one row each. `WebScanDedupeRegression` pins both
  halves of that.
- The identity prefers the authenticated user and falls back to a trust-aware IP
  via `get_client_ip`, replacing the previous raw `REMOTE_ADDR` read — that was
  never a security bug, but it meant a reverse-proxied deployment recorded the
  proxy's address and could not dedupe at all. The `get_client_ip` call also
  fixes a latent crash: `ArtifactScan.ip_address` is nullable, so a `None` from
  a resolvable-IP-less request was fine, but the old code path and the new one
  now agree on where the address comes from.
- This is intentionally lossy: a genuine repeat view inside the window is folded
  into the earlier scan. That is the right trade for engagement analytics, where
  the question is "was this artifact viewed", not "how many HTTP requests
  arrived". The window is a new `SCAN_DEDUPE_WINDOW_SECONDS` setting (default
  3600s).

---

## F-06 — Quiz XP is farmable by unlimited retakes

**Vulnerability:** CWE-840 — business logic error
**Platform:** backend (both web and API)
**Severity:** Low · **CVSS: 4.3**
**OWASP:** A04:2021 Insecure Design

`start_quiz` (`web/services.py:612`) opens a fresh `IN_PROGRESS` attempt with
`get_or_create`, and `finish_quiz` (`:667`) pays `quiz.xp_reward` on every pass.
There is no cooldown, per-day cap, or diminishing return.

### Proof of Concept

```bash
DJANGO_SETTINGS_MODULE=config.settings.test \
  .venv-linux/bin/python manage.py test \
  web.test_security_poc.WebXpFarmingPoC
```

Five start → answer → finish cycles on one quiz.

**Evidence:**
```
after 1 take(s): total_xp= 100 quizzes_passed=1
after 2 take(s): total_xp= 200 quizzes_passed=2
after 3 take(s): total_xp= 300 quizzes_passed=3
after 4 take(s): total_xp= 400 quizzes_passed=4
after 5 take(s): total_xp= 500 quizzes_passed=5
```

**Not web-specific:** `gamification/views.py:157` (`QuizViewSet.finish`) has the
identical structure and pays via `streaks.grant_xp_and_stats`.

### Impact

Leaderboard ordering and every XP-gated badge are forgeable by a loop. No
financial or personal-data impact.

### Remediation

Award XP for a quiz only on a user's **first** pass, or apply a cooldown
between attempts, and move the award into shared code so both platforms agree.

**As implemented:** first-pass-only, in shared code. New
`gamification/services/quiz_xp.py` exposes `already_earned_quiz_xp(user, quiz,
exclude_attempt=None)`, called by both `web/services.finish_quiz` and
`QuizAttemptViewSet.finish`. A passing attempt that has already been paid sets
`xp_earned = 0` and skips the profile/stats update, then falls through to
`record_activity` so the streak still advances.

The guard is a **database** query, not a cache. XP is a durable ledger: a cache
expiry or eviction must never be able to re-open the payout, and a cache would
add a failure mode that pays twice under memory pressure. `exclude_attempt`
keeps the call correct even if it is ever evaluated after the attempt is saved.

This bounds the *reward*, not the activity — unlimited retakes are still allowed
and still counted as engagement (the test asserts 5 completed attempts survive).
What cannot happen is converting them into a second payout. XP-gated badges are
closed off as a side effect, since `xp_required` and `quizzes_passed_required`
are checked against the same profile fields.

**Bug found while fixing this:** the web `finish_quiz` badge sweep read
`profile.total_xp`, but `profile` was only bound inside the payout branch. Once
the payout became conditional, every *retake* would have raised
`UnboundLocalError` instead of completing quietly. `profile` is now resolved
before the branch, so the badge check runs on every passing attempt. Worth
noting that the pre-fix code had the same latent shape, masked only by the
payout being unconditional.

---

## Filtered candidates (investigated, not vulnerabilities)

Recorded so the next reviewer does not re-derive them.

**Open redirect via `next=/\evil.example` — NOT EXPLOITABLE.**
`web/actions.py:_safe_next` rejects `//` but not the WHATWG backslash form. It
is nevertheless safe: every action returns through `HttpResponseRedirect`,
which applies `iri_to_uri()`, percent-encoding the backslash to `%5C`. A URL
parser treats a literal `\` as a separator but does **not** re-interpret
`%5C` as one, so the browser resolves a same-site path. Observed:

```
next='/library/'                 -> Location='/library/'                  [same-site]
next='//evil.example'            -> Location='/story/p-1/'                [blocked]
next='/\evil.example'            -> Location='/%5Cevil.example'           [same-site]
next='https://evil.example/x'    -> Location='/story/p-1/'                [blocked]
next='javascript:alert(1)'       -> Location='/story/p-1/'                [blocked]
```

Pinned as a regression test (`WebOpenRedirectPoC`) so a move to a raw
`HttpResponse` cannot silently reintroduce it.

**Stored XSS in the markdown renderer — NOT EXPLOITABLE.**
`web/templatetags/web_extras.py:196` ends in `mark_safe`, but `_inline()`
escapes with `html.escape(quote=True)` *before* substituting, and its link
pattern only accepts `https?://`. Verified with an HTML-parsing allow-list test
over 10 payloads (script tags, `javascript:` URLs, attribute-breakout via
`"`, `<img onerror>`, `<svg onload>`, iframe): no unexpected tag, no event
handler, no non-http(s) `href`. Pinned as `WebPositiveControls`.

**Hardcoded secrets — NONE.** No credential-shaped strings in tracked backend
source; `SECRET_KEY` defaults to an obviously-fake dev value and
`config/settings/prod.py` refuses to boot on it. `backend/.env` is gitignored;
no `.jks`/`.keystore`/`key.properties`/`.pem` is tracked. `LUMA_API_KEY` and
`SENTRY_DSN` are environment-only.

**Sensitive data in logs — NONE.** `api/middleware.py` logs method, path,
status, duration, username and IP. It never logs the query string, request
body, cookies, or the `Authorization` header. The JWT username is read with
`AccessToken(...)`, which verifies the signature.

**SQL injection — NONE.** The only raw SQL in the project is
`api/views.py:64` (`cursor.execute('SELECT 1')`), a constant.

**Path traversal in media serving — NONE.** `config/urls.py` registers
`django.views.static.serve` explicitly for production, but `serve()` resolves
through `safe_join`, which raises on traversal. `MEDIA_ROOT` is `BASE_DIR/media`
— not `BASE_DIR` — so `db.sqlite3` is not reachable at `/media/…`, and no
credential or config file exists under the served tree.

**Self-assigned admin role — BLOCKED.** `register` accepts `role` from POST,
but `register_user` whitelists it to `('visitor', 'contributor')` before use.
Verified: posting `role=admin` yields a `visitor`.

**Email squatting via profile update — BLOCKED.** `update_profile`
(`web/services.py:958`) rejects an email already held by another account.

---

## Verified controls (positive results)

Each is now pinned by a test in `WebPositiveControls` or the PoC classes, so a
regression turns the suite red:

| Control | Result |
| --- | --- |
| CSRF on every web action | 403 without a token (required `Client(enforce_csrf_checks=True)`; the default test client silently exempts requests) |
| BOLA — edit another user's story | blocked |
| BOLA — delete another user's story | blocked |
| Privilege escalation via self-registration | blocked (role whitelisted) |
| Story/audio/video ownership checks in `web/services.py` | correct |
| Markdown renderer XSS | safe (tag + attribute allow-list) |
| `prod.py` transport hardening | `SSL_REDIRECT`, HSTS 1y + preload + subdomains, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `SECURE_REFERRER_POLICY` all set |
| CORS | allow-all is `dev.py` only; prod uses an explicit origin list; `CORS_ALLOW_CREDENTIALS` never enabled (defaults False) |
| `IntegrityError` handling | field name only, never the driver message |
| Dependency CVEs | 1 known: `click 8.1.8` PYSEC-2026-2132 (fix 8.3.3), unreachable via `gTTS<8.2` and confined to `click.edit`, which is never called |

## Non-security observations

- ~~`web/auth.py:login_redirect_url` returns `?next=` unvalidated. **Dead code** —
  no caller.~~ **Fixed:** confirmed to have no caller anywhere in the tree and
  deleted, so the unvalidated `?next=` reader is gone. `WebLoginView` uses
  Django's validated `get_redirect_url`.
- ~~`templates/web/admin_dashboard.html:91` renders `{{ growth_html|safe }}`, but
  no view ever sets `growth_html`. Dead reference.~~ **Correction — this note
  was wrong.** `growth_html` is the *return value* of the `growth_bars` template
  tag on the line above it; it is live, admin-facing code, not a dead reference.
  It was inspected and left alone: `growth_bars` builds every bar with
  `format_html` and coerces the value with `int(...)`, so the `|safe` is not a
  landmine and removing it would delete a working chart.
- `actions.story_video_status` lacks `@require_POST` (read-only JSON poll, so
  harmless) while its 20 siblings have it. Add for consistency. **Not changed** —
  out of scope for a security fix and it would alter a working poll endpoint.
- ~~`web` records `request.META.get('REMOTE_ADDR')` directly for scans and
  shares.~~ **Fixed as part of F-05:** scan recording now uses the trust-aware
  `config/client_ip.get_client_ip()`, so a reverse-proxied deployment records the
  real client address rather than the proxy's.
- `register` allows an unverified email change with no confirmation step. Not
  exploitable today because there is no password-reset flow; it becomes an
  account-takeover path the moment one is added. Add verification before that.
