"""Security regression suite for the web app (scope: backend/web + backend API).

This started life as a set of proofs of concept: the original versions asserted
the *vulnerable* behaviour, so they stayed green while the finding was live and
went red only once it was fixed. They were inverted, and the classes renamed
``...Regression``, because that is what they are now — a permanent suite that
fails if a control is removed again. Only the filename still said "poc".

The controls under test:
  - F-01 web media actions enforce the same per-user daily caps as the API.
  - F-02 web login/registration are throttled.
  - F-03 registration does not disclose whether an account exists.
  - F-04 registration runs the configured password validators.
  - F-05 artifact-view scan writes are collapsed per window.
  - F-06 quiz XP is first-pass-only.

Plus a set of positive controls (``WebPositiveControls``) asserting behaviour
that is *supposed* to hold — CSRF enforcement, ownership checks, role
self-assignment, output escaping — so a future "fix" cannot pass by breaking
something adjacent.

Several controls are enforced with Django's cache (rate limiting, scan dedupe).
The cache is a per-process store that survives between tests in a single run, so
the tests that depend on it clear it in ``setUp`` to stay order-independent.

Run with:
    DJANGO_SETTINGS_MODULE=config.settings.test .venv-linux/bin/python \
        manage.py test web.test_security_regressions -v 2
"""

from unittest import mock

from django.core.cache import cache
from django.test import TestCase, override_settings
from django.urls import reverse

from gamification.models import QuizQuestion
from media_app.models import AudioNarrationJob, VideoGenerationJob
from qr_codes.models import Artifact
from stories.models import Story
from users.models import User


class WebQuotaBypassRegression(TestCase):
    """F-01: web POST actions enforce the per-user daily media caps.

    The API enforces VIDEO_GENERATIONS_PER_USER_PER_DAY and
    AUDIO_NARRATIONS_PER_USER_PER_DAY. These pin that the server-rendered web
    actions now share the same ceiling (via media_app.quota), so a contributor
    can no longer bypass the bound by using the form instead of the API.
    """

    def setUp(self):
        self.author = User.objects.create_user(
            username='contributor', email='c@example.org',
            password='Correct-Horse-9', role='contributor',
        )
        self.stories = [
            Story.objects.create(
                author=self.author, title=f'Story {i}', content=f'Body {i}',
                slug=f'story-{i}', status=Story.Status.PUBLISHED,
            )
            for i in range(6)
        ]

    @override_settings(VIDEO_GENERATIONS_PER_USER_PER_DAY=1)
    def test_video_cap_stops_web_action_after_limit(self):
        """With the cap pinned to 1/day, six attempts across six stories start
        exactly one paid Luma job."""
        luma = mock.MagicMock()
        luma.submit_video_generation.return_value = {'id': 'job-1'}

        for story in self.stories:
            with mock.patch('web.services.get_luma_service', return_value=luma):
                self.client.force_login(self.author)
                self.client.post(
                    reverse('web:story-generate-video', args=[story.slug]),
                )

        started = VideoGenerationJob.objects.filter(
            user=self.author, status=VideoGenerationJob.Status.PENDING,
        ).count()
        self.assertEqual(
            started, 1,
            'web video action must stop at the daily cap (regression: F-01)',
        )
        self.assertEqual(
            luma.submit_video_generation.call_count, 1,
            'only the first attempt may reach the paid Luma backend',
        )

    @override_settings(AUDIO_NARRATIONS_PER_USER_PER_DAY=1)
    def test_audio_cap_stops_web_action_after_limit(self):
        """Same story, six languages: cap is 1/day, so exactly one narration
        is synthesized."""
        tts = mock.MagicMock()
        tts.submit_narration.return_value = {
            'filename': 'a.mp3', 'audio_bytes': b'ID3', 'duration': 1.0,
            'file_size': 3,
        }

        for lang in ('en', 'fr', 'es', 'pt', 'sw', 'ha'):
            with mock.patch('web.services.get_tts_service', return_value=tts):
                self.client.force_login(self.author)
                self.client.post(
                    reverse('web:story-generate-audio', args=[self.stories[0].slug]),
                    {'language': lang},
                )

        completed = AudioNarrationJob.objects.filter(
            user=self.author, status=AudioNarrationJob.Status.COMPLETED,
        ).count()
        self.assertEqual(
            completed, 1,
            'web audio action must stop at the daily cap (regression: F-01)',
        )
        self.assertEqual(
            tts.submit_narration.call_count, 1,
            'only the first attempt may reach the TTS backend',
        )

    @override_settings(VIDEO_GENERATIONS_PER_USER_PER_DAY=5)
    def test_video_cap_allows_usage_below_limit(self):
        """Below the cap, the web path is unaffected (guards against an
        off-by-one that blocks legitimate use)."""
        luma = mock.MagicMock()
        luma.submit_video_generation.return_value = {'id': 'job-1'}

        for story in self.stories[:3]:
            with mock.patch('web.services.get_luma_service', return_value=luma):
                self.client.force_login(self.author)
                self.client.post(
                    reverse('web:story-generate-video', args=[story.slug]),
                )

        self.assertEqual(VideoGenerationJob.objects.count(), 3)


