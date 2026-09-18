"""
Template tags & filters for the web interface.

Icons: the mobile app renders Font Awesome via FaIcon (app_icons.dart).
The web UI mirrors this with Font Awesome 6 — no emoji "stickers".
DB-stored emoji glyphs (category icons, badge emojis) are mapped to a
consistent Font Awesome icon through ICON_MAP; unknown glyphs fall back
to a sensible icon.

Also provides a dependency-free Markdown renderer for story content and
small quiz/chart helpers.
"""

import html
import re

from django import template
from django.utils.html import format_html, mark_safe

register = template.Library()

# ---------------------------------------------------------------------------
# Icon mapping
# ---------------------------------------------------------------------------
ICON_MAP = {
    # Navigation / general (mirrors app_icons.dart usage)
    'home': 'fa-house',
    'book-open': 'fa-book-open',
    'book': 'fa-book',
    'landmark': 'fa-landmark',
    'bookmark': 'fa-bookmark',
    'trophy': 'fa-trophy',
    'chart': 'fa-chart-line',
    'search': 'fa-magnifying-glass',
    'filter': 'fa-sliders',
    'close': 'fa-xmark',
    'eye': 'fa-eye',
    'heart': 'fa-heart',
    'heart-regular': 'fa-regular fa-heart',
    'bookmark-solid': 'fa-bookmark',
    'bookmark-regular': 'fa-regular fa-bookmark',
    'share': 'fa-share-nodes',
    'flag': 'fa-flag',
    'clock': 'fa-clock',
    'globe': 'fa-globe',
    'language': 'fa-language',
    'user': 'fa-user',
    'users': 'fa-users',
    'sign-out': 'fa-arrow-right-from-bracket',
    'chevron-right': 'fa-chevron-right',
    'arrow-right': 'fa-arrow-right',
    'arrow-left': 'fa-arrow-left',
    'check-circle': 'fa-circle-check',
    'times-circle': 'fa-circle-xmark',
    'info': 'fa-circle-info',
    'spinner': 'fa-solid fa-spinner fa-spin-pulse',
    'sparkles': 'fa-wand-magic-sparkles',
    'fire': 'fa-fire',
    'compass': 'fa-compass',
    'layer-group': 'fa-layer-group',
    'question': 'fa-circle-question',
    'graduation': 'fa-graduation-cap',
    'certificate': 'fa-certificate',
    'bolt': 'fa-bolt',
    'calendar': 'fa-calendar-days',
    'location': 'fa-location-dot',
    'qrcode': 'fa-qrcode',
    'play': 'fa-play',
    'download': 'fa-download',
    'moon': 'fa-moon',
    'bars': 'fa-bars',
    'envelope': 'fa-envelope',
    'lock': 'fa-lock',
    'user-pen': 'fa-user-pen',
    'shield': 'fa-shield-halved',
    'feather': 'fa-feather',
    'magnifier': 'fa-magnifying-glass',
    'building-columns': 'fa-building-columns',
    'gauge': 'fa-gauge-high',
    'star': 'fa-star',
    'medal': 'fa-medal',
    'flame': 'fa-fire-flame-curved',
    'microphone': 'fa-microphone',
    'video': 'fa-video',
    'refresh': 'fa-arrows-rotate',
    'edit': 'fa-pen-to-square',
    'trash': 'fa-trash-can',
    'headphones': 'fa-headphones',

    # DB-stored emoji glyph → icon mapping
    '📖': 'fa-book-open',
    '📚': 'fa-book',
    '🏛️': 'fa-landmark',
    '🏛': 'fa-landmark',
    '🗿': 'fa-monument',
    '🛕': 'fa-gopuram',
    '🌄': 'fa-mountain-sun',
    '🌊': 'fa-water',
    '🏆': 'fa-trophy',
    '🔍': 'fa-magnifying-glass',
    '✍️': 'fa-feather-pointed',
    '⚡': 'fa-bolt',
    '❤️': 'fa-heart',
    '🤍': 'fa-regular fa-heart',
    '🔖': 'fa-bookmark',
    '📑': 'fa-regular fa-bookmark',
    '👁': 'fa-eye',
    '🌍': 'fa-earth-africa',
    '🥇': 'fa-medal',
    '🎉': 'fa-champagne-glasses',
    '🎭': 'fa-masks-theater',
    '🪘': 'fa-drum',
    '🧭': 'fa-compass',
    '🗂️': 'fa-layer-group',
    '🔥': 'fa-fire',
    '👋': 'fa-hand',
    '🤲': 'fa-hands',
    '📊': 'fa-chart-simple',
    '🗡️': 'fa-khanda',
    '🧵': 'fa-scissors',
    '🥁': 'fa-drum',
    '🏺': 'fa-jar',
    '💎': 'fa-gem',
    '🔨': 'fa-hammer',
    '🪡': 'fa-vector-square',
    '⚗️': 'fa-flask',
    '📦': 'fa-box-open',
    '🛖': 'fa-igloo',
}


