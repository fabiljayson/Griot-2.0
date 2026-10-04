"""
Stage 2 — the web palette must stop putting the brand bronze on text.

The defect these tests exist for is not a bug that throws. It is that the brand
accent `#C68B29` was carried by 83 template elements as a *text* colour while
measuring 2.95:1 on white — WCAG 1.4.3 asks 4.5:1 — and by another 23 elements
as a button fill under a white label, which is the same ratio again. Nothing
about the pages looked broken; they simply were not readable for anyone who
needs the contrast, and the auth form's primary button was the worst of it.

Two things make this awkward to test by eye, and so these tests are here:

1. **The web app has a dark theme.** `darkMode: 'class'` with `dark:bg-mud-charcoal`
   on 27 elements. So there is no single correct bronze for text — `#8A5D13`
   clears 4.5:1 on the light ground and *fails* at 3.26:1 on `bg-mud-charcoal`,
   while `#D9A84D` is the reverse. The accent text colour is therefore a CSS
   custom property that flips with the `.dark` class, and a static hex in a
   template is a latent failure in whichever theme it was not measured for.

2. **`text-terracotta` is ambiguous under a regex.** `text-terracotta-tint/70`,
   `text-ochre-dark` and `text-terracotta/50` are all different things, and the
   `/50` ones are decorative icons beside visible labels, which 1.4.3 exempts.
   A blanket find-and-replace either misses them or breaks them.

So: assert the two variable values clear 4.5:1 against every ground actually
used, assert both variable definitions exist, and assert the two mistakes
cannot come back.

Run with:

    DJANGO_SETTINGS_MODULE=config.settings.test python manage.py test web.test_contrast
"""

import re
from pathlib import Path

from django.test import SimpleTestCase

BACKEND_DIR = Path(__file__).resolve().parent.parent
TEMPLATES_DIR = BACKEND_DIR / "templates" / "web"
BASE_HTML = TEMPLATES_DIR / "base.html"
THEME_JS = BACKEND_DIR / "static" / "web" / "js" / "tailwind-theme.js"

# Parsed out of the files under test rather than hardcoded, so that changing a
# colour without revisiting this file fails loudly instead of passing against a
# stale copy of the number it is supposed to police.
ROOT_VAR_RE = re.compile(r":root\s*\{\s*--griot-accent-text:\s*(\d+)\s+(\d+)\s+(\d+)")
DARK_VAR_RE = re.compile(r"\.dark\s*\{\s*--griot-accent-text:\s*(\d+)\s+(\d+)\s+(\d+)")


def _channel(value: float) -> float:
    """sRGB 0-1 to linear-light, per WCAG 2.x relative luminance."""
    srgb = value / 255
    if srgb <= 0.03928:
        return srgb / 12.92
    return ((srgb + 0.055) / 1.055) ** 2.4


