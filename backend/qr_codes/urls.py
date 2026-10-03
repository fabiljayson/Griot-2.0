from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

app_name = 'qr_codes'

router = DefaultRouter()
router.register(r'artifacts', views.ArtifactViewSet, basename='artifact')

urlpatterns = [
    # Specific paths BEFORE router (to avoid slug conflicts).
    path(
        'artifacts/lookup/',
        views.ArtifactLookupByDeepLinkView.as_view(),
        name='artifact-lookup',
    ),
    # The admin QR worklist. Registered ahead of the router for the same
    # reason: `artifacts/qr/...` would otherwise be swallowed by the
    # `artifacts/<slug>/` detail route.
    path(
        'artifacts/qr/worklist/',
        views.ArtifactQRWorklistView.as_view(),
        name='artifact-qr-worklist',
    ),
    path(
        'artifacts/qr/worklist/generate/',
        views.ArtifactQRWorklistGenerateView.as_view(),
        name='artifact-qr-worklist-generate',
    ),
    path(
        'qr/<slug:slug>/',
        views.QRCodeRedirectView.as_view(),
        name='qr-redirect',
    ),
    path('', include(router.urls)),
]
