"""Seed data for the stories app (pure data, no model logic)."""

from .categories import CATEGORY_DATA
from .stories_culture import SEED_STORIES_CULTURE
from .stories_kingdoms import SEED_STORIES_KINGDOMS
from .stories_nature import SEED_STORIES_NATURE

STORIES = [
    *SEED_STORIES_NATURE,
    *SEED_STORIES_KINGDOMS,
    *SEED_STORIES_CULTURE,
]
