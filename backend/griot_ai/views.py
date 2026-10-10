"""`/api/ai/ask/` — grounded question answering.

The single entry point for every client that wants an answer: the Flutter app,
the web UI and the Unity headset. Nothing else in the platform talks to the model
provider, which is why the provider key only has to exist in one place.

Ordering inside `post` is deliberate — validate, resolve, quota, *then* spend:

1. the request is parsed and the subject resolved, so a typo costs nothing;
2. the daily cap is checked before the provider is called, not after;
3. the provider is called exactly once;
4. both messages are written whatever the outcome, so a failure is visible in
   the conversation rather than looking like the reader never asked.
"""

from django.conf import settings
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema, inline_serializer
from rest_framework import generics, serializers, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from media_app.quota import within_daily_cap
from qr_codes.models import Artifact
from stories.models import Story
from subscriptions.services import has_feature_access
from vr.services.experiences import active_experiences

from .models import GriotConversation, GriotMessage
from .serializers import (
    GriotAskRequestSerializer,
    GriotAskResponseSerializer,
    GriotConversationSerializer,
)
from .services.context import build_context
from .services.llm import GriotAIError, get_griot_ai_service


def _error_schema(name: str):
    return inline_serializer(
        name=name,
        fields={
            'error': serializers.CharField(help_text='Human-readable reason.'),
            'code': serializers.CharField(help_text='Stable machine-readable reason.'),
        },
    )


def _error(code: str, message: str, http_status: int) -> Response:
    return Response({'error': message, 'code': code}, status=http_status)


def ai_asks_per_day(user=None) -> int:
    """Rolling-24h ceiling for questions that reached the provider.

    The free cap is `AI_ASKS_PER_USER_PER_DAY`. An entitled account (or
    platform staff) draws from the extended `AI_ASKS_PER_PREMIUM_USER_PER_DAY`
    — the premium half of the freemium split for `advanced_ai`. The check is
    server-side; a client claiming entitlement changes nothing here.
    """
    free_cap = int(getattr(settings, 'AI_ASKS_PER_USER_PER_DAY', 40))
    if user is not None and has_feature_access(user, 'advanced_ai'):
        return int(
            getattr(settings, 'AI_ASKS_PER_PREMIUM_USER_PER_DAY', free_cap * 5)
        )
    return free_cap


def _within_daily_quota(user) -> bool:
    """Count only questions that actually reached the provider.

    A failed ask is stored with an `error_code`, and those rows are excluded —
    otherwise a provider outage would quietly spend every reader's daily
    allowance on requests that never produced an answer.
    """
    answered = GriotMessage.objects.filter(
        conversation__user=user,
        role=GriotMessage.Role.USER,
        error_code='',
    )
    return within_daily_cap(answered, ai_asks_per_day(user))


def _resolve_artifact(key):
    if not key:
        return None
    key = str(key).strip()
    queryset = Artifact.objects.filter(is_published=True)
    if key.isdigit():
        return queryset.filter(pk=int(key)).first()
    return queryset.filter(slug=key).first()


def _resolve_story(key):
    if not key:
        return None
    key = str(key).strip()
    queryset = Story.objects.filter(status=Story.Status.PUBLISHED)
    if key.isdigit():
        return queryset.filter(pk=int(key)).first()
    return queryset.filter(slug=key).first()


def _resolve_experience(key):
    if not key:
        return None
    key = str(key).strip()
    queryset = active_experiences()
    if key.isdigit():
        return queryset.filter(pk=int(key)).first()
    return queryset.filter(slug=key).first()


@extend_schema(
    request=GriotAskRequestSerializer,
    responses={
        200: GriotAskResponseSerializer,
        400: _error_schema('GriotAskBadRequest'),
        429: _error_schema('GriotAskQuotaExceeded'),
        502: _error_schema('GriotAskProviderError'),
        503: _error_schema('GriotAskUnavailable'),
    },
    description=(
        'Ask Griot a question, optionally grounded in an artifact, story or VR '
        'experience. Answers come only from the platform record: when the record '
        'does not cover the question, the answer says so instead of guessing.'
    ),
)
class AskGriotView(APIView):
    """`POST /api/ai/ask/`."""

    permission_classes = [IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'ai_ask'

    def post(self, request):
        serializer = GriotAskRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        artifact = story = experience = None
        if data.get('artifact'):
            artifact = _resolve_artifact(data['artifact'])
            if artifact is None:
                return _error(
                    'unknown_context', 'That artifact is not available.',
                    status.HTTP_400_BAD_REQUEST,
                )
        if data.get('story'):
            story = _resolve_story(data['story'])
            if story is None:
                return _error(
                    'unknown_context', 'That story is not available.',
                    status.HTTP_400_BAD_REQUEST,
                )
        if data.get('experience'):
            experience = _resolve_experience(data['experience'])
            if experience is None:
                return _error(
                    'unknown_context', 'That experience is not available.',
                    status.HTTP_400_BAD_REQUEST,
                )

        # Scoped to the caller: another reader's conversation is a 404, not a
        # 403 that confirms it exists.
        conversation = None
        if data.get('conversation'):
            conversation = get_object_or_404(
                GriotConversation, pk=data['conversation'], user=request.user,
            )

        if not _within_daily_quota(request.user):
            return _error(
                'ai_quota_exceeded',
                'You have reached today’s limit for questions. Try again tomorrow.',
                status.HTTP_429_TOO_MANY_REQUESTS,
            )

        # Artifacts carry no language of their own in this schema (the catalogue
        # is bilingual by field, not per row), so an artifact-only question
        # falls back to English unless the caller names a language.
        language = (
            data.get('language')
            or getattr(story, 'language', '')
            or getattr(experience, 'language', '')
            or 'en'
        )

        context = build_context(
            artifact=artifact, story=story, experience=experience,
        )

        try:
            answer = get_griot_ai_service().answer(
                question=data['question'],
                context_text=context.text,
                language=language,
            )
        except GriotAIError as exc:
            # The question is recorded with the failure so the reader's history
            # shows what happened, and so the same question does not count
            # against their allowance.
            if conversation is None:
                conversation = GriotConversation.objects.create(
                    user=request.user,
                    artifact=artifact,
                    story=story,
                    experience=experience,
                    language=language,
                )
            GriotMessage.objects.create(
                conversation=conversation,
                role=GriotMessage.Role.USER,
                text=data['question'],
                error_code=exc.code,
            )

            http_status = (
                status.HTTP_503_SERVICE_UNAVAILABLE
                if exc.code == 'ai_unavailable'
                else status.HTTP_502_BAD_GATEWAY
            )
            return _error(exc.code, str(exc), http_status)

        if conversation is None:
            conversation = GriotConversation.objects.create(
                user=request.user,
                artifact=artifact,
                story=story,
                experience=experience,
                language=language,
            )

        GriotMessage.objects.create(
            conversation=conversation,
            role=GriotMessage.Role.USER,
            text=data['question'],
        )
        GriotMessage.objects.create(
            conversation=conversation,
            role=GriotMessage.Role.ASSISTANT,
            text=answer.text,
            provider=answer.provider,
            model_name=answer.model_name,
            degraded=answer.degraded,
            latency_ms=answer.latency_ms,
        )
        conversation.save(update_fields=['updated_at'])

        return Response(
            GriotAskResponseSerializer({
                'conversation_id': conversation.pk,
                'answer': answer.text,
                'provider': answer.provider,
                'model_name': answer.model_name,
                'degraded': answer.degraded,
                'latency_ms': answer.latency_ms,
                'sources': context.sources,
            }).data,
        )


@extend_schema(
    responses={200: GriotConversationSerializer},
    description='One conversation and its messages. Owner only.',
)
class GriotConversationDetailView(generics.RetrieveAPIView):
    """`GET /api/ai/conversations/<id>/`."""

    serializer_class = GriotConversationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return (
            GriotConversation.objects.filter(user=self.request.user)
            .prefetch_related('messages')
        )
