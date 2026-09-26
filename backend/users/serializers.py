from django.contrib.auth import get_user_model
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import UserRole

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    """Public profile representation of a user."""

    role_display = serializers.CharField(source='get_role_display', read_only=True)

    class Meta:
        model = User
        fields = (
            'id',
            'username',
            'email',
            'first_name',
            'last_name',
            'role',
            'role_display',
            'institution',
            'date_joined',
        )
        read_only_fields = ('id', 'date_joined')


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
        return (value or '').strip().lower()

    def find_by_email(self, email):
        """Return the account already holding this email, or None.

        Email is not unique at the database level, so the match is
        case-insensitive on the normalized value.
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
