"""DRF exception handler that keeps database integrity failures out of 500s.

A unique-constraint violation is a *validation* outcome, not a server fault:
the caller sent a value that is already taken. Left alone, DRF's default
handler does not recognise `django.db.IntegrityError`, so it falls through to
Django's 500 page — which hides the real reason from the client and, because
the project does not use `ATOMIC_REQUESTS`, leaves the connection inside a
broken transaction.

The raw driver message is never echoed back: it leaks table and column names.
Only the field name is surfaced, and only when it can be identified safely.
"""

from django.db import IntegrityError
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

# Postgres: 23505 unique_violation. SQLite: 2067/1555.
_UNIQUE_VIOLATION_CODES = {'23505', '2067', '1555'}


def _is_unique_violation(exc: IntegrityError) -> bool:
    """True when the failure is a unique-constraint collision."""
    code = getattr(getattr(exc, '__cause__', None), 'pgcode', None)
    if code:
        return code in _UNIQUE_VIOLATION_CODES
    # SQLite has no SQLSTATE; fall back to the driver's wording.
    message = str(exc).lower()
    return 'unique constraint failed' in message or 'duplicate key' in message


def _offending_field(exc: IntegrityError) -> str | None:
    """Best-effort field name for the response payload.

    Postgres exposes the constraint name on the diagnostics object; SQLite
    spells out `table.column`. Anything unrecognised returns None so the
    caller can fall back to a generic message.
    """
    cause = getattr(exc, '__cause__', None)
    constraint_name = getattr(getattr(cause, 'diag', None), 'constraint_name', None)
    if constraint_name:
        return 'email' if 'email' in constraint_name.lower() else None

    message = str(exc).lower()
    marker = 'unique constraint failed:'
    if marker in message:
        column = message.split(marker, 1)[1].split()[0]
        return column.rsplit('.', 1)[-1] or None
    return None


def api_exception_handler(exc, context):
    """Map an `IntegrityError` to 400; defer everything else to DRF."""
    if isinstance(exc, IntegrityError) and _is_unique_violation(exc):
        field = _offending_field(exc)
        if field:
            detail = {field: ['This value is already in use.']}
        else:
            detail = {'detail': ['That value is already in use.']}
        return Response(detail, status=status.HTTP_400_BAD_REQUEST)

    return drf_exception_handler(exc, context)
