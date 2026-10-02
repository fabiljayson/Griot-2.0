import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from runner import crawl_all


class CrawlCategoryFilterTests(unittest.TestCase):
    def test_category_filter_writes_only_matching_items(self):
        page_info = {'url': '/test-region/', 'type': 'region'}
        extracted_items = [
            {
                'id': 'woven-mask',
                'title': 'Woven Mask',
                'category': 'Artifact',
                'description': 'A woven ceremonial mask.',
                'short_description': 'A woven ceremonial mask.',
                'images': [],
            },
            {
                'id': 'river-legend',
                'title': 'River Legend',
                'category': 'Legend',
                'description': 'A story about a river.',
                'short_description': 'A story about a river.',
                'images': [],
            },
        ]

        with tempfile.TemporaryDirectory() as directory:
            with (
                patch('runner.config.PAGES_TO_CRAWL', [page_info]),
                patch('runner.fetch_page', return_value=object()),
                patch('runner.extract_region_page', return_value=extracted_items),
            ):
                items = crawl_all(
                    Path(directory),
                    dry_run=True,
                    category='artifact',
                )

            output_path = Path(directory) / 'cameroon_content.json'
            with output_path.open(encoding='utf-8') as output_file:
                saved_items = json.load(output_file)

        self.assertEqual([item['category'] for item in items], ['Artifact'])
        self.assertEqual(saved_items, items)