def _relative_luminance(hex_colour: str) -> float:
    value = hex_colour.lstrip("#")
    r, g, b = (int(value[i : i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b)


def contrast(foreground: str, background: str) -> float:
    """WCAG contrast ratio between two hex colours, 1.0 - 21.0."""
    a, b = _relative_luminance(foreground), _relative_luminance(background)
    lighter, darker = max(a, b), min(a, b)
    return (lighter + 0.05) / (darker + 0.05)


# Grounds the templates actually paint. Taken from a grep of every `bg-*` used
# in the web templates, not from the palette file — a colour nobody uses does
# not need to pass, and one that is used but missing here would pass untested.
LIGHT_GROUNDS = {"white": "#FFFFFF", "ivory": "#FBF9F4", "bronze tint": "#F5ECD6"}
DARK_GROUNDS = {"mud-charcoal": "#0F1219", "deep-earth": "#1C1C1E", "slate-800": "#1E293B"}

BRONZE = "#C68B29"
INK = "#1C1C1E"


def _hex(rgb_triple: str) -> str:
    return "#%02X%02X%02X" % tuple(int(c) for c in rgb_triple.split())


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _template_files():
    return sorted(p for p in TEMPLATES_DIR.rglob("*.html"))


class AccentTextVariableTests(SimpleTestCase):
    """The flipping accent-text variable must be defined and must be legible."""

    def test_base_html_defines_the_variable_for_both_themes(self):
        html = _read(BASE_HTML)
        self.assertRegex(
            html,
            ROOT_VAR_RE,
            "base.html must define --griot-accent-text on :root. It cannot live "
            "in tailwind.input.css: the Play-CDN fallback generates its "
            "utilities from the config alone and would have nothing to read.",
        )
        self.assertRegex(
            html,
            DARK_VAR_RE,
            "base.html must define --griot-accent-text on .dark, or the accent "
            "text colour never flips and every dark-theme accent label fails.",
        )

    def test_the_light_value_clears_4_5_on_every_light_ground(self):
        light = _hex(" ".join(ROOT_VAR_RE.search(_read(BASE_HTML)).groups()))
        for name, ground in LIGHT_GROUNDS.items():
            with self.subTest(ground=name):
                self.assertGreaterEqual(
                    contrast(light, ground),
                    4.5,
                    f"accent text {light} is {contrast(light, ground):.2f}:1 on {name}",
                )

    def test_the_dark_value_clears_4_5_on_every_dark_ground(self):
        dark = _hex(" ".join(DARK_VAR_RE.search(_read(BASE_HTML)).groups()))
        for name, ground in DARK_GROUNDS.items():
            with self.subTest(ground=name):
                self.assertGreaterEqual(
                    contrast(dark, ground),
                    4.5,
                    f"accent text {dark} is {contrast(dark, ground):.2f}:1 on {name}",
                )

    def test_the_light_value_is_genuinely_illegal_in_dark_mode(self):
        """Why this is a variable and not one static hex.

        If someone 'simplifies' the theme back to a fixed colour, this is the
        assertion that explains what broke.
        """
        light = _hex(" ".join(ROOT_VAR_RE.search(_read(BASE_HTML)).groups()))
        self.assertLess(
            contrast(light, "#0F1219"),
            4.5,
            "the light accent now passes on mud-charcoal, so it could be used "
            "as a single static value — revisit this test before doing that",
        )

    def test_theme_config_exposes_a_var_backed_strong_shade(self):
        theme = _read(THEME_JS)
        self.assertIn(
            "rgb(var(--griot-accent-text) / <alpha-value>)",
            theme,
            "the bronze scale must expose a `strong` shade that resolves through "
            "the variable, for each of cam-bronze, terracotta and ochre",
        )
        for family in ("'cam-bronze'", "terracotta:", "ochre:"):
            with self.subTest(family=family):
                line = next(
                    ln for ln in theme.splitlines() if ln.strip().startswith(family)
                )
                self.assertIn("strong:", line)

    def test_the_stated_contrast_pairs_hold(self):
        """The base bronze stays a decorative token and must not be 'fixed'.

        Darkening `DEFAULT` to make the text pass would have wrecked every
        gradient stop, bead and ring at the same time. Assert the bronze still
        fails as text, so that stays visible.
        """
        self.assertLess(contrast(BRONZE, "#FFFFFF"), 4.5)
        # And the ink the web uses on a bronze fill passes.
        self.assertGreaterEqual(contrast(INK, BRONZE), 4.5)


class TemplateUsageTests(SimpleTestCase):
    """The two mistakes cannot come back."""

    # Bare `text-terracotta` / `text-ochre`, but NOT `-tint`, `-dark`, or an
    # opacity modifier. `/50` on a large decorative icon beside a visible text
    # label is exempt from 1.4.3 and is deliberately left alone.
    BARE_ACCENT_TEXT = re.compile(r"text-(?:terracotta|ochre)(?![\w/-])")
    OPAQUE_ACCENT_BG = re.compile(r"bg-(?:terracotta|ochre|cam-bronze)(?![\w/-])")
    WHITE_TEXT = re.compile(r"text-white(?![\w/-])")
    CLASS_ATTR = re.compile(r'class="([^"]*)"')

    def test_no_template_uses_the_bare_accent_for_text(self):
        offenders = []
        for path in _template_files():
            for number, line in enumerate(_read(path).splitlines(), 1):
                if self.BARE_ACCENT_TEXT.search(line):
                    offenders.append(f"{path.relative_to(BACKEND_DIR)}:{number}")
        self.assertEqual(
            offenders,
            [],
            "these use the decorative accent as text; use the -strong shade",
        )

    def test_no_template_puts_white_text_on_an_opaque_accent_fill(self):
        offenders = []
        for path in _template_files():
            for number, line in enumerate(_read(path).splitlines(), 1):
                for match in self.CLASS_ATTR.finditer(line):
                    classes = re.sub(r"dark:[^\s]+", "", match.group(1))
                    if self.OPAQUE_ACCENT_BG.search(classes) and self.WHITE_TEXT.search(
                        classes
                    ):
                        offenders.append(
                            f"{path.relative_to(BACKEND_DIR)}:{number} "
                            f"{match.group(1)[:70]}"
                        )
        self.assertEqual(
            offenders,
            [],
            "white on the bronze accent is 2.95:1 — use text-cam-dark instead",
        )

    def test_the_compiled_stylesheet_actually_ships_the_strong_classes(self):
        """A Tailwind class that was never compiled silently renders as no-op."""
        css = (BACKEND_DIR / "static" / "web" / "css" / "tailwind.css").read_text(
            encoding="utf-8"
        )
        for utility in (
            ".text-terracotta-strong",
            ".text-ochre-strong",
            # `cam-bronze-strong` is deliberately absent: nothing in the
            # templates uses it yet, and Tailwind only emits what is
            # referenced. Its availability is asserted from the config above.
            ".text-cam-bronze-light",
            ".text-cam-dark",
        ):
            with self.subTest(utility=utility):
                self.assertIn(utility, css)
        self.assertIn(
            ".text-terracotta-strong{color:rgb(var(--griot-accent-text) / 1)}",
            css,
            "the strong shade must resolve through the variable, not a fixed hex",
        )