@register.simple_tag
def icon(name, size='text-base', extra_class=''):
    """Render a Font Awesome icon: {% icon 'heart' 'text-lg' 'text-red' %}."""
    fa_class = ICON_MAP.get(name, name)
    return _format_icon(fa_class, size, extra_class)


@register.simple_tag
def emoji_icon(emoji, size='text-base', extra_class=''):
    """Render an icon for a DB-stored emoji glyph (categories, badges)."""
    fa_class = ICON_MAP.get(emoji, 'fa-book-open')
    return _format_icon(fa_class, size, extra_class)


def _format_icon(fa_class, size='text-base', extra_class=''):
    # format_html marks the result safe for template rendering (simple_tag
    # escapes plain strings) while escaping the interpolated pieces, so
    # DB-stored glyphs can never inject markup.
    fa_class = fa_class.strip()
    if not fa_class.startswith(('fa-solid', 'fa-regular', 'fa-brands')):
        fa_class = f'fa-solid {fa_class}'
    classes = f'{fa_class} {size} {extra_class}'.strip()
    return format_html('<span class="inline-block {}" aria-hidden="true"></span>', classes)


@register.simple_tag
def role_icon(role):
    """Icon for a user role — mirrors mobile RoleBadge icons."""
    mapping = {
        'visitor': 'fa-magnifying-glass',
        'contributor': 'fa-feather-pointed',
        'institution_manager': 'fa-building-columns',
        'admin': 'fa-bolt',
    }
    fa_class = mapping.get(role, 'fa-user')
    return _format_icon(fa_class, 'text-xs')


@register.simple_tag
def artifact_category_icon(category_slug, size='text-base'):
    """Icon for an Artifact.Category slug."""
    mapping = {
        'sculpture': 'fa-monument',
        'textile': 'fa-bars-staggered',
        'instrument': 'fa-drum',
        'jewelry': 'fa-gem',
        'pottery': 'fa-jar',
        'mask': 'fa-masks-theater',
        'weapon': 'fa-khanda',
        'fabric': 'fa-scroll',
        'tool': 'fa-hammer',
        'other': 'fa-box-open',
    }
    fa_class = mapping.get(category_slug, 'fa-box-open')
    return _format_icon(fa_class, size)


# ---------------------------------------------------------------------------
# Markdown — dependency-free renderer for story content. The mobile app
# renders the same Markdown via flutter_markdown; this covers the subset
# the seeded stories use: headings, bold/italic, lists, quotes, links,
# code, hr and paragraphs.
# ---------------------------------------------------------------------------

