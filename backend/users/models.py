from django.contrib.auth.models import AbstractUser
from django.db import models
from django.db.models.functions import Lower


class UserRole(models.TextChoices):
    """Application-level roles for the African Teller platform."""

    VISITOR = 'visitor', 'Visitor'
    CONTRIBUTOR = 'contributor', 'Contributor'
    INSTITUTION_MANAGER = 'institution_manager', 'Institution Manager'
    ADMIN = 'admin', 'Admin'


class User(AbstractUser):
    """Custom user model with platform roles (Task 2.1).

    Roles:
      - Visitor          — browse, read, and listen (Explorer Mode)
      - Contributor      — submit stories, notes, and cultural research
      - InstitutionManager — manage museum artifacts & QR code engines
      - Admin            — full platform administration

    Note: `role` is the *application* role. `is_staff`/`is_superuser`
    remain Django-level flags for accessing the Django admin site.
    """

    role = models.CharField(
        max_length=24,
        choices=UserRole.choices,
        default=UserRole.VISITOR,
        help_text='Application role controlling what the account can do.',
    )

    # Optional for Institution Managers (museum / archive name).
    institution = models.CharField(
        max_length=120,
        blank=True,
        default='',
        help_text='Affiliated museum, archive, or institution (managers).',
    )

    class Meta(AbstractUser.Meta):
        constraints = [
            # Every email lookup in the codebase uses `email__iexact`, so the
            # constraint has to be case-insensitive too — otherwise
            # `A@x.com` and `a@x.com` both insert and the address becomes
            # unusable. Blank emails are exempt because the column is
            # `blank=True` and several users may legitimately have none.
            models.UniqueConstraint(
                Lower('email'),
                condition=~models.Q(email=''),
                name='uniq_user_email_case_insensitive',
            ),
        ]

    # --- Role helpers -------------------------------------------------------

    @property
    def role_display(self) -> str:
        return self.get_role_display()

    @property
    def is_visitor(self) -> bool:
        return self.role == UserRole.VISITOR

    @property
    def is_contributor(self) -> bool:
        return self.role == UserRole.CONTRIBUTOR

    @property
    def is_institution_manager(self) -> bool:
        return self.role == UserRole.INSTITUTION_MANAGER

    @property
    def is_admin_role(self) -> bool:
        return self.role == UserRole.ADMIN

    def __str__(self) -> str:
        return self.username
