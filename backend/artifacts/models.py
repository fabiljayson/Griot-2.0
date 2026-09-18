"""
Deprecated: The Artifact model has been consolidated into qr_codes.Artifact.

This app is kept for migration history integrity but no longer defines models.
The import_crawl_data management command now uses qr_codes.Artifact.
"""

from django.db import models
