from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import UserRole

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    """Public profile representation of a user.

    Deliberately excludes ``email``. This serializer is nested inside the story
    list, story detail and story-flag responses, all of which are served to
    anonymous readers — including it turned the stories API into a scrapable
    directory of contributor addresses. The email is available to its owner
    through :class:`PrivateUserSerializer`, and nowhere else.
    """

    role_display = serializers.CharField(source='get_role_display', read_only=True)

    class Meta:
        model = User
        fields = (
            'id',
            'username',
            'first_name',
            'last_name',
            'role',
            'role_display',
            'institution',
            'date_joined',
        )
        read_only_fields = ('id', 'username', 'date_joined')


class PrivateUserSerializer(UserSerializer):
    """The authenticated user's own record, including their email.

    Used only for ``/api/users/me/`` and the auth responses, where the reader
    is asking about themselves. Inheriting from :class:`UserSerializer` keeps
    the public shape identical plus this one field, so the two cannot drift.
    """

    class Meta(UserSerializer.Meta):
        fields = UserSerializer.Meta.fields + ('email',)
        # Writable by the owner: changing your own address is legitimate.
        read_only_fields = ('id', 'username', 'date_joined')


class RegisterSerializer(serializers.ModelSerializer):
    """Create a new account.

    Self-service registration allows the Visitor and Contributor roles.
    InstitutionManager and Admin roles are granted by an administrator and
    cannot be self-assigned.
    """

    password = serializers.CharField(
        write_only=True,
        min_length=8,
        trim_whitespace=False,
        style={'input_type': 'password'},
    )
    role = serializers.ChoiceField(
        choices=[UserRole.VISITOR, UserRole.CONTRIBUTOR],
        default=UserRole.VISITOR,
    )

    class Meta:
        model = User
        fields = (
            'username',
            'email',
            'password',
            'first_name',
            'last_name',
            'role',
        )

    def validate_email(self, value: str) -> str:
        return self.normalize_email(value)

    @staticmethod
    def normalize_email(value) -> str:
        if not isinstance(value, str):
            return ''
        return value.strip().lower()

    def find_by_email(self, email):
        """Return the account already holding this email, or None.

        Email is not unique at the database level, so the match is
        case-insensitive on the normalized value. A non-string input is treated
        as "no address" rather than normalized, so a caller that reaches here
        before validation cannot turn a malformed body into an exception.
        """
        email = self.normalize_email(email)
        if not email:
            return None
        return User.objects.filter(email__iexact=email).first()

    def is_verbatim_replay(self, user, *, username, password) -> bool:
        """True when this request repeats an already-committed registration.

        The client re-sends the same body when the response outlasts its
        timeout, which happens routinely while the hosted backend cold-starts.
        Treating that replay as the same request keeps the account usable; a
        mismatched username or password is a genuine conflict and must not be
        treated as a replay.
        """
        if user is None:
            return False
        return user.username == (username or '').strip() and user.check_password(
            password or ''
        )

    def validate_password(self, value: str) -> str:
        """Run the project's real password policy.

        ``min_length=8`` on the field was the only check in force, so every
        password in the common-breach list was accepted over the API even
        though ``AUTH_PASSWORD_VALIDATORS`` is configured in settings. Delegate
        to Django so this path enforces the same policy as the web form.
        """
        try:
            validate_password(value)
        except DjangoValidationError as exc:
            raise serializers.ValidationError(list(exc.messages)) from exc
        return value

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user


class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    """JWT that embeds the user's platform role for client-side checks."""

    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token['role'] = user.role
        token['username'] = user.username
        return token