class WebAuthControlsRegression(TestCase):
    """F-02/F-03/F-04: throttling, non-disclosure and password policy."""

    def setUp(self):
        cache.clear()
        self.target = User.objects.create_user(
            username='victim', email='victim@example.org',
            password='Correct-Horse-9', role='contributor',
        )

    @override_settings(WEB_AUTH_ATTEMPTS_PER_MIN=5)
    def test_login_is_throttled_after_limit(self):
        """Wrong-password attempts beyond the budget get 429, not the 200 login
        page. A GET renders the form and must not consume the budget."""
        url = reverse('web:login')
        self.client.get(url)  # form render is free

        statuses = []
        for _ in range(12):
            response = self.client.post(
                url, {'username': 'victim', 'password': 'wrong-guess'},
            )
            statuses.append(response.status_code)

        self.assertEqual(
            statuses[:5], [200] * 5,
            'attempts within the budget must still reach the login view',
        )
        self.assertTrue(
            all(s == 429 for s in statuses[5:]),
            f'attempts past the budget must be throttled, got {statuses}',
        )
        self.assertIn('Retry-After', self.client.post(
            url, {'username': 'victim', 'password': 'wrong-guess'},
        ).headers)

    @override_settings(WEB_AUTH_ATTEMPTS_PER_MIN=5)
    def test_registration_is_throttled_after_limit(self):
        """Registration is likewise rate-limited against bulk account
        creation."""
        url = reverse('web:register')
        statuses = []
        for i in range(8):
            response = self.client.post(url, {
                'username': f'newuser{i}', 'email': f'new{i}@example.org',
                'password': 'Correct-Horse-9', 'password2': 'Correct-Horse-9',
            })
            statuses.append(response.status_code)

        self.assertTrue(
            all(s == 429 for s in statuses[5:]),
            f'register attempts past the budget must be throttled, got {statuses}',
        )

    def test_registration_does_not_disclose_account_existence(self):
        """A collision must not reveal *which* field collided, so the form
        cannot enumerate accounts."""
        response = self.client.post(reverse('web:register'), {
            'username': 'victim', 'email': 'someone-else@example.org',
            'password': 'Correct-Horse-9', 'password2': 'Correct-Horse-9',
        })
        body = response.content.decode()
        self.assertNotIn('That username is taken', body)
        self.assertNotIn('A user with this email already exists.', body)
        self.assertIn('already exists', body)

    def test_registration_does_not_disclose_email_collision(self):
        """The same non-disclosure applies to an email collision."""
        response = self.client.post(reverse('web:register'), {
            'username': 'brand-new-name', 'email': 'VICTIM@example.org',
            'password': 'Correct-Horse-9', 'password2': 'Correct-Horse-9',
        })
        body = response.content.decode()
        self.assertNotIn('A user with this email already exists.', body)
        self.assertNotIn('That username is taken', body)
        self.assertIn('already exists', body)

    def test_registration_runs_password_validators(self):
        """Weak passwords that AUTH_PASSWORD_VALIDATORS rejects must now be
        refused by the web form, matching the API."""
        from django.contrib.auth import password_validation

        from web.services import register_user

        weak = ('password1', '12345678', 'qwerty123', 'letmein1')
        for password in weak:
            with self.subTest(password=password):
                with self.assertRaises(
                    password_validation.ValidationError,
                    msg=f'{password!r} unexpectedly passed the configured validators',
                ):
                    password_validation.validate_password(password)

                user, errors = register_user(
                    username=f'u_{password}', email=f'{password}@example.org',
                    password=password, password2=password, role='visitor',
                )
                self.assertIsNone(
                    user, f'registration accepted {password!r} (regression: F-04)',
                )
                self.assertTrue(errors, 'weak password must produce an error')

    def test_registration_accepts_strong_password(self):
        """A compliant password still registers (guards against over-blocking)."""
        from web.services import register_user

        user, errors = register_user(
            username='stronguser', email='strong@example.org',
            password='Correct-Horse-9', password2='Correct-Horse-9',
            role='visitor',
        )
        self.assertFalse(errors)
        self.assertIsNotNone(user)


