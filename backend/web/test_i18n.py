"""
Phase 5 Track A — the interface actually speaks French.

The defect this file exists for is not a bug that throws. It is that
`USE_I18N = True` was set, `LANGUAGES` existed, and **`LocaleMiddleware` was
never in `MIDDLEWARE`**, so no request ever had a language and every string on
every page stayed English no matter what a reader asked for. A test suite that
only renders pages in the default language cannot see that; it renders the
English page perfectly. So these tests all assert the same thing from different
angles: switch the language, then prove the output changed.

Run with:

    DJANGO_SETTINGS_MODULE=config.settings.test python manage.py test web.test_i18n
"""

import re
from pathlib import Path

from django.conf import settings
from django.template.base import Lexer, TokenType
from django.test import SimpleTestCase, TestCase
from django.urls import reverse
from django.utils import translation

from stories.models import Story
from users.models import User

from .models import WebUserSettings
from .services import DEFAULT_UI_LANGUAGE, resolve_ui_language


class TemplateSyntaxTests(SimpleTestCase):
    """Every tag in every template is actually parsed as a tag.

    Wrapping this many literals in `{% trans %}` is exactly the kind of edit
    that introduces a mistyped terminator — `%}` written as `%>` or `}}`. Django
    does not complain: it emits the malformed construct as literal text, so the
    page still renders and still looks right, and the one tag that stopped
    working is a `{% url %}` whose form posts nowhere. Both of those shipped
    during this phase and were only caught by walking the token stream.

    The same walk finds multi-line `{# … #}` comments, which Django's own
    lexer does not match across newlines and which were therefore being
    rendered into the HTML source of the home page and the story page.
    """

    def test_no_template_emits_an_unparsed_tag(self):
        offenders = []
        for path in sorted(Path(settings.BASE_DIR / 'templates').rglob('*.html')):
            source = path.read_text(encoding='utf-8')
            for token in Lexer(source).tokenize():
                if token.token_type is not TokenType.TEXT:
                    continue
                if any(
                    marker in token.contents for marker in ('{%', '{{', '{#')
                ):
                    offenders.append(
                        f'{path.relative_to(settings.BASE_DIR)}:{token.lineno}: '
                        f'{token.contents.strip()[:80]!r}',
                    )
        self.assertEqual(
            offenders, [], 'template tags rendered as literal text:\n'
            + '\n'.join(offenders),
        )


class LocaleMiddlewareInstalledTests(TestCase):
    """The precondition. Everything else in this file is downstream of it."""

    def test_locale_middleware_is_in_the_stack(self):
        self.assertIn(
            'django.middleware.locale.LocaleMiddleware', settings.MIDDLEWARE,
        )

    def test_locale_middleware_runs_after_the_session(self):
        """It reads the chosen language from the session, so order is not free.

        Ahead of SessionMiddleware the session does not exist yet and the
        switch silently stops surviving a page load.
        """
        middleware = settings.MIDDLEWARE
        self.assertLess(
            middleware.index('django.contrib.sessions.middleware.SessionMiddleware'),
            middleware.index('django.middleware.locale.LocaleMiddleware'),
        )

    def test_default_language_is_in_the_language_list(self):
        """`LANGUAGE_CODE` is the fallback; a default outside `LANGUAGES` means
        every lookup falls back one step before it starts."""
        self.assertIn(settings.LANGUAGE_CODE, dict(settings.LANGUAGES))


class StoredPreferenceReachesANewBrowserTests(TestCase):
    """The account preference exists to follow the reader between devices.

    `WebUserSettings.language` had a docstring saying exactly that and no code
    reading it back, so the column was written by nothing and read by nothing.
    """

    def setUp(self):
        self.user = User.objects.create_user(
            username='returning_reader', password='pw12345678',
        )
        self.url = reverse('web:set-language')

    def test_a_new_browser_inherits_the_stored_language(self):
        self.client.force_login(self.user)
        self.client.post(self.url, {'language': 'fr'})

        # A second browser: same account, no language cookie at all.
        del self.client.cookies[settings.LANGUAGE_COOKIE_NAME]
        body = self.client.get(reverse('web:home')).content.decode()

        self.assertIn('Bibliothèque', body)

    def test_an_explicit_choice_on_this_device_is_not_overridden(self):
        WebUserSettings.objects.create(user=self.user, language='fr')
        self.client.force_login(self.user)
        self.client.cookies[settings.LANGUAGE_COOKIE_NAME] = 'en'

        body = self.client.get(reverse('web:home')).content.decode()

        self.assertIn('Library', body)
        self.assertNotIn('Bibliothèque', body)

    def test_an_unrenderable_stored_language_falls_back(self):
        """A row written by an older build could hold a code with no
        catalogue; activating it would serve an English page under a
        language option that promises otherwise."""
        WebUserSettings.objects.create(user=self.user, language='ewo')
        self.client.force_login(self.user)

        self.client.get(reverse('web:home'))

        self.assertEqual(
            self.client.cookies[settings.LANGUAGE_COOKIE_NAME].value, 'en',
        )


