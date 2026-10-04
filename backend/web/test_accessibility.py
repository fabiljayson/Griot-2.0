"""
Accessibility scaffolding that every web page was missing.

None of the defects in this file are visible in a rendered page. The layout
looks right, the colours look deliberate, nothing throws. Each one costs
something to a specific person and only shows up when you go looking:

- **No skip link.** The desktop layout puts a 260px navigation column before
  the first piece of content and the header puts a row of links above that.
  A keyboard user had to tab through the entire navigation on every page, on
  every page load, to reach the content they came for.
- **No `<meta name="description">` and no Open Graph tags.** Search engines and
  social platforms invent their own snippet, so a shared story link renders as
  a bare URL.
- **No `prefers-reduced-motion` support anywhere.** Not one rule in the app's
  own CSS or templates. (The vendored Font Awesome stylesheet has one, which is
  why a naive grep looks like it is covered.)
- **A missing `alt` on an `<img>`**, which is the single most common way a
  screen reader announces an image as "image" with no content.

These tests assert structure in `web/base.html` rather than behaviour, because
the behaviour is CSS. What they can catch is the regression: someone deleting
the skip link, or renaming `main-content` and orphaning the `href`.

Run with:

    DJANGO_SETTINGS_MODULE=config.settings.test python manage.py test web.test_accessibility
"""

import re
from pathlib import Path

from django.test import SimpleTestCase, TestCase
from django.urls import reverse

BACKEND_DIR = Path(__file__).resolve().parent.parent
TEMPLATES_DIR = BACKEND_DIR / "templates" / "web"
BASE_HTML = TEMPLATES_DIR / "base.html"

# Pages that must render for the end-to-end checks. Kept small on purpose:
# `base.html` is the shared shell, so one anonymous page and one authenticated
# page exercise every branch of it.
ANONYMOUS_PAGE = "web:home"


class SkipLinkTests(SimpleTestCase):
    """WCAG 2.4.1 Bypass Blocks / 2.4.7 Focus Visible."""

    def setUp(self):
        self.html = BASE_HTML.read_text(encoding="utf-8")

    def test_the_skip_link_is_the_first_focusable_thing_in_the_body(self):
        body = self.html.split("<body", 1)[1]
        first_link = re.search(r"<a\b[^>]*", body)
        self.assertIsNotNone(first_link, "no link at all in the body")
        self.assertIn(
            'class="skip-link"',
            first_link.group(0),
            "the skip link must precede the navigation, otherwise it is not a "
            "skip link — it is just another link",
        )
        self.assertIn('href="#main-content"', first_link.group(0))

    def test_the_skip_target_exists_and_can_receive_focus(self):
        main = re.search(r"<main\b[^>]*>", self.html)
        self.assertIsNotNone(main, "base.html must have a <main>")
        tag = main.group(0)
        # `id` so the fragment resolves, and `tabindex="-1"` so focus can
        # actually land there — a <main> is not focusable by default, so
        # without it the browser scrolls but focus stays in the nav and the
        # next Tab continues from the sidebar.
        self.assertIn('id="main-content"', tag)
        self.assertIn('tabindex="-1"', tag)

    def test_the_skip_link_is_hidden_without_being_removed(self):
        """`display:none` or `visibility:hidden` would drop it from the tab order.

        The standard way to do this is to move it off-screen, which keeps it
        focusable. Assert the mechanism, so nobody "simplifies" it into
        something that stops working while still looking correct.
        """
        self.assertRegex(self.html, r"\.skip-link\s*\{[^}]*position:\s*fixed")
        self.assertNotRegex(
            self.html,
            r"\.skip-link\s*\{[^}]*display:\s*none",
            "display:none would remove the skip link from the tab order",
        )
        self.assertNotRegex(
            self.html,
            r"\.skip-link\s*\{[^}]*visibility:\s*hidden",
            "visibility:hidden would remove the skip link from the tab order",
        )
        # ...and that it becomes visible on focus.
        self.assertRegex(self.html, r"\.skip-link:focus[^{]*\{[^}]*translateY\(0\)")