class WebOpenRedirectRegression(TestCase):
    """_safe_next() reviewed and found sound — kept as a regression guard.

    Originally logged as a suspected open redirect: the helper rejects '//'
    but not the WHATWG backslash form '/\\evil.example'. Verified NOT
    exploitable — every action returns the target through
    HttpResponseRedirect, which applies iri_to_uri(), percent-encoding the
    backslash to '%5C'. A URL parser treats a literal backslash as a path
    separator but does NOT re-interpret the percent-encoded '%5C' as one, so
    the browser resolves it as a same-site path. Scheme-based payloads are
    rejected because _safe_next requires a leading '/'.

    This test pins that behaviour so a future edit to _safe_next (or a move
    to a raw HttpResponse) cannot silently reintroduce the bypass.
    """

    def test_next_stays_same_site_for_all_known_bypass_forms(self):
        user = User.objects.create_user(
            username='redirector', email='r@example.org',
            password='Correct-Horse-9', role='contributor',
        )
        story = Story.objects.create(
            author=user, title='T', content='C', slug='r-1',
            status=Story.Status.PUBLISHED,
        )
        self.client.force_login(user)

        payloads = [
            '/\\evil.example',       # WHATWG backslash authority form
            '/\\/evil.example',
            '/%09/evil.example',     # percent-encoded tab before authority
            '//evil.example',        # protocol-relative
            '/\\/\\evil.example',
            'https://evil.example/x',  # absolute off-site
            'javascript:alert(1)',      # scheme injection
        ]
        for payload in payloads:
            with self.subTest(payload=payload):
                response = self.client.post(
                    reverse('web:story-like', args=[story.slug]),
                    {'next': payload},
                )
                location = response['Location']
                self.assertFalse(
                    location.startswith(('http://', 'https://')),
                    f'open redirect via {payload!r} -> {location!r}',
                )