class ResolveUiLanguageTests(TestCase):
    """One definition of "a language this interface has"."""

    def test_known_code_is_kept(self):
        self.assertEqual(resolve_ui_language('fr'), 'fr')

    def test_unknown_code_falls_back_to_english(self):
        self.assertEqual(resolve_ui_language('ewo'), DEFAULT_UI_LANGUAGE)

    def test_story_language_codes_are_not_interface_languages(self):
        """The bug this guards against.

        `set_language` used to validate against `Story.Language.choices`, so a
        request could write `ful` — a language a story can be *written in* —
        into a column whose own choices are en/fr. No catalogue exists for it,
        so the switch would have offered a language that renders in English.
        """
        story_codes = {code for code, _ in Story.Language.choices}
        interface_codes = {code for code, _ in settings.LANGUAGES}
        self.assertTrue(story_codes - interface_codes)
        for code in story_codes - interface_codes:
            self.assertEqual(resolve_ui_language(code), DEFAULT_UI_LANGUAGE)


class LanguageSwitchTests(TestCase):
    """The switch, from both sides of the login boundary."""

    def setUp(self):
        self.url = reverse('web:set-language')

    def test_a_signed_out_reader_can_switch(self):
        """French is the language of administration and schooling.

        The reader who most needs this page in French is the one with no
        account yet, so the endpoint is deliberately not `@login_required`.
        """
        response = self.client.post(self.url, {'language': 'fr'})

        self.assertEqual(response.status_code, 302)
        self.assertEqual(
            response.cookies[settings.LANGUAGE_COOKIE_NAME].value, 'fr',
        )

    def test_switching_redirects_back_to_the_page_you_were_on(self):
        response = self.client.post(
            self.url, {'language': 'fr', 'next': '/stories/?sort=-view_count'},
        )

        self.assertEqual(response['Location'], '/stories/?sort=-view_count')

    def test_next_cannot_leave_the_site(self):
        """Same rule as every other `next` in this app — no open redirect."""
        response = self.client.post(
            self.url, {'language': 'fr', 'next': 'https://evil.example/'},
        )

        self.assertEqual(response['Location'], reverse('web:home'))

    def test_a_signed_in_readers_choice_is_stored_on_their_account(self):
        user = User.objects.create_user(username='fr_reader', password='pw12345678')

        self.client.force_login(user)
        self.client.post(self.url, {'language': 'fr'})

        self.assertEqual(
            WebUserSettings.objects.get(user=user).language, 'fr',
        )

    def test_an_unsupported_code_is_not_persisted(self):
        """The endpoint must not write a value it cannot render."""
        user = User.objects.create_user(username='ewo_reader', password='pw12345678')

        self.client.force_login(user)
        self.client.post(self.url, {'language': 'ewo'})

        self.assertEqual(
            WebUserSettings.objects.get(user=user).language, DEFAULT_UI_LANGUAGE,
        )