def _inline(text: str) -> str:
    """Render inline markdown (bold, italic, code, links) with escaping."""
    text = html.escape(text, quote=True)
    text = re.sub(r'\[([^\]]+)\]\((https?://[^)\s]+)\)',
                  r'<a href="\2" rel="noopener" target="_blank">\1</a>', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', text)
    text = re.sub(r'(?<!\*)\*([^*\n]+)\*(?!\*)', r'<em>\1</em>', text)
    text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
    return text


@register.filter
def markdown(value: str) -> str:
    """Minimal safe Markdown → HTML for story content."""
    if not value:
        return ''
    lines = value.replace('\r\n', '\n').split('\n')
    out = []
    state = {'list': None, 'quote': False}
    paragraph = []

    def flush_paragraph():
        if paragraph:
            out.append(f'<p>{_inline(" ".join(paragraph))}</p>')
            paragraph.clear()

    def close_list():
        if state['list']:
            out.append(f"</{state['list']}>")
            state['list'] = None

    def close_quote():
        if state['quote']:
            out.append('</blockquote>')
            state['quote'] = False

    for raw in lines:
        line = raw.rstrip()

        if line.strip().startswith('```'):
            flush_paragraph(); close_list(); close_quote()
            out.append('<pre><code>' + html.escape(line.strip()[3:]) + '</code></pre>')
            continue

        if not line.strip():
            flush_paragraph(); close_list(); close_quote()
            continue

        heading = re.match(r'^(#{1,3})\s+(.*)$', line)
        if heading:
            flush_paragraph(); close_list(); close_quote()
            level = len(heading.group(1))
            out.append(f'<h{level}>{_inline(heading.group(2))}</h{level}>')
            continue

        if re.match(r'^\s*([-*_]\s*){3,}$', line):
            flush_paragraph(); close_list(); close_quote()
            out.append('<hr>')
            continue

        if line.lstrip().startswith('>'):
            flush_paragraph(); close_list()
            if not state['quote']:
                out.append('<blockquote>')
                state['quote'] = True
            out.append(f'<p>{_inline(line.lstrip()[1:].strip())}</p>')
            continue
        close_quote()

        ul = re.match(r'^\s*[-*+]\s+(.*)$', line)
        ol = re.match(r'^\s*\d+[.)]\s+(.*)$', line)
        if ul:
            flush_paragraph()
            if state['list'] != 'ul':
                close_list()
                out.append('<ul>')
                state['list'] = 'ul'
            out.append(f'<li>{_inline(ul.group(1))}</li>')
            continue
        if ol:
            flush_paragraph()
            if state['list'] != 'ol':
                close_list()
                out.append('<ol>')
                state['list'] = 'ol'
            out.append(f'<li>{_inline(ol.group(1))}</li>')
            continue

        close_list()
        paragraph.append(line.strip())

    flush_paragraph(); close_list(); close_quote()
    return mark_safe('\n'.join(out))


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

@register.filter
def dict_item(items, index):
    """Return items[index] or None — lists (quiz questions) and dicts
    (latest quiz attempt per quiz id) both supported."""
    try:
        return items[int(index)]
    except (IndexError, TypeError, ValueError, KeyError):
        pass
    try:
        return items.get(index)
    except AttributeError:
        return None


@register.filter
def question_options(question):
    """Return [(letter, text), …] for a quiz question's A–D options."""
    options = []
    for letter in ('a', 'b', 'c', 'd'):
        text = getattr(question, f'option_{letter}', '')
        if text:
            options.append((letter, text))
    return options


@register.filter
def status_color(status):
    """Tailwind classes for a story status pill."""
    mapping = {
        'published': 'bg-savannah-tint text-savannah',
        'pending': 'bg-ochre-tint text-ochre',
        'draft': 'bg-brand-border/50 text-secondary-text',
        'rejected': 'bg-brand-error/10 text-brand-error',
        'archived': 'bg-secondary-text/10 text-secondary-text',
    }
    return mapping.get(status, 'bg-secondary-text/10 text-secondary-text')


@register.simple_tag
def growth_bars(series, height_class='h-28'):
    """Render a pure-CSS bar chart for a daily-growth series."""
    try:
        peak = max(int(p.get('count', 0)) for p in series) or 1
    except (TypeError, ValueError, AttributeError):
        peak = 1
    bars = []
    for point in series:
        count = int(point.get('count', 0))
        pct = round(count / peak * 100)
        min_h = '4px' if count else '1px'
        bars.append(format_html(
            '<div class="group relative flex-1" title="{}: {}">'
            '<div class="w-full rounded-t bg-terracotta/80 transition group-hover:bg-terracotta" '
            'style="height:{}%;min-height:{};"></div></div>',
            point.get('date', ''), count, pct, min_h,
        ))
    inner = ''.join(str(bar) for bar in bars)
    return format_html(
        '<div class="flex {} items-end gap-[3px]">{}</div>'
        '<p class="mt-3 text-xs text-secondary-text">Daily new registrations — hover a bar for details.</p>',
        height_class, format_html(inner),
    )


@register.filter
def xp_width(progress):
    """Convert xp_progress (0.0–1.0) to a CSS width percentage."""
    try:
        return max(0, min(100, round(float(progress) * 100)))
    except (TypeError, ValueError):
        return 0