class SocialAndSearchMetaTests(SimpleTestCase):
    """Every page was shipping an empty snippet to anything that shares it."""

    def setUp(self):
        # `{% comment %}` blocks are stripped first: this file's own comments
        # quote the anti-pattern they warn about, and a naive scan finds them.
        self.html = BASE_HTML.read_text(encoding="utf-8")
        self.markup = re.sub(
            r"\{%\s*comment\s*%\}.*?\{%\s*endcomment\s*%\}", "", self.html, flags=re.S
        )

    def test_a_description_meta_tag_exists_and_is_not_empty(self):
        match = re.search(r'<meta\s+name="description"\s+content="([^"]*)"', self.html)
        self.assertIsNotNone(match, "no <meta name=\"description\"> in base.html")
        self.assertTrue(
            match.group(1).strip(),
            "the description must have a default; an empty content attribute "
            "is worse than none, because it looks done",
        )

    def test_open_graph_tags_exist(self):
        for prop in ("og:site_name", "og:type", "og:title", "og:description", "og:url"):
            with self.subTest(prop=prop):
                self.assertIn(f'property="{prop}"', self.html)

    def test_twitter_card_is_declared(self):
        self.assertIn('name="twitter:card"', self.html)

    def test_no_block_reference_is_used_for_the_social_tags(self):
        """`{{ self.title }}` looks like the tidy solution and is a trap.

        On this Django version a block reference renders as an **empty
        string**, so it produces `content=""` — an empty description tag,
        which is worse than no tag because it looks deliberate. This was
        verified by rendering, not assumed, after it shipped into a draft of
        this file.
        """
        self.assertNotRegex(
            self.markup,
            r"\{\{\s*self\.",
            "block references render empty here; give og:title/og:description "
            "their own default text",
        )

    def test_the_social_tags_have_their_own_non_empty_defaults(self):
        for attr, pattern in (
            ("og:title", r'property="og:title"\s+content="\{%\s*block og_title\s*%\}(.+?)\{%\s*endblock'),
            (
                "og:description",
                r'property="og:description"\s+content="\{%\s*block og_description\s*%\}(.+?)\{%\s*endblock',
            ),
        ):
            with self.subTest(attr=attr):
                match = re.search(pattern, self.markup)
                self.assertIsNotNone(match, f"{attr} must wrap its default in a block")
                self.assertTrue(match.group(1).strip(), f"{attr} has no default text")


class ReducedMotionTests(SimpleTestCase):
    """Nothing in the app honoured prefers-reduced-motion."""

    def test_base_html_declares_a_reduced_motion_guard(self):
        html = BASE_HTML.read_text(encoding="utf-8")
        self.assertIn(
            "prefers-reduced-motion",
            html,
            "the web app has no reduced-motion support; the only rule anywhere "
            "is inside the vendored Font Awesome stylesheet, which does not "
            "cover this app's own transitions",
        )

    def test_the_guard_actually_neutralises_the_transform_transitions(self):
        """Tailwind's `transition` utility only animates colour-like properties,
        so the blanket duration reset above is close to a no-op for it. What
        genuinely causes trouble is the scale-on-hover used by story cards,
        and that one is neutralised explicitly — a blanket
        `animation-duration: 0` cannot stop a transition-driven transform."""
        html = BASE_HTML.read_text(encoding="utf-8")
        guard = html.split("@media (prefers-reduced-motion: reduce)", 1)[-1]
        self.assertIn("transition-duration", guard)
        # The blanket reset above cannot reach a transition-driven transform,
        # so the one hover-scale in the app is neutralised by name.
        self.assertRegex(guard, r"\.group:hover[^{]*\{[^}]*scale:\s*1\b")


class ImageAltTests(SimpleTestCase):
    """An `<img>` with no `alt` is announced as a nameless image."""

    def test_every_img_carries_an_alt_attribute(self):
        offenders = []
        for path in sorted(TEMPLATES_DIR.rglob("*.html")):
            for number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), 1
            ):
                for match in re.finditer(r"<img\b[^>]*>", line):
                    tag = match.group(0)
                    # An image tag always has a src. `base.html` contains a
                    # bare `<img>` *string literal* inside the script that
                    # sniffs whether the browser is rendering CSS at all, and a
                    # naive `<img` scan flags it as a missing alt.
                    if "src=" not in tag:
                        continue
                    if "alt=" not in tag:
                        offenders.append(f"{path.name}:{number} {tag[:80]}")
        self.assertEqual(
            offenders,
            [],
            "add alt=\"...\", or alt=\"\" if the image is purely decorative",
        )


class RenderedPageChecks(TestCase):
    """The scaffolding has to survive actual rendering, not just sit in a file.

    A `TestCase`, not a `SimpleTestCase`: the home view counts published
    artefacts, so this cannot be a database-free structural check.
    """

    def test_an_anonymous_page_carries_the_description_and_skip_link(self):
        response = self.client.get(reverse(ANONYMOUS_PAGE))
        self.assertEqual(response.status_code, 200)
        html = response.content.decode()
        self.assertIn('name="description"', html)
        self.assertIn('property="og:title"', html)
        self.assertIn('class="skip-link"', html)
        self.assertIn('id="main-content"', html)

    def test_no_description_tag_renders_empty(self):
        """The end-to-end version of the `{{ self.title }}` trap: render, then look.

        A `content=""` description is worse than a missing one, because it
        looks like the work was done.
        """
        response = self.client.get(reverse(ANONYMOUS_PAGE))
        html = response.content.decode()
        for attr in (
            'name="description"',
            'property="og:description"',
            'property="og:title"',
        ):
            with self.subTest(attr=attr):
                match = re.search(attr + r'\s+content="([^"]*)"', html)
                self.assertIsNotNone(match, f"{attr} missing from the rendered page")
                self.assertTrue(match.group(1).strip(), f"{attr} rendered empty")