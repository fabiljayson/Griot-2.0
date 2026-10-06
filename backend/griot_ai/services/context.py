"""Assemble the cultural context an answer must be grounded in.

`ask_griot` is a retrieval-grounded question answerer, not an oracle. The model
is handed the artifact's own catalogue text, its cultural significance note and
the published stories that feature it, and is told to answer from that alone —
because the alternative, a fluent model inventing a Bamoun king's name, is worse
than saying "the record does not cover that". Heritage content is the one place
where a confident wrong answer does lasting damage.

The context is assembled here rather than in the view so the VR panel, the
mobile app and any future web surface all ground on exactly the same text.
"""

from dataclasses import dataclass, field

from django.conf import settings

from stories.models import Story

#: Per-source character cap. A story is markdown and can run to tens of
#: thousands of characters; sending all of it would cost more per question than
#: the question is worth and push the useful part out of the model's attention.
DEFAULT_SOURCE_CHARS = 4000


@dataclass
class GriotContext:
    """The grounding text plus a citable record of where it came from."""

    text: str
    sources: list[dict] = field(default_factory=list)

    @property
    def is_empty(self) -> bool:
        return not self.text.strip()


def _clip(value: str, limit: int) -> str:
    value = (value or '').strip()
    if len(value) <= limit:
        return value
    # Clip on a word boundary so the model is not handed half a word, and say
    # how much was dropped rather than letting the model assume it saw it all.
    clipped = value[:limit].rsplit(' ', 1)[0]
    return f'{clipped} […{len(value) - len(clipped)} more characters not shown]'


def _artifact_section(artifact, limit: int) -> tuple[str, int]:
    lines = [f'[Artifact #{artifact.pk} — {artifact.title}]']
    if artifact.category:
        lines.append(f'Category: {artifact.get_category_display()}')
    if artifact.culture:
        lines.append(f'Culture: {artifact.culture}')
    if artifact.region:
        lines.append(f'Region: {artifact.region}')
    if artifact.estimated_date:
        lines.append(f'Period: {artifact.estimated_date}')
    if artifact.materials:
        lines.append(f'Materials: {artifact.materials}')
    if artifact.museum_name:
        lines.append(f'Held at: {artifact.museum_name}')
    if artifact.description:
        lines.append(f'Description: {_clip(artifact.description, limit)}')
    if artifact.story:
        lines.append(f'Catalogue narrative: {_clip(artifact.story, limit)}')
    if artifact.historical_significance:
        lines.append(
            f'Historical significance: {_clip(artifact.historical_significance, limit)}'
        )

    text = '\n'.join(lines)
    return text, len(text)


def _story_section(story, limit: int) -> tuple[str, int]:
    lines = [f'[Story #{story.pk} — {story.title}]']
    if story.region:
        lines.append(f'Region: {story.region}')
    if story.summary:
        lines.append(f'Summary: {_clip(story.summary, limit)}')
    if story.cultural_context:
        lines.append(f'Cultural context: {_clip(story.cultural_context, limit)}')
    if story.moral_lesson:
        lines.append(f'Moral: {_clip(story.moral_lesson, limit)}')
    if story.content:
        lines.append(f'Text: {_clip(story.content, limit)}')

    text = '\n'.join(lines)
    return text, len(text)


def _experience_section(experience, limit: int) -> tuple[str, int]:
    lines = [f'[VR experience #{experience.pk} — {experience.title}]']
    if experience.description:
        lines.append(_clip(experience.description, limit))
    if experience.museum_name:
        lines.append(f'Museum: {experience.museum_name}')
    if experience.region:
        lines.append(f'Region: {experience.region}')
    if experience.culture:
        lines.append(f'Culture: {experience.culture}')

    text = '\n'.join(lines)
    return text, len(text)


def build_context(
    *,
    artifact=None,
    story=None,
    experience=None,
    max_chars=None,
) -> GriotContext:
    """Assemble grounding text for the given subject.

    Sources are added in priority order — artifact, then story, then experience
    — and stop at the budget, so the most specific content is never the part
    that gets truncated.
    """
    budget = int(
        max_chars
        if max_chars is not None
        else getattr(settings, 'GRIOT_AI_MAX_CONTEXT_CHARS', 6000)
    )
    source_limit = min(DEFAULT_SOURCE_CHARS, max(budget // 2, 500))

    sections: list[str] = []
    sources: list[dict] = []
    used = 0

    def add(text: str, length: int, source: dict) -> None:
        nonlocal used
        sections.append(text)
        sources.append(source)
        used += length

    if artifact is not None:
        text, length = _artifact_section(artifact, source_limit)
        add(text, length, {
            'type': 'artifact',
            'id': artifact.pk,
            'slug': artifact.slug,
            'title': artifact.title,
            'url': f'/artifact/{artifact.slug}/',
        })

        # Only stories a reader could open themselves. A draft story must not
        # reach a reader's answer as an uncited "fact" before review.
        for related in artifact.stories.filter(
            status=Story.Status.PUBLISHED
        ).only('id', 'slug', 'title', 'summary', 'cultural_context', 'moral_lesson', 'content', 'region')[:3]:
            if used + 400 > budget:
                break
            text, length = _story_section(related, source_limit // 2)
            add(text, length, {
                'type': 'story',
                'id': related.pk,
                'slug': related.slug,
                'title': related.title,
                'url': f'/story/{related.slug}/',
            })

    if story is not None:
        text, length = _story_section(story, source_limit)
        add(text, length, {
            'type': 'story',
            'id': story.pk,
            'slug': story.slug,
            'title': story.title,
            'url': f'/story/{story.slug}/',
        })

    if experience is not None:
        text, length = _experience_section(experience, source_limit)
        add(text, length, {
            'type': 'experience',
            'id': experience.pk,
            'slug': experience.slug,
            'title': experience.title,
            'url': '',
        })

    return GriotContext(text='\n\n'.join(sections), sources=sources)
