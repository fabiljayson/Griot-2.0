"""Context processors for the web interface."""

from django.conf import settings
from django.utils import translation


def web_globals(request):
    """Globals every web template can rely on.

    Read-only, deliberately. This processor used to call
    ``WebUserSettings.objects.get_or_create`` for every authenticated request,
    which turns every page view by every signed-in reader into an ``INSERT OR
    IGNORE`` — a write on the hot path, taken while the visitor waits, for a
    row whose defaults the database already supplies. ``WebUserSettings``
    is now written only when someone actually changes a preference (see
    ``web.services.set_language``) or signs in with a preference to restore
    (``web.middleware.WebUserSettingsMiddleware``).
    """
    authenticated = request.user.is_authenticated
    return {
        # The language this request is being rendered in. Templates that need
        # it (the <html lang> attribute, the switcher's current state) read it
        # from here rather than from the database row, because the session is
        # what `LocaleMiddleware` actually acted on and the two can differ for
        # one request — a fresh browser whose stored preference is only
        # applied by middleware after the language was resolved.
        'current_language': translation.get_language(),
        'ui_languages': settings.LANGUAGES,
        'is_authenticated': authenticated,
        'is_contributor_plus': (
            authenticated and request.user.role in ('contributor', 'institution_manager', 'admin')
        ),
        'is_moderator': (
            authenticated and request.user.role in ('institution_manager', 'admin')
        ),
        'GRIOT_APP_NAME': 'Griot AI',
    }