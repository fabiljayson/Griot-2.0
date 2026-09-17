"""Context processors for the web interface."""

from django.conf import settings


def web_globals(request):
    """Globals every web template can rely on."""
    authenticated = request.user.is_authenticated
    web_settings = getattr(request, 'griot_web_settings', None)
    if authenticated and web_settings is None:
        from web.models import WebUserSettings
        web_settings, _ = WebUserSettings.objects.get_or_create(user=request.user)
    return {
        'web_settings': web_settings,
        'is_authenticated': authenticated,
        'is_contributor_plus': (
            authenticated and request.user.role in ('contributor', 'institution_manager', 'admin')
        ),
        'is_moderator': (
            authenticated and request.user.role in ('institution_manager', 'admin')
        ),
        'GRIOT_APP_NAME': 'Griot AI',
    }
