"""HTTP tests for `/api/ai/ask/` and conversation reads."""

from unittest.mock import patch

from django.core.cache import cache
from django.test import override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from subscriptions.factories import grant_premium
from vr.factories import make_artifact, make_experience, make_story, make_user, place

from .models import GriotConversation, GriotMessage
from .services.llm import GriotAnswer

ASK_URL = reverse('griot_ai:ask')


class StubService:
    """A provider stub, so the endpoint is tested without a network call."""

    def __init__(self, text='King Njoya commissioned the throne.'):
        self.text = text
        self.calls = []

    def answer(self, *, question, context_text, language='en'):
        self.calls.append({
            'question': question,
            'context_text': context_text,
            'language': language,
        })
        return GriotAnswer(
            text=self.text,
            provider='stub',
            model_name='stub-1',
            degraded=False,
            latency_ms=12,
        )


class AskGriotApiTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = make_user()
        self.other_user = make_user('visitor2')
        self.artifact = make_artifact()
        self.artifact.story = 'Carved from a single piece of iroko.'
        self.artifact.save()
        self.published_story = make_story('Procession', status='published')
        self.artifact.stories.add(self.published_story)
        self.experience = make_experience()
        place(self.experience, self.artifact)
        self.stub = StubService()

    def ask(self, service=None, **body):
        payload = {'question': 'Who carved this?', **body}
        with patch(
            'griot_ai.views.get_griot_ai_service',
            return_value=service or self.stub,
        ):
            return self.client.post(ASK_URL, payload, format='json')

    def test_anonymous_callers_are_refused(self):
        response = self.client.post(ASK_URL, {'question': 'Hello?'}, format='json')

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_a_blank_question_is_a_validation_error(self):
        self.client.force_authenticate(self.user)

        self.assertEqual(
            self.ask(question='').status_code, status.HTTP_400_BAD_REQUEST,
        )

    def test_the_model_receives_the_artifact_record(self):
        self.client.force_authenticate(self.user)

        response = self.ask(artifact=self.artifact.slug)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        sent = self.stub.calls[0]['context_text']
        self.assertIn('Carved from a single piece of iroko.', sent)
        self.assertIn('Procession', sent)

    def test_the_answer_is_returned_with_its_sources(self):
        self.client.force_authenticate(self.user)

        body = self.ask(artifact=self.artifact.slug).json()

        self.assertEqual(body['answer'], 'King Njoya commissioned the throne.')
        self.assertEqual(body['provider'], 'stub')
        self.assertFalse(body['degraded'])
        self.assertEqual(body['sources'][0]['type'], 'artifact')
        self.assertEqual(
            [source['type'] for source in body['sources']],
            ['artifact', 'story'],
        )

    def test_the_question_and_answer_are_recorded(self):
        self.client.force_authenticate(self.user)

        body = self.ask(artifact=self.artifact.slug).json()

        conversation = GriotConversation.objects.get(pk=body['conversation_id'])
        self.assertEqual(conversation.user, self.user)
        self.assertEqual(conversation.artifact, self.artifact)
        roles = list(
            conversation.messages.values_list('role', flat=True)
        )
        self.assertEqual(roles, [GriotMessage.Role.USER, GriotMessage.Role.ASSISTANT])
        answer = conversation.messages.get(role=GriotMessage.Role.ASSISTANT)
        self.assertEqual(answer.provider, 'stub')
        self.assertEqual(answer.latency_ms, 12)

    def test_the_response_never_carries_a_credential(self):
        self.client.force_authenticate(self.user)

        with override_settings(GEMINI_API_KEY='super-secret-key'):
            body = self.ask(artifact=self.artifact.slug).json()

        self.assertNotIn('super-secret-key', repr(body))

    def test_an_unknown_subject_is_rejected_before_the_provider_is_called(self):
        self.client.force_authenticate(self.user)

        response = self.ask(artifact='no-such-artifact')

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.json()['code'], 'unknown_context')
        self.assertEqual(self.stub.calls, [])
        self.assertFalse(GriotMessage.objects.exists())

    def test_an_unpublished_artifact_is_not_a_valid_subject(self):
        draft = make_artifact('Draft Piece', published=False)
        self.client.force_authenticate(self.user)

        response = self.ask(artifact=draft.slug)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_question_may_be_asked_with_no_subject(self):
        self.client.force_authenticate(self.user)

        body = self.ask().json()

        self.assertEqual(body['sources'], [])
        self.assertEqual(self.stub.calls[0]['context_text'], '')

    def test_the_story_language_is_inherited_when_none_is_given(self):
        french = make_story('Procession française', language='fr')
        self.client.force_authenticate(self.user)

        self.ask(story=french.slug)

        self.assertEqual(self.stub.calls[0]['language'], 'fr')

    def test_an_explicit_language_wins(self):
        self.client.force_authenticate(self.user)

        self.ask(story=self.published_story.slug, language='dua')

        self.assertEqual(self.stub.calls[0]['language'], 'dua')

    def test_a_conversation_can_be_continued(self):
        self.client.force_authenticate(self.user)
        first = self.ask(artifact=self.artifact.slug).json()

        second = self.ask(
            artifact=self.artifact.slug, conversation=first['conversation_id'],
        ).json()

        self.assertEqual(second['conversation_id'], first['conversation_id'])
        self.assertEqual(GriotConversation.objects.count(), 1)
        self.assertEqual(GriotMessage.objects.count(), 4)

    def test_continuing_someone_elses_conversation_is_a_404(self):
        self.client.force_authenticate(self.other_user)
        foreign = self.ask(artifact=self.artifact.slug).json()
        self.client.force_authenticate(self.user)

        response = self.ask(
            artifact=self.artifact.slug, conversation=foreign['conversation_id'],
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class AskGriotFailureTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = make_user()
        self.artifact = make_artifact()

    def test_an_unconfigured_deployment_reports_503(self):
        self.client.force_authenticate(self.user)

        with override_settings(GEMINI_API_KEY='', GRIOT_AI_ALLOW_MOCK=False):
            response = self.client.post(
                ASK_URL, {'question': 'Who carved this?'}, format='json',
            )

        self.assertEqual(response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertEqual(response.json()['code'], 'ai_unavailable')

    def test_a_provider_failure_reports_502(self):
        from .services.llm import GriotAIError

        self.client.force_authenticate(self.user)

        with patch(
            'griot_ai.views.get_griot_ai_service',
            side_effect=GriotAIError('boom', code='ai_provider_error'),
        ):
            response = self.client.post(
                ASK_URL, {'question': 'Who carved this?'}, format='json',
            )

        self.assertEqual(response.status_code, status.HTTP_502_BAD_GATEWAY)
        self.assertEqual(response.json()['code'], 'ai_provider_error')

    def test_a_failed_ask_is_recorded_without_an_answer(self):
        self.client.force_authenticate(self.user)

        with override_settings(GEMINI_API_KEY='', GRIOT_AI_ALLOW_MOCK=False):
            self.client.post(ASK_URL, {'question': 'Who?'}, format='json')

        message = GriotMessage.objects.get()
        self.assertEqual(message.role, GriotMessage.Role.USER)
        self.assertEqual(message.error_code, 'ai_unavailable')
        self.assertFalse(
            GriotMessage.objects.filter(role=GriotMessage.Role.ASSISTANT).exists()
        )

    @override_settings(
        AI_ASKS_PER_USER_PER_DAY=1,
        AI_ASKS_PER_PREMIUM_USER_PER_DAY=3,
    )
    def test_an_entitled_account_draws_from_the_extended_allowance(self):
        """The freemium split for `advanced_ai`: the free cap stops a free
        account, while an entitled one keeps going on the premium cap.

        The check runs on the server against the stored subscription — a
        client claiming entitlement changes nothing here.
        """
        grant_premium(self.user)
        self.client.force_authenticate(self.user)
        stub = StubService()

        with patch('griot_ai.views.get_griot_ai_service', return_value=stub):
            first = self.client.post(ASK_URL, {'question': 'One?'}, format='json')
            second = self.client.post(ASK_URL, {'question': 'Two?'}, format='json')

        # A free account with AI_ASKS_PER_USER_PER_DAY=1 is blocked at the
        # second ask (pinned by test_the_daily_allowance_is_enforced).
        self.assertEqual(first.status_code, status.HTTP_200_OK)
        self.assertEqual(second.status_code, status.HTTP_200_OK, second.data)
        self.assertEqual(len(stub.calls), 2)

    @override_settings(AI_ASKS_PER_USER_PER_DAY=1)
    def test_the_daily_allowance_is_enforced(self):
        self.client.force_authenticate(self.user)
        stub = StubService()

        with patch('griot_ai.views.get_griot_ai_service', return_value=stub):
            ok = self.client.post(ASK_URL, {'question': 'One?'}, format='json')
            blocked = self.client.post(ASK_URL, {'question': 'Two?'}, format='json')

        self.assertEqual(ok.status_code, status.HTTP_200_OK)
        self.assertEqual(blocked.status_code, status.HTTP_429_TOO_MANY_REQUESTS)
        self.assertEqual(blocked.json()['code'], 'ai_quota_exceeded')

    @override_settings(AI_ASKS_PER_USER_PER_DAY=1, GEMINI_API_KEY='', GRIOT_AI_ALLOW_MOCK=False)
    def test_a_failed_ask_does_not_spend_the_allowance(self):
        """An outage must not burn the reader's questions for the day."""
        self.client.force_authenticate(self.user)

        first = self.client.post(ASK_URL, {'question': 'One?'}, format='json')
        self.assertEqual(first.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)

        with override_settings(GRIOT_AI_ALLOW_MOCK=True):
            second = self.client.post(ASK_URL, {'question': 'Two?'}, format='json')

        self.assertEqual(second.status_code, status.HTTP_200_OK)


class GriotConversationReadTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = make_user()
        self.other_user = make_user('visitor2')
        self.artifact = make_artifact()
        self.conversation = GriotConversation.objects.create(
            user=self.user, artifact=self.artifact,
        )

    def url(self, conversation=None):
        return reverse('griot_ai:conversation-detail', args=[(conversation or self.conversation).pk])

    def test_the_owner_can_read_the_thread(self):
        GriotMessage.objects.create(
            conversation=self.conversation, role='user', text='Who carved this?',
        )
        self.client.force_authenticate(self.user)

        response = self.client.get(self.url())

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.json()['messages'][0]['text'], 'Who carved this?')

    def test_another_reader_gets_a_404(self):
        self.client.force_authenticate(self.other_user)

        response = self.client.get(self.url())

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_anonymous_callers_are_refused(self):
        self.assertEqual(
            self.client.get(self.url()).status_code,
            status.HTTP_401_UNAUTHORIZED,
        )