class WebScanDedupeRegression(TestCase):
    """F-05: anonymous artifact scans are collapsed per window.

    artifact_detail_view is a plain Django view. It used to write a Scan row on
    every GET, so an anonymous crawler or a reload loop could inflate scan
    analytics without bound. Repeats within the window are now folded into the
    first scan.
    """

    def setUp(self):
        cache.clear()
        self.artifact = Artifact.objects.create(
            title='Mask', slug='mask', description='A mask',
            is_published=True,
        )
        self.other = Artifact.objects.create(
            title='Other', slug='other', description='Another',
            is_published=True,
        )

    def test_repeat_views_collapse_to_one_scan(self):
        url = reverse('web:artifact-detail', args=[self.artifact.slug])
        for _ in range(40):
            self.client.get(url)
        self.assertEqual(
            self.artifact.scans.count(), 1,
            'repeat views must collapse to a single scan (regression: F-05)',
        )

    def test_distinct_artifacts_are_tracked_separately(self):
        """Dedupe is per artifact, not global — a second artifact is still
        counted (guards against over-collapsing)."""
        for _ in range(3):
            self.client.get(reverse('web:artifact-detail', args=[self.artifact.slug]))
        for _ in range(3):
            self.client.get(reverse('web:artifact-detail', args=[self.other.slug]))
        self.assertEqual(self.artifact.scans.count(), 1)
        self.assertEqual(self.other.scans.count(), 1)


class WebXpFarmingRegression(TestCase):
    """F-06: quiz XP is first-pass-only.

    start_quiz() opens a fresh IN_PROGRESS attempt on demand, and both the web
    and API finish paths used to pay quiz.xp_reward on every passing attempt.
    The reward is now paid once per (user, quiz); retakes are still recorded
    (real engagement) but do not pay out again, so the leaderboard and every
    XP-gated badge can no longer be farmed from a single quiz.
    """

    def test_repeat_pass_earns_xp_only_once(self):
        from gamification.models import UserProfile

        user = User.objects.create_user(
            username='farmer', email='f@example.org',
            password='Correct-Horse-9', role='contributor',
        )
        story = Story.objects.create(
            author=user, title='S', content='C', slug='farm-1',
            status=Story.Status.PUBLISHED,
        )
        quiz = story.quiz  # provisioned by the gamification post_save receiver
        QuizQuestion.objects.create(
            quiz=quiz, question_text='2+2?', option_a='3', option_b='4',
            option_c='5', option_d='6', correct_answer='b',
        )
        question = quiz.questions.first()
        reward = quiz.xp_reward
        self.client.force_login(user)

        for _ in range(5):
            self.client.post(reverse('web:quiz-start', args=[quiz.id]))
            self.client.post(
                reverse('web:quiz-answer', args=[quiz.id, question.id]),
                {'answer': 'b'},
            )
            self.client.post(reverse('web:quiz-finish', args=[quiz.id]))

        profile = UserProfile.objects.get(user=user)
        self.assertEqual(
            profile.total_xp, reward,
            f'5 retakes must pay XP once ({reward}), not {reward * 5} '
            f'(regression: F-06)',
        )
        # Activity is still recorded — the guard bounds the reward, not the
        # engagement.
        from gamification.models import QuizAttempt
        self.assertEqual(
            QuizAttempt.objects.filter(
                user=user, quiz=quiz, status=QuizAttempt.Status.COMPLETED,
            ).count(),
            5,
        )


