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
    path(
        'qr/<slug:slug>/',
        views.QRCodeRedirectView.as_view(),
        name='qr-redirect',
    ),
    path('', include(router.urls)),
]
