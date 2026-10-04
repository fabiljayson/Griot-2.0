"""
URLs for the crawler administration API (§18).

Mounted under `/api/crawler/` from `api/urls.py`. Note what is *absent*: there
is no public read endpoint here. §19 is explicit that Flutter only receives
content that passed review, so crawled items are reachable exclusively by
authenticated administrators through the paths below.
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    CrawledItemViewSet,
    CrawlJobViewSet,
    CrawlSourceViewSet,
    CrawlStartView,
)

router = DefaultRouter()
router.register('sources', CrawlSourceViewSet, basename='crawl-source')
router.register('jobs', CrawlJobViewSet, basename='crawl-job')
router.register('items', CrawledItemViewSet, basename='crawled-item')

urlpatterns = [
    # Declared before the router so `start/` is not swallowed by the
    # `jobs`/`items` detail patterns.
    path('start/', CrawlStartView.as_view(), name='crawler-start'),
    path('', include(router.urls)),
]
