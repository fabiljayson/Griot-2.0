"""Guards for management commands that must never run against production.

Several seeders create accounts with well-known credentials (a demo admin
password, a local database's superuser rows). Those are fine on a developer
machine and catastrophic on a hosted database, and a printed warning is not a
control -- the command has no way to tell "someone ran this locally" from
"someone pointed DATABASE_URL at production and ran the same command".

`assert_safe_environment` is the shared precondition. It allow-lists the
settings modules that may run an unsafe command, so the check fails *closed*:
an unknown or new settings module is treated as production until someone
deliberately adds it to the list.
"""

import os

from django.conf import settings
from django.core.management.base import CommandError

#: Settings modules under which an unsafe seeder is allowed to run. Anything
#: not listed -- `config.settings.prod` included -- is refused.
SAFE_SETTINGS_MODULES = frozenset({
    'config.settings.dev',
    'config.settings.test',
})

#: Escape hatch for staging environments that intentionally run the demo seed.
#: It restores the ability to run the command, but never the ability to invent
#: a password: see `require_explicit_password`.
OVERRIDE_ENV_VAR = 'GRIOT_ALLOW_UNSAFE_COMMANDS'

#: Password the seeders fall back to when none is supplied. Recognised so it
#: can be rejected outright rather than silently used.
INSECURE_DEFAULT_PASSWORD = 'demo12345'


def settings_module_name() -> str:
    """The dotted settings module this process is running under."""
    return getattr(settings, 'SETTINGS_MODULE', '') or ''


def is_production() -> bool:
    """True unless the active settings module is explicitly a safe one."""
    return settings_module_name() not in SAFE_SETTINGS_MODULES


def override_enabled() -> bool:
    return os.environ.get(OVERRIDE_ENV_VAR, '').strip().lower() in {
        '1', 'true', 'yes',
    }


def assert_safe_environment(command: str, *, reason: str) -> None:
    """Abort unless `command` is running somewhere it cannot do damage.

    `reason` is appended to the error so whoever ran the command learns what
    the guard is protecting, rather than only that they were stopped.
    """
    if not is_production():
        return

    if not override_enabled():
        raise CommandError(
            f'Refusing to run "{command}" under settings module '
            f'"{settings_module_name()}": {reason}\n'
            f'This command is only allowed under: '
            f'{", ".join(sorted(SAFE_SETTINGS_MODULES))}.\n'
            f'If this really is a disposable staging database, set '
            f'{OVERRIDE_ENV_VAR}=1 and re-run.'
        )


def require_explicit_password(command: str, password: str | None) -> str:
    """Return the password to use, or refuse if none was supplied.

    Called on the override path: opting in to running the command in a hosted
    environment must never also mean accepting a password that is published in
    this repository.
    """
    if not password:
        raise CommandError(
            f'"{command}" requires an explicit --password under '
            f'"{settings_module_name()}". The built-in demo password '
            f'("{INSECURE_DEFAULT_PASSWORD}") is refused here because this '
            f'database is reachable from outside the developer machine.'
        )
    if password == INSECURE_DEFAULT_PASSWORD:
        raise CommandError(
            f'"{command}" refuses the well-known demo password. Pass a '
            f'different --password.'
        )
    return password
