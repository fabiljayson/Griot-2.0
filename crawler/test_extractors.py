import unittest

from extractors import sections_to_items
from utils import summarize_description


class ArtifactDescriptionTests(unittest.TestCase):
    def test_artifact_classifier_ignores_unrelated_long_paragraph_terms(self):
        item = sections_to_items(
            [{
                'title': 'Other Tourist Attractions',
                'text_parts': [
                    'In addition to the scenery, the area offers many attractions. '
                    'Visitors can tour a museum and see handicrafts, art objects, '
                    'and pottery in nearby cultural centers.'
                ],
                'images': [{
                    'original_url': 'https://example.org/landscape.jpg',
                    'alt_text': 'Scenery around Bamenda',
                }],
            }],
            'https://example.org/bamenda',
            'Bamenda',
        )[0]

        self.assertNotEqual(item['category'], 'Artifact')

    def test_actual_mask_item_remains_classified_as_artifact(self):
        item = sections_to_items(
            [{
                'title': 'Bamoun Elephant Mask',
                'text_parts': [
                    'A carved ceremonial mask worn during royal celebrations.'
                ],
                'images': [],
            }],
            'https://example.org/foumban',
            'Foumban',
        )[0]

        self.assertEqual(item['category'], 'Artifact')

    def test_summary_keeps_a_short_lead_without_replacing_full_text(self):
        full_text = (
            'A ceremonial throne used by Bamoun kings. '
            'It features carved wooden supports and bronze panels. '
            'The throne represents royal authority.'
        )

        summary = summarize_description(full_text)

        self.assertEqual(
            summary,
            'A ceremonial throne used by Bamoun kings. '
            'It features carved wooden supports and bronze panels.',
        )
        self.assertLessEqual(len(summary), 240)
        self.assertGreater(len(full_text), len(summary))

    def test_section_uses_image_alt_text_when_no_paragraph_description_exists(self):
        item = sections_to_items(
            [{
                'title': 'Bamoun bronze throne',
                'text_parts': [],
                'images': [{
                    'original_url': 'https://example.org/throne.jpg',
                    'alt_text': 'Carved wooden throne with bronze panels',
                }],
            }],
            'https://example.org/foumban',
            'Foumban',
        )[0]

        self.assertEqual(
            item['short_description'],
            'Carved wooden throne with bronze panels',
        )
        self.assertEqual(item['description'], item['short_description'])


if __name__ == '__main__':
    unittest.main()