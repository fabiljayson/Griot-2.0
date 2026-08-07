from django.contrib.auth.models import AbstractUser
from django.db import models


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
