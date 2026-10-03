"""Seed data for the stories app (pure data, no model logic)."""

from .categories import CATEGORY_DATA
from .stories_culture import SEED_STORIES_CULTURE
from .stories_discovered import SEED_STORIES_DISCOVERED
from .stories_kingdoms import SEED_STORIES_KINGDOMS
from .stories_nature import SEED_STORIES_NATURE

STORIES = [
    *SEED_STORIES_NATURE,
    *SEED_STORIES_KINGDOMS,
    *SEED_STORIES_CULTURE,
    *SEED_STORIES_DISCOVERED,
]

# Re-exported so callers can `from stories.seed_data import CATEGORY_DATA`
# without reaching into the submodule.
__all__ = [
    'CATEGORY_DATA',
    'SEED_STORIES_CULTURE',
    'SEED_STORIES_DISCOVERED',
    'SEED_STORIES_KINGDOMS',
    'SEED_STORIES_NATURE',
    'STORIES',
]