class FrenchReachesThePageTests(TestCase):
    """The point of the whole exercise: the bytes on the page change."""

    @classmethod
    def setUpTestData(cls):
        cls.user = User.objects.create_user(
            username='francophone', password='pw12345678', role='contributor',
        )
        cls.story = Story.objects.create(
            title='The Baobab and the Drum',
            content='Once upon a time.',
            summary='A tale about rhythm.',
            author=cls.user,
            status=Story.Status.PUBLISHED,
        )

    def setUp(self):
        self.client.force_login(self.user)

    def test_html_lang_attribute_follows_the_active_language(self):
        """`<html lang>` decides screen-reader pronunciation and browser
        hyphenation, so it has to be the language actually rendered."""
        response = self.client.get(reverse('web:home'))

        self.assertIn('<html lang="en">', response.content.decode())

        self.client.post(reverse('web:set-language'), {'language': 'fr'})
        response = self.client.get(reverse('web:home'))

        self.assertIn('<html lang="fr">', response.content.decode())

    def test_navigation_is_translated(self):
        self.client.post(reverse('web:set-language'), {'language': 'fr'})
        body = self.client.get(reverse('web:home')).content.decode()

        self.assertIn('Bibliothèque', body)
        self.assertIn('Récits', body)

    def test_the_story_page_is_translated(self):
        self.client.post(reverse('web:set-language'), {'language': 'fr'})
        body = self.client.get(
            reverse('web:story-detail', args=[self.story.slug]),
        ).content.decode()

        self.assertIn('Signaler ce récit', body)
        self.assertIn('Langue', body)

    def test_the_english_page_still_looks_english(self):
        """A translation table that leaked into the default language would be
        a worse bug than no French at all."""
        body = self.client.get(reverse('web:home')).content.decode()

        self.assertIn('Library', body)
        self.assertNotIn('Bibliothèque', body)

    def test_enum_labels_are_translated_where_they_are_displayed(self):
        """`get_status_display` is what the library pill and the moderation
        queue render. Consent and licence labels were English-only, so a
        moderator recording a consent decision read them in English on an
        otherwise French page."""
        with translation.override('fr'):
            self.assertEqual(
                str(self.story.get_status_display()), 'Publié',
            )
            self.assertEqual(
                str(Story.Consent.GRANTED.label), 'Consentement accordé',
            )
            self.assertEqual(
                str(Story.Licence.PUBLIC_DOMAIN.label), 'Domaine public',
            )

    def test_language_names_are_not_translated(self):
        """`Story.Language` values are proper nouns in every language."""
        with translation.override('fr'):
            self.assertEqual(str(Story.Language.EWONDO.label), 'Ewondo')

    def test_plural_forms_use_french_agreement(self):
        """French keeps the singular for zero ("0 récit"), which the `n > 1`
        plural rule gives for free — and only if the catalogue carries both
        forms."""
        with translation.override('fr'):
            one = translation.ngettext('%(counter)s story', '%(counter)s stories', 1)
            many = translation.ngettext('%(counter)s story', '%(counter)s stories', 4)

        self.assertEqual(one, '%(counter)s récit')
        self.assertEqual(many, '%(counter)s récits')

    def test_the_switcher_is_offered_to_signed_out_readers(self):
        self.client.logout()
        body = self.client.get(reverse('web:home')).content.decode()

        self.assertIn(reverse('web:set-language'), body)


class CatalogueTests(TestCase):
    """The invariant behind every language this project can offer."""

    def test_every_offered_language_has_a_compiled_catalogue(self):
        """`LANGUAGES` is the promise the switch makes.

        A code listed here with no `.mo` behind it renders every string in
        English while looking like a language option — the exact defect
        Phase 5 was opened to close, and the one the Flutter app already had
        with `supportedLocales: [en, fr]` and no strings.
        """
        from django.utils.translation import trans_real

        available = trans_real.get_languages()
        for code, _name in settings.LANGUAGES:
            if code == settings.LANGUAGE_CODE:
                # The source language is its own catalogue: the msgid *is*
                # the English string, so a `.po` for it would only be able to
                # say the same thing twice. This is why `makemessages -l en`
                # is not part of the documented workflow.
                continue
            compiled = Path(settings.LOCALE_PATHS[0]) / code / 'LC_MESSAGES' / 'django.mo'
            self.assertTrue(
                compiled.exists(),
                f'{code} is in LANGUAGES but {compiled} does not exist — '
                'run `manage.py compilemessages`',
            )
            self.assertIn(code, available)

    def test_the_french_catalogue_has_no_untranslated_entries(self):
        """Silent gaps are how a "translated" page stays half English.

        The `.mo` is compiled and committed precisely so this can be asserted
        from a clean checkout; a msgid added without a translation would
        otherwise only show up as a stray English word on a French page.
        """
        from django.utils.translation import trans_real

        catalogue = trans_real.translation('fr')
        # Every non-empty msgid extracted from the project's own source must
        # have a translation. Django's own strings are compiled in too, so
        # this reads the project's catalogue rather than the merged one.
        po_path = settings.LOCALE_PATHS[0] / 'fr' / 'LC_MESSAGES' / 'django.po'
        content = po_path.read_text(encoding='utf-8')

        missing = []
        for block in content.split('\n\n'):
            match = re.search(
                r'^msgid ((?:"(?:[^"\\]|\\.)*"\s*)+)', block, re.M,
            )
            if not match:
                continue
            msgid = ''.join(re.findall(
                r'"((?:[^"\\]|\\.)*)"', match.group(1),
            ))
            if not msgid:
                continue
            plural = 'msgid_plural' in block
            forms = re.findall(
                r'^msgstr(?:\[\d+\])? ((?:"(?:[^"\\]|\\.)*"\s*)+)',
                block, re.M,
            )
            values = [''.join(re.findall(r'"((?:[^"\\]|\\.)*)"', f)) for f in forms]
            expected = 2 if plural else 1
            if len(values) != expected or any(not v for v in values):
                missing.append(msgid)

        self.assertEqual(
            missing, [],
            f'{len(missing)} untranslated French strings; run '
            'scripts/translate_fr.py or add them by hand',
        )
        # A guard on the guard: an empty or unmerged catalogue would make this
        # vacuous, so assert the compiled French really carries our strings.
        self.assertEqual(catalogue.gettext('Sign in'), 'Se connecter')