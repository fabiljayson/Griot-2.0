"""Subscriptions API endpoints.

* `GET /api/subscriptions/status/` — the account's entitlement plus the state
  of every premium feature, so the paywall and the feature gates have one
  payload to render from.
* `GET /api/subscriptions/plans/` — the purchasable plans for the paywall.
* `POST /api/subscriptions/checkout/` — the development checkout: a clearly
  labelled stand-in for a payment provider, disabled unless
  `SUBSCRIPTION_DEV_CHECKOUT` is on. It never pretends a real charge happened.
* `POST /api/subscriptions/webhook/` — the RevenueCat store-sync entry point.
  It is deliberately not a user-authenticated endpoint: it is a store calling
  us, and the only token it accepts is the shared webhook secret
  (`REVENUECAT_WEBHOOK_AUTH_TOKEN`), so an ordinary session could never
  deliver a purchase.
"""

import secrets

from django.conf import settings
from django.utils.decorators import method_decorator
from django.views.decorators.csrf import csrf_exempt
from drf_spectacular.utils import (
    OpenApiResponse,
    extend_schema,
    extend_schema_view,
    inline_serializer,
)
from rest_framework import permissions, serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView

from . import services
from .models import SubscriptionPlan
from .serializers import SubscriptionPlanSerializer, SubscriptionStatusSerializer


@extend_schema_view(
    get=extend_schema(
        responses=SubscriptionStatusSerializer,
        summary='Current subscription & premium-feature access',
    ),
)
class SubscriptionStatusView(APIView):
    """The paywall's source of truth for the signed-in reader."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(services.subscription_status(request.user))


@extend_schema_view(
    get=extend_schema(
        responses=SubscriptionPlanSerializer(many=True),
        summary='Purchasable subscription plans',
    ),
)
class SubscriptionPlansView(APIView):
    """The plan shelf: what the paywall offers, priced from the database."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(
            SubscriptionPlanSerializer(
                SubscriptionPlan.objects.filter(is_active=True),
                many=True,
            ).data,
        )


@extend_schema_view(
    post=extend_schema(
        summary='Development checkout',
        description=(
            'Grants one paid period without a payment provider. Disabled '
            'unless `SUBSCRIPTION_DEV_CHECKOUT` is on (off in production). '
            'The 201 body is the standard subscription status payload plus '
            '`payment_reference` and a `notice` stating that no real charge '
            'was processed.'
        ),
        request=inline_serializer(
            'DevCheckoutRequest',
            {'plan': serializers.CharField()},
        ),
        responses={
            201: SubscriptionStatusSerializer,
            400: OpenApiResponse(description='No `plan` key supplied.'),
            403: OpenApiResponse(description='Dev checkout is disabled.'),
            404: OpenApiResponse(description='No such active plan.'),
        },
    ),
)
class DevCheckoutView(APIView):
    """`POST /api/subscriptions/checkout/` — development checkout.

    Body: `{ "plan": "<plan key>" }`.

    Grants one paid period without a payment provider, for development and
    demos only. Refuses with 403 when `SUBSCRIPTION_DEV_CHECKOUT` is off (the
    production default) — the guard is server-side, so no client can talk its
    way into free premium. The response says plainly that no charge occurred.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        if not services.dev_checkout_enabled():
            return Response(
                {
                    'error': 'The development checkout is disabled on this server.',
                    'code': 'dev_checkout_disabled',
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        plan_key = (request.data.get('plan') or '').strip()
        if not plan_key:
            return Response(
                {'error': 'A plan key is required.', 'code': 'plan_required'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            plan = SubscriptionPlan.objects.get(key=plan_key, is_active=True)
        except SubscriptionPlan.DoesNotExist:
            return Response(
                {'error': 'No such plan.', 'code': 'plan_not_found'},
                status=status.HTTP_404_NOT_FOUND,
            )

        payment = services.perform_dev_checkout(request.user, plan)
        payload = services.subscription_status(request.user)
        payload.update(
            {
                'payment_reference': payment.provider_reference,
                'notice': (
                    'Development checkout: no real payment was processed.'
                ),
            }
        )
        return Response(payload, status=status.HTTP_201_CREATED)


@method_decorator(csrf_exempt, name='dispatch')
@extend_schema_view(
    post=extend_schema(
        summary='Apply a RevenueCat webhook event',
        description=(
            'Store sync entry point. Requires the RevenueCat shared secret; '
            'every other caller is answered with 403.'
        ),
        request=None,
        responses={
            200: OpenApiResponse(
                inline_serializer(
                    'WebhookAck',
                    {
                        'received': serializers.BooleanField(),
                        'outcome': serializers.CharField(),
                    },
                ),
                description='Event applied (or deliberately ignored).',
            ),
            403: OpenApiResponse(
                description='Webhooks disabled or invalid/missing token.',
            ),
        },
    ),
)
class RevenueCatWebhookView(APIView):
    """Store webhook: apply purchase lifecycle events to subscription rows.

    Disabled unless `REVENUECAT_WEBHOOK_AUTH_TOKEN` is configured — an empty
    token means the operator has not set the store sync up, and accepting
    unauthenticated webhooks then would hand any caller write access to the
    entitlement table.
    """

    authentication_classes = []  # Store-to-server, not user-to-server.
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        expected = settings.REVENUECAT_WEBHOOK_AUTH_TOKEN
        if not expected:
            return Response(
                {'error': 'Webhooks are not configured on this server.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        supplied = None
        auth = request.headers.get('Authorization') or ''
        if auth.lower().startswith('bearer '):
            supplied = auth[7:].strip()
        else:
            supplied = request.headers.get('X-RevenueCat-Token') or ''
        if not supplied or not secrets.compare_digest(supplied, expected):
            return Response(
                {'error': 'Invalid webhook token.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        payload = request.data or {}
        event = payload.get('event') or {}
        outcome = services.apply_webhook_event(event)
        return Response({'received': True, 'outcome': outcome})