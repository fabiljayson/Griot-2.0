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
        email = (value or '').strip().lower()
        if User.objects.filter(email__iexact=email).exists():
            raise serializers.ValidationError('A user with this email already exists.')
        return email

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
