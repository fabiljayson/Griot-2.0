"""
Web-only middleware.

Kept apart from ``api/middleware.py`` because this one is about the
server-rendered site rather than the JSON API, and because it has to run in a
specific place in the stack — after ``LocaleMiddleware``, which has already
decided this request's language, and after ``AuthenticationMiddleware``, which
is what gives it ``request.user``.
"""

from django.conf import settings
from django.utils import translation

from .services import resolve_ui_language


class WebUserSettingsMiddleware:
    """Restore a signed-in reader's saved interface language.

    ``LocaleMiddleware`` decides a request's language from, in order: the URL
    prefix, the language cookie, the ``Accept-Language`` header, then
    ``LANGUAGE_CODE``. The cookie is per-browser and it is the only one of
    those we can write from a template. So a reader who chose French on their
    phone and then opens the site in a fresh browser arrives with no cookie at
    all and is served English — the preference is stored in
    ``WebUserSettings`` exactly as its docstring promises, and nothing ever
    reads it back.

    This copies that stored preference into the cookie the first time a
    browser is seen without one, which is all it takes: afterwards the cookie
    is present and the lookup is skipped. Cost is one query per browser rather
    than one per request.

    Two rules keep it from being a way to be sent somewhere unexpected:

    * only when the cookie is absent, so an explicit choice made on this
      device (or an ``Accept-Language`` match) is never overridden;
    * ``resolve_ui_language`` is applied to whatever was stored, so a row left
      behind by an older build holding a code this project cannot render
      falls back to English instead of activating a language with no
      catalogue.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        user = getattr(request, 'user', None)
        if (
            user is not None
            and user.is_authenticated
            and not request.COOKIES.get(settings.LANGUAGE_COOKIE_NAME)
        ):
            from .models import WebUserSettings

            stored = (
                WebUserSettings.objects.filter(user=user)
                .values_list('language', flat=True)
                .first()
            )
            if stored:
                code = resolve_ui_language(stored)
                request.COOKIES[settings.LANGUAGE_COOKIE_NAME] = code
                translation.activate(code)
                response = self.get_response(request)
                response.set_cookie(
                    settings.LANGUAGE_COOKIE_NAME,
                    code,
                    max_age=settings.LANGUAGE_COOKIE_AGE,
                    path=settings.LANGUAGE_COOKIE_PATH,
                    domain=settings.LANGUAGE_COOKIE_DOMAIN,
                    secure=settings.LANGUAGE_COOKIE_SECURE,
                    httponly=settings.LANGUAGE_COOKIE_HTTPONLY,
                    samesite=settings.LANGUAGE_COOKIE_SAMESITE,
                )
                return response
        return self.get_response(request)