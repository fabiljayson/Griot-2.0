import json
import tempfile
from io import StringIO
from pathlib import Path

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .models import Artifact, QRCodeScan

User = get_user_model()


class SeedArtifactCaptionTests(TestCase):
    def test_seed_command_refreshes_existing_artifact_caption(self):
        artifact = Artifact.objects.create(
            title='Bamoun Royal Mask',
            description='An older, longer artifact description.',
            category='mask',
        )

        call_command('seed_qr_codes', stdout=StringIO())

        artifact.refresh_from_db()
        self.assertEqual(
            artifact.description,
            'A carved Bamoun royal mask decorated with beads and cowrie shells, '
            'worn in Foumban ceremonies.',
        )


class ArtifactTests(APITestCase):
    def setUp(self):
        self.manager = User.objects.create_user(
            'manager1',
            email='manager1@example.com',
            password='hunter2secure',
            role='institution_manager',
        )
        self.visitor = User.objects.create_user(
            'visitor1',
            email='visitor1@example.com',
            password='hunter2secure',
            role='visitor',
        )
        self.artifact = Artifact.objects.create(
            title='Royal Bamoun Throne',
            description='A ceremonial throne used by Bamoun kings.',
            category='sculpture',
            culture='Bamoun',
            region='West Region',
            materials='wood, bronze',
            museum_name='Foumban Royal Museum',
            is_published=True,
            created_by=self.manager,
        )
        self.draft_artifact = Artifact.objects.create(
            title='Draft Artifact',
            description='Not yet published.',
            is_published=False,
            created_by=self.manager,
        )

    def test_list_published_artifacts(self):
        """Anonymous users should see only published artifacts."""
        url = reverse('qr_codes:artifact-list')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data['results']), 1)
        self.assertEqual(resp.data['results'][0]['title'], 'Royal Bamoun Throne')

    def test_manager_sees_all_artifacts(self):
        """Managers should see all artifacts including drafts."""
        self.client.force_authenticate(self.manager)
        url = reverse('qr_codes:artifact-list')
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data['results']), 2)

    def test_retrieve_artifact_detail(self):
        url = reverse('qr_codes:artifact-detail', kwargs={'slug': 'royal-bamoun-throne'})
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['title'], 'Royal Bamoun Throne')
        self.assertEqual(resp.data['culture'], 'Bamoun')

    def test_create_artifact_requires_manager(self):
        self.client.force_authenticate(self.visitor)
        url = reverse('qr_codes:artifact-list')
        resp = self.client.post(url, {
            'title': 'New Artifact',
            'description': 'A new artifact.',
            'category': 'mask',
        })
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)

    def test_manager_can_create_artifact(self):
        self.client.force_authenticate(self.manager)
        url = reverse('qr_codes:artifact-list')
        resp = self.client.post(url, {
            'title': 'Bamileke Elephant Mask',
            'description': 'A ceremonial elephant mask.',
            'category': 'mask',
            'culture': 'Bamileke',
            'region:': 'West Region',
            'materials': 'wood, raffia',
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(resp.data['title'], 'Bamileke Elephant Mask')

    def test_generate_qr_code_svg(self):
        self.client.force_authenticate(self.manager)
        url = reverse('qr_codes:artifact-generate-qr', kwargs={'slug': 'royal-bamoun-throne'})
        resp = self.client.post(url, {
            'format': 'svg',
            'foreground': '#C85A32',
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('svg', resp.data)
        self.assertIn('deep_link', resp.data)
        self.assertIn('africanteller.org', resp.data['deep_link'])
        self.artifact.refresh_from_db()
        self.assertIn('<svg', self.artifact.qr_code_svg)

    def test_generate_qr_requires_manager(self):
        """Generating a QR code is a manager action, not a public one.

        Regression: `get_permissions` only listed the CRUD actions, so
        `generate_qr` fell through to `AllowAny` and an anonymous POST could
        persist `qr_code_svg` onto a published artifact.
        """
        url = reverse('qr_codes:artifact-generate-qr', kwargs={'slug': 'royal-bamoun-throne'})

        # Anonymous: rejected, and nothing is written.
        resp = self.client.post(url, {'format': 'svg'})
        self.assertIn(resp.status_code, (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN))
        self.artifact.refresh_from_db()
        self.assertEqual(self.artifact.qr_code_svg, '')

        # Authenticated but only a Visitor: still rejected.
        self.client.force_authenticate(self.visitor)
        resp = self.client.post(url, {'format': 'svg'})
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        self.artifact.refresh_from_db()
        self.assertEqual(self.artifact.qr_code_svg, '')

    def test_visitor_can_still_scan(self):
        """Scanning stays public — only QR *generation* was restricted."""
        url = reverse('qr_codes:artifact-scan', kwargs={'slug': 'royal-bamoun-throne'})
        resp = self.client.post(url, {'device_type': 'Android'})
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertEqual(QRCodeScan.objects.filter(artifact=self.artifact).count(), 1)

    def test_scan_artifact(self):
        url = reverse('qr_codes:artifact-scan', kwargs={'slug': 'royal-bamoun-throne'})
        resp = self.client.post(url, {
            'device_type': 'Android',
        })
        self.assertEqual(resp.status_code, status.HTTP_201_CREATED)
        self.assertTrue(QRCodeScan.objects.filter(artifact=self.artifact).exists())

    def test_list_scans_requires_manager(self):
        QRCodeScan.objects.create(artifact=self.artifact, device_type='iOS')
        url = reverse('qr_codes:artifact-scans', kwargs={'slug': 'royal-bamoun-throne'})
        
        # Visitor cannot see scans
        self.client.force_authenticate(self.visitor)
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_403_FORBIDDEN)
        
        # Manager can see scans
        self.client.force_authenticate(self.manager)
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(len(resp.data), 1)

    def test_artifact_lookup_by_path(self):
        url = reverse('qr_codes:artifact-lookup')
        resp = self.client.get(url, {'path': '/artifact/royal-bamoun-throne'})
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['title'], 'Royal Bamoun Throne')

    def test_qr_redirect(self):
        url = reverse('qr_codes:qr-redirect', kwargs={'slug': 'royal-bamoun-throne'})
        resp = self.client.get(url)
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertEqual(resp.data['title'], 'Royal Bamoun Throne')
        # Should record a scan
        self.assertEqual(QRCodeScan.objects.count(), 1)


class QRGeneratorTests(APITestCase):
    def test_generate_png(self):
        from .services.qr_generator import get_qr_generator
        
        gen = get_qr_generator()
        png = gen.generate_png('https://africanteller.org/artifact/test')
        self.assertIsInstance(png, bytes)
        self.assertGreater(len(png), 100)

    def test_generate_svg(self):
        from .services.qr_generator import get_qr_generator
        
        gen = get_qr_generator()
        svg = gen.generate_svg('https://africanteller.org/artifact/test')
        self.assertIsInstance(svg, str)
        self.assertIn('<svg', svg)

    def test_generate_data_uri(self):
        from .services.qr_generator import get_qr_generator
        
        gen = get_qr_generator()
        uri = gen.generate_data_uri('https://africanteller.org/artifact/test')
        self.assertTrue(uri.startswith('data:image/png;base64,'))


class CrawlImportTests(TestCase):
    def test_import_uses_short_description_and_keeps_full_story(self):
        full_description = (
            'A carved wooden throne with bronze panels. It was used by Bamoun '
            'kings during public ceremonies.'
        )
        crawl_data = [{
            'id': 'bamoun-bronze-throne',
            'title': 'Bamoun Bronze Throne',
            'category': 'Artifact',
            'location': 'Foumban, West Region',
            'short_description': 'A carved wooden throne with bronze panels.',
            'description': full_description,
            'historical_significance': 'It was used by Bamoun kings during public ceremonies.',
            'images': [],
        }]

        with tempfile.TemporaryDirectory() as directory:
            json_path = Path(directory) / 'crawl.json'
            json_path.write_text(json.dumps(crawl_data), encoding='utf-8')
            call_command(
                'import_crawl_data',
                json_path=str(json_path),
                skip_images=True,
                stdout=StringIO(),
            )

        artifact = Artifact.objects.get(slug='bamoun-bronze-throne')
        self.assertEqual(
            artifact.description,
            'A carved wooden throne with bronze panels.',
        )
        self.assertIn(full_description, artifact.story)
        self.assertIn('Historical Significance', artifact.story)

    def test_import_summarizes_legacy_description_when_short_field_is_missing(self):
        full_description = (
            'A ceremonial drum carved from a single tree trunk. '
            'Its sound traditionally called people together.'
        )
        crawl_data = [{
            'id': 'carved-ceremonial-drum',
            'title': 'Carved Ceremonial Drum',
            'category': 'Artifact',
            'location': 'Bamoun',
            'description': full_description,
            'historical_significance': '',
            'images': [],
        }]

        with tempfile.TemporaryDirectory() as directory:
            json_path = Path(directory) / 'legacy-crawl.json'
            json_path.write_text(json.dumps(crawl_data), encoding='utf-8')
            call_command(
                'import_crawl_data',
                json_path=str(json_path),
                skip_images=True,
                stdout=StringIO(),
            )

        artifact = Artifact.objects.get(slug='carved-ceremonial-drum')
        self.assertEqual(
            artifact.description,
            'A ceremonial drum carved from a single tree trunk.',
        )
        self.assertIn(full_description, artifact.story)


class ArtifactTaxonomyTests(TestCase):
    """Content type and material category are separate vocabularies.

    A carved mask is both `ContentType.ARTIFACT` and `Category.MASK`. The
    importer used to funnel both through one field, which forced a map to
    `other` and left 127 of 134 artifacts unclassified.
    """

    def test_content_type_defaults_to_unknown(self):
        artifact = Artifact.objects.create(
            title='Unclassified thing',
            slug='unclassified-thing',
            description='Something we have not looked at yet.',
        )
        self.assertEqual(artifact.content_type, Artifact.ContentType.UNKNOWN)

    def test_content_type_and_category_are_independent(self):
        artifact = Artifact.objects.create(
            title='Bamoun Royal Mask',
            slug='bamoun-royal-mask-2',
            description='A carved wooden mask with beads.',
            category=Artifact.Category.MASK,
            content_type=Artifact.ContentType.ARTIFACT,
        )
        artifact.refresh_from_db()
        self.assertEqual(artifact.content_type, Artifact.ContentType.ARTIFACT)
        self.assertEqual(artifact.category, Artifact.Category.MASK)

    def test_artifacts_can_be_filtered_by_content_type(self):
        Artifact.objects.create(
            title='Foumban Palace', slug='foumban-palace',
            description='Royal palace.', content_type=Artifact.ContentType.KINGDOM,
        )
        Artifact.objects.create(
            title='Lobe Falls', slug='lobe-falls',
            description='Waterfall.', content_type=Artifact.ContentType.LANDMARK,
        )
        kingdoms = Artifact.objects.filter(content_type=Artifact.ContentType.KINGDOM)
        self.assertEqual([a.slug for a in kingdoms], ['foumban-palace'])


class MaterialClassificationTests(TestCase):
    def test_classifies_distinct_materials(self):
        from .classification import classify_material

        cases = {
            'A carved wooden mask worn at ceremonies.': Artifact.Category.MASK,
            'A talking drum used to call people together.': Artifact.Category.INSTRUMENT,
            'A handwoven cotton wrapper with embroidery.': Artifact.Category.TEXTILE,
            'A terracotta water jar for storing water.': Artifact.Category.POTTERY,
            'A bronze necklace of heavy beads.': Artifact.Category.JEWELRY,
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(classify_material(text), expected)

    def test_unmatched_text_is_other_not_a_guess(self):
        from .classification import classify_material

        self.assertEqual(
            classify_material('Practical advice about electrical outlets.'),
            Artifact.Category.OTHER,
        )

    def test_min_score_rejects_a_single_weak_hit(self):
        from .classification import classify_material

        # "pot" appears once, inside unrelated prose. One hit is not evidence.
        text = 'Visitors are advised to carry drinking water; a pot of palm wine costs little.'
        self.assertEqual(classify_material(text), Artifact.Category.POTTERY)
        self.assertEqual(classify_material(text, min_score=2), Artifact.Category.OTHER)


class CrawlTaxonomyTests(TestCase):
    """resolve_taxonomy: read the crawler's two fields, report what we can't."""

    def _resolve(self, item):
        from .management.commands.import_crawl_data import resolve_taxonomy
        return resolve_taxonomy(item)

    def test_reads_content_type_and_material_type(self):
        content_type, category, problems = self._resolve({
            'content_type': 'Artifact',
            'material_type': 'mask',
            'title': 'Bamoun Royal Mask',
        })
        self.assertEqual(content_type, Artifact.ContentType.ARTIFACT)
        self.assertEqual(category, Artifact.Category.MASK)
        self.assertEqual(problems, [])

    def test_falls_back_to_legacy_category_key_as_content_type(self):
        # Crawl files written before the split used `category` for content type.
        content_type, _, problems = self._resolve({'category': 'Legend', 'title': 'A myth'})
        self.assertEqual(content_type, Artifact.ContentType.LEGEND)
        self.assertEqual(problems, [])

    def test_unreadable_content_type_is_reported_not_guessed(self):
        content_type, _, problems = self._resolve({'category': 'Wibble', 'title': 'x'})
        self.assertEqual(content_type, Artifact.ContentType.UNKNOWN)
        self.assertEqual(len(problems), 1)
        self.assertIn('wibble', problems[0])

    def test_unreadable_material_type_falls_back_to_text_and_still_reports(self):
        content_type, category, problems = self._resolve({
            'material_type': 'wibble',
            'title': 'Carved wooden mask',
            'description': 'A mask worn at ceremonies.',
        })
        self.assertEqual(category, Artifact.Category.MASK)
        self.assertEqual(len(problems), 1)

    def test_missing_material_type_classifies_from_text(self):
        _, category, problems = self._resolve({
            'title': 'Carved wooden mask',
            'description': 'A mask worn at ceremonies.',
        })
        self.assertEqual(category, Artifact.Category.MASK)
        self.assertEqual(problems, [])

    def test_empty_item_is_unknown_other_and_clean(self):
        content_type, category, problems = self._resolve({'title': 'Nothing here'})
        self.assertEqual(content_type, Artifact.ContentType.UNKNOWN)
        self.assertEqual(category, Artifact.Category.OTHER)
        self.assertEqual(problems, [])


class CrawlImportTaxonomyTests(TestCase):
    def _write_crawl(self, payload):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'crawl.json'
        path.write_text(json.dumps(payload), encoding='utf-8')
        return str(path)

    def _item(self, **overrides):
        base = {
            'id': 'some-object',
            'title': 'Some Object',
            'description': 'A carved wooden mask used at ceremonies. ' * 3,
            'historical_significance': '',
            'images': [],
        }
        base.update(overrides)
        return base

    def test_import_stores_both_taxonomies(self):
        path = self._write_crawl([
            self._item(content_type='Artifact', material_type='mask'),
        ])
        call_command('import_crawl_data', json_path=path, skip_images=True, stdout=StringIO())
        artifact = Artifact.objects.get(slug='some-object')
        self.assertEqual(artifact.content_type, Artifact.ContentType.ARTIFACT)
        self.assertEqual(artifact.category, Artifact.Category.MASK)

    def test_import_no_longer_defaults_everything_to_other(self):
        # The regression that motivated the split.
        path = self._write_crawl([
            self._item(id='a-drum', title='Kenkeni drum', material_type='instrument'),
            self._item(id='a-vase', title='Foumban vase', material_type='pottery'),
        ])
        call_command('import_crawl_data', json_path=path, skip_images=True, stdout=StringIO())
        self.assertEqual(Artifact.objects.filter(category=Artifact.Category.OTHER).count(), 0)

    def test_strict_aborts_on_unreadable_value(self):
        from django.core.management.base import CommandError

        path = self._write_crawl([
            self._item(content_type='Wibble'),
            self._item(id='second', title='Second'),
        ])
        with self.assertRaises(CommandError):
            call_command(
                'import_crawl_data', json_path=path, skip_images=True,
                stdout=StringIO(), strict=True,
            )
        # Abort before writing anything, not halfway through.
        self.assertEqual(Artifact.objects.count(), 0)

    def test_non_strict_warns_and_continues(self):
        path = self._write_crawl([
            self._item(content_type='Wibble', material_type='pottery'),
            self._item(id='second', title='Second object', material_type='instrument'),
        ])
        out = StringIO()
        call_command('import_crawl_data', json_path=path, skip_images=True, stdout=out)
        self.assertEqual(Artifact.objects.count(), 2)
        self.assertIn('Unreadable taxonomy values: 1', out.getvalue())
        bad = Artifact.objects.get(slug='some-object')
        self.assertEqual(bad.content_type, Artifact.ContentType.UNKNOWN)
        self.assertEqual(bad.category, Artifact.Category.POTTERY)


class ReclassifyArtifactsTests(TestCase):
    def test_does_not_overwrite_a_curated_category(self):
        curated = Artifact.objects.create(
            title='Bamoun Royal Mask', slug='bamoun-royal-mask',
            description='A carved wooden mask hung with beads and cowries.',
            category=Artifact.Category.MASK,
            content_type=Artifact.ContentType.ARTIFACT,
        )
        call_command('reclassify_artifacts', stdout=StringIO())
        curated.refresh_from_db()
        # Measured corruption before this guard: mask -> jewelry, because the
        # description mentions beads more often than it says "mask".
        self.assertEqual(curated.category, Artifact.Category.MASK)
        self.assertEqual(curated.content_type, Artifact.ContentType.ARTIFACT)

    def test_sets_content_type_on_previously_other_rows(self):
        artifact = Artifact.objects.create(
            title='Lobe Waterfalls', slug='lobe-waterfalls',
            description='A spectacular waterfall and national park.',
            category=Artifact.Category.OTHER,
            content_type=Artifact.ContentType.UNKNOWN,
        )
        call_command('reclassify_artifacts', stdout=StringIO())
        artifact.refresh_from_db()
        self.assertEqual(artifact.content_type, Artifact.ContentType.LANDMARK)

    def test_dry_run_writes_nothing(self):
        artifact = Artifact.objects.create(
            title='Lobe Waterfalls', slug='lobe-waterfalls-dry',
            description='A spectacular waterfall and national park.',
            category=Artifact.Category.OTHER,
            content_type=Artifact.ContentType.UNKNOWN,
        )
        call_command('reclassify_artifacts', dry_run=True, stdout=StringIO())
        artifact.refresh_from_db()
        self.assertEqual(artifact.content_type, Artifact.ContentType.UNKNOWN)

    def test_report_flags_rows_that_are_not_artifacts(self):
        Artifact.objects.create(
            title='Electrical outlets', slug='electrical-outlets',
            description='Voltage and plug types.',
            category=Artifact.Category.OTHER,
        )
        out = StringIO()
        call_command('reclassify_artifacts', stdout=out)
        self.assertIn('not artifacts at all', out.getvalue())
