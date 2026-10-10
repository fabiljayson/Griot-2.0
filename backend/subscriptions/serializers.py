"""Serializers for the subscriptions API surface."""

from rest_framework import serializers

from .models import SubscriptionPlan


class SubscriptionPlanSerializer(serializers.ModelSerializer):
    """One purchasable plan for the paywall's plan shelf."""

    class Meta:
        model = SubscriptionPlan
        fields = (
            'key',
            'name',
            'description',
            'price',
            'currency',
            'interval',
            'duration_days',
        )


class FeatureAccessSerializer(serializers.Serializer):
    """One premium feature and whether the requesting account may use it."""

    key = serializers.CharField()
    label = serializers.CharField()
    enabled = serializers.BooleanField()
    has_access = serializers.BooleanField()


class SubscriptionStatusSerializer(serializers.Serializer):
    """`GET /api/subscriptions/status/` — the current entitlement, and the
    paywall state for every configured premium feature.

    `has_access` is already the final verdict (free features included), so a
    client can render the paywall directly from this payload.
    """

    subscribed = serializers.BooleanField()
    entitled = serializers.BooleanField()
    status = serializers.CharField(allow_null=True)
    provider = serializers.CharField(allow_null=True)
    plan = serializers.CharField(allow_null=True, required=False)
    plan_name = serializers.CharField(allow_null=True, required=False)
    # ISO-8601 strings (already formatted server-side); DateTimeField would try
    # to re-parse them and fail on a plain response dict.
    current_period_start = serializers.CharField(
        allow_null=True, required=False,
    )
    current_period_end = serializers.CharField(
        allow_null=True, required=False,
    )
    features = FeatureAccessSerializer(many=True)