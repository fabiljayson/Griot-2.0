"""Unit tests for the Griot AI provider adapter and context builder."""

import json
from unittest.mock import Mock, patch

from django.test import TestCase, override_settings

from .services.context import build_context
from .services.llm import (
    PROVIDER_GEMINI,
    PROVIDER_MOCK,
    GeminiGriotAIService,
    GriotAIError,
    MockGriotAIService,
    build_prompt,
    get_griot_ai_service,
)


class PromptTests(TestCase):
    def test_prompt_delimits_context_from_the_question(self):
        prompt = build_prompt(
            question='Who carved the throne?',
            context_text='[Artifact #1 — Throne]\nCarved for King Njoya.',
            language='en',
        )

        self.assertIn('CONTEXT', prompt)
        self.assertIn('READER QUESTION', prompt)
        self.assertLess(prompt.index('Carved for King Njoya'), prompt.index('Who carved'))
        self.assertIn('en', prompt)

    def test_an_empty_retrieval_is_stated_rather_than_left_blank(self):
        prompt = build_prompt(question='Anything?', context_text='', language='fr')

        self.assertIn('no record was retrieved', prompt)
        self.assertIn('fr', prompt)


class ContextBuilderTests(TestCase):
    def setUp(self):
        from vr.factories import make_artifact, make_story

        self.make_artifact = make_artifact
        self.make_story = make_story
        self.artifact = make_artifact()

    def test_artifact_text_is_included_and_cited(self):
        self.artifact.story = 'Carved from a single piece of iroko.'
        self.artifact.historical_significance = 'Used at royal enthronements.'
        self.artifact.save()

        context = build_context(artifact=self.artifact)

        self.assertIn('Royal Bamoun Throne', context.text)
        self.assertIn('Carved from a single piece of iroko.', context.text)
        self.assertIn('Used at royal enthronements.', context.text)
        self.assertEqual(context.sources[0]['type'], 'artifact')
        self.assertEqual(context.sources[0]['url'], f'/artifact/{self.artifact.slug}/')

    def test_unpublished_stories_are_not_grounding(self):
        published = self.make_story('Procession', status='published')
        draft = self.make_story('Unfinished', status='draft')
        self.artifact.stories.set([published, draft])

        context = build_context(artifact=self.artifact)

        self.assertIn('Procession', context.text)
        self.assertNotIn('Unfinished', context.text)
        self.assertNotIn(
            draft.pk,
            [source['id'] for source in context.sources if source['type'] == 'story'],
        )

    def test_context_stops_at_the_budget(self):
        self.artifact.story = 'x' * 20000
        self.artifact.save()

        context = build_context(artifact=self.artifact, max_chars=1200)

        self.assertLess(len(context.text), 20000)
        self.assertIn('not shown', context.text)

    def test_no_subject_means_no_context(self):
        context = build_context()

        self.assertTrue(context.is_empty)
        self.assertEqual(context.sources, [])

    def test_a_story_subject_is_citable_on_its_own(self):
        story = self.make_story('Procession')

        context = build_context(story=story)

        self.assertIn('Procession', context.text)
        self.assertEqual(context.sources[0]['url'], f'/story/{story.slug}/')


class GeminiServiceTests(TestCase):
    def setUp(self):
        self.service = GeminiGriotAIService('test-key', model='gemini-test')

    def _response(self, payload, status_code=200):
        response = Mock()
        response.status_code = status_code
        response.json.return_value = payload
        response.text = json.dumps(payload)
        return response

    def _envelope(self, text):
        return {'candidates': [{'content': {'parts': [{'text': text}]}}]}

    @patch('griot_ai.services.llm.requests.post')
    def test_an_answer_is_parsed_and_attributed(self, post):
        post.return_value = self._response(self._envelope('King Njoya commissioned it.'))

        answer = self.service.answer(question='Who?', context_text='ctx', language='en')

        self.assertEqual(answer.text, 'King Njoya commissioned it.')
        self.assertEqual(answer.provider, PROVIDER_GEMINI)
        self.assertEqual(answer.model_name, 'gemini-test')
        self.assertFalse(answer.degraded)

    @patch('griot_ai.services.llm.requests.post')
    def test_the_api_key_is_sent_in_a_header_not_the_url(self, post):
        post.return_value = self._response(self._envelope('ok'))

        self.service.answer(question='Who?', context_text='ctx')

        _, kwargs = post.call_args
        self.assertEqual(kwargs['headers']['x-goog-api-key'], 'test-key')
        self.assertNotIn('test-key', kwargs.get('url', '') or '')
        self.assertNotIn('test-key', post.call_args[0][0])

    @patch('griot_ai.services.llm.requests.post')
    def test_the_system_prompt_forbids_answer_from_general_knowledge(self, post):
        post.return_value = self._response(self._envelope('ok'))

        self.service.answer(question='Who?', context_text='ctx')

        body = json.loads(post.call_args[1]['data'])
        instruction = body['systemInstruction']['parts'][0]['text']
        self.assertIn('Answer only from the CONTEXT', instruction)
        self.assertIn('Never invent', instruction)

    @patch('griot_ai.services.llm.requests.post')
    def test_a_rejected_request_raises_a_typed_error(self, post):
        post.return_value = self._response({'error': {'message': 'bad key'}}, status_code=403)

        with self.assertRaises(GriotAIError) as caught:
            self.service.answer(question='Who?', context_text='ctx')

        self.assertEqual(caught.exception.code, 'ai_provider_error')

    @patch('griot_ai.services.llm.requests.post')
    def test_unreadable_and_empty_responses_are_distinguished(self, post):
        post.return_value = Mock(status_code=200, text='not json')
        post.return_value.json.side_effect = ValueError('no json')

        with self.assertRaises(GriotAIError) as caught:
            self.service.answer(question='Who?', context_text='ctx')
        self.assertEqual(caught.exception.code, 'ai_provider_malformed')

        post.return_value = self._response({'candidates': []})
        with self.assertRaises(GriotAIError) as caught:
            self.service.answer(question='Who?', context_text='ctx')
        self.assertEqual(caught.exception.code, 'ai_provider_empty')

    @patch('griot_ai.services.llm.requests.post')
    def test_a_transport_failure_is_typed(self, post):
        import requests

        post.side_effect = requests.ConnectionError('no route to host')

        with self.assertRaises(GriotAIError) as caught:
            self.service.answer(question='Who?', context_text='ctx')

        self.assertEqual(caught.exception.code, 'ai_provider_unreachable')


class ServiceFactoryTests(TestCase):
    @override_settings(GEMINI_API_KEY='live-key', GRIOT_AI_ALLOW_MOCK=False)
    def test_a_configured_key_selects_the_live_client(self):
        self.assertIsInstance(get_griot_ai_service(), GeminiGriotAIService)

    @override_settings(GEMINI_API_KEY='', GRIOT_AI_ALLOW_MOCK=True)
    def test_development_falls_back_to_the_mock(self):
        self.assertIsInstance(get_griot_ai_service(), MockGriotAIService)

    @override_settings(GEMINI_API_KEY='', GRIOT_AI_ALLOW_MOCK=False)
    def test_a_production_deploy_with_no_key_refuses_rather_than_faking(self):
        with self.assertRaises(GriotAIError) as caught:
            get_griot_ai_service()

        self.assertEqual(caught.exception.code, 'ai_unavailable')

    def test_the_mock_never_passes_itself_off_as_an_answer(self):
        answer = MockGriotAIService().answer(
            question='Who carved it?',
            context_text='[Artifact #108 — Traditional Mask]',
        )

        self.assertTrue(answer.degraded)
        self.assertEqual(answer.provider, PROVIDER_MOCK)
        self.assertIn('not a real answer', answer.text)
