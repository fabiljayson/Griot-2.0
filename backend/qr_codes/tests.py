from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .models import Artifact, QRCodeScan

User = get_user_model()


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
        url = reverse('qr_codes:artifact-generate-qr', kwargs={'slug': 'royal-bamoun-throne'})
        resp = self.client.post(url, {
            'format': 'svg',
            'foreground': '#C85A32',
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertIn('svg', resp.data)
        self.assertIn('deep_link', resp.data)
        self.assertIn('africanteller.org', resp.data['deep_link'])

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