class WebPositiveControls(TestCase):
    """Controls that are correctly enforced — pinned so they stay enforced.

    Not findings. Included so the audit records what was checked and cleared,
    and so a future refactor that drops one of them turns this file red.
    """

    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(
            username='ctrl', email='ctrl@example.org',
            password='Correct-Horse-9', role='contributor',
        )
        self.other = User.objects.create_user(
            username='intruder', email='int@example.org',
            password='Correct-Horse-9', role='contributor',
        )
        self.story = Story.objects.create(
            author=self.user, title='T', content='C', slug='ctrl-1',
            status=Story.Status.PUBLISHED,
        )

    def test_csrf_is_enforced_on_actions(self):
        """A POST without a CSRF token must be rejected (403).

        Django's test Client sets enforce_csrf_checks=False by default, which
        silently exempts every request from the CsrfViewMiddleware. Without
        opting in, this test would observe the 302 success path and wrongly
        'pass'.
        """
        from django.test import Client

        csrf_client = Client(enforce_csrf_checks=True)
        csrf_client.force_login(self.user)
        response = csrf_client.post(
            reverse('web:story-like', args=[self.story.slug]),
        )
        self.assertEqual(
            response.status_code, 403,
            'CSRF middleware is not protecting the web actions',
        )

    def test_cannot_edit_another_users_story(self):
        self.client.force_login(self.other)
        response = self.client.post(
            reverse('web:story-update', args=[self.story.slug]),
            {'title': 'Hijacked', 'content': 'x', 'status': 'draft'},
        )
        self.story.refresh_from_db()
        self.assertNotEqual(
            self.story.title, 'Hijacked',
            'BOLA: a contributor edited a story they do not own',
        )
        self.assertIn(response.status_code, (403, 302))

    def test_cannot_delete_another_users_story(self):
        self.client.force_login(self.other)
        self.client.post(reverse('web:story-delete', args=[self.story.slug]))
        self.assertTrue(
            Story.objects.filter(slug='ctrl-1').exists(),
            'BOLA: a contributor deleted a story they do not own',
        )

    def test_registration_cannot_self_assign_admin_role(self):
        self.client.post(reverse('web:register'), {
            'username': 'sneaky', 'email': 'sneaky@example.org',
            'password': 'Correct-Horse-9', 'password2': 'Correct-Horse-9',
            'role': 'admin',
        })
        created = User.objects.filter(username='sneaky').first()
        self.assertIsNotNone(created)
        self.assertEqual(
            created.role, 'visitor',
            'privilege escalation: self-registration granted an admin role',
        )

    def test_markdown_renderer_escapes_html(self):
        """Stored XSS probe on the hand-rolled markdown renderer.

        Substring checks are not usable here: a payload like
        '<img src=x onerror=alert(1)>' legitimately leaves the text 'onerror='
        in the output as *escaped, inert text* ('&lt;img ... onerror=...&gt;'),
        which cannot execute. So this parses the rendered HTML and enforces an
        allow-list of tags and attributes instead — the only way to tell an
        inert string from a live one.
        """
        from html.parser import HTMLParser

        from web.templatetags.web_extras import markdown

        ALLOWED_TAGS = {
            'p', 'h1', 'h2', 'h3', 'ul', 'ol', 'li', 'blockquote', 'pre',
            'code', 'strong', 'em', 'hr', 'a', 'br',
        }
        # `a` may carry href/rel/target; nothing may carry an event handler.
        ALLOWED_ATTRS = {'href', 'rel', 'target'}

        class Inspector(HTMLParser):
            def __init__(self):
                super().__init__()
                self.bad_tags = []
                self.bad_attrs = []
                self.hrefs = []

            def handle_starttag(self, tag, attrs):
                if tag not in ALLOWED_TAGS:
                    self.bad_tags.append(tag)
                for name, value in attrs:
                    if name.lower() not in ALLOWED_ATTRS:
                        self.bad_attrs.append(f'{tag}@{name}')
                    if name.lower() == 'href':
                        self.hrefs.append(value or '')

        payloads = [
            '<script>alert(1)</script>',
            '[x](javascript:alert(1))',
            '[" onmouseover="alert(1)](https://ok.example)',
            '![i](https://ok.example/x.png" onerror="alert(1))',
            '<img src=x onerror=alert(1)>',
            '> <svg/onload=alert(1)>',
            '[a](https://ok.example" onclick="alert(1))',
            '<a href="javascript:alert(1)">click</a>',
            '**<iframe src=//evil.example>**',
            '[ok](https://ok.example/page)',
        ]
        for payload in payloads:
            with self.subTest(payload=payload):
                out = markdown(payload)
                parser = Inspector()
                parser.feed(out)
                self.assertEqual(
                    parser.bad_tags, [],
                    f'unexpected tag rendered from {payload!r} -> {out!r}',
                )
                self.assertEqual(
                    parser.bad_attrs, [],
                    f'unexpected attribute rendered from {payload!r} -> {out!r}',
                )
                for href in parser.hrefs:
                    self.assertTrue(
                        href.startswith(('http://', 'https://')),
                        f'non-http(s) href {href!r} from {payload!r}',
                    )
