from rest_framework import serializers

from .models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    """An inbox message as the client needs it to render a row.

    ``is_read`` is writable so a row can be marked read by tapping it, but the
    timestamp is not: the server owns when a message was opened, and a client
    that could set it could backdate its own history.
    """

    class Meta:
        model = Notification
        fields = (
            'id',
            'kind',
            'title',
            'body',
            'story',
            'story_title',
            'story_slug',
            'is_read',
            'read_at',
            'created_at',
        )
        read_only_fields = ('id', 'kind', 'title', 'body', 'story',
                            'story_title', 'story_slug', 'read_at', 'created_at')

    def validate_is_read(self, value):
        # Un-marking a message is not supported: the inbox is a log, and letting
        # a client re-open an old message would make the unread count flicker.
        if value is False:
            raise serializers.ValidationError('A notification cannot be unread.')
        return value


class MarkReadSerializer(serializers.Serializer):
    """Payload for the mark-as-read endpoint."""

    is_read = serializers.BooleanField(default=True)
