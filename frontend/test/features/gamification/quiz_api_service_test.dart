import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/gamification/services/quiz_api_service.dart';

/// Records every request and replies with a canned payload.
class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this.payload);

  final Object payload;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioFor(_FakeHttpAdapter adapter) {
  return Dio(BaseOptions(baseUrl: 'https://backend.test'))
    ..httpClientAdapter = adapter;
}

/// The story reader looks its quiz up by story, so the list endpoint has to be
/// able to answer for one story instead of forcing the whole catalogue down the
/// wire. These tests pin that request shape and the parsed result.
void main() {
  group('QuizApiService.listQuizzes', () {
    test('narrows the request to a single story', () async {
      final adapter = _FakeHttpAdapter(const {'count': 0, 'results': []});
      final service = QuizApiService(dio: _dioFor(adapter));

      await service.listQuizzes(storyId: 7);

      expect(adapter.requests.single.queryParameters, {'story': 7});
      expect(adapter.requests.single.path, '/api/gamification/quizzes/');
    });

    test('omits the filter when no story is given', () async {
      final adapter = _FakeHttpAdapter(const {'count': 0, 'results': []});
      final service = QuizApiService(dio: _dioFor(adapter));

      await service.listQuizzes();

      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test('parses the catalogue, keeping the story slug', () async {
      final adapter = _FakeHttpAdapter({
        'count': 1,
        'results': [
          {
            'id': 9,
            'title': 'Sacred Forest Wisdom: Foreke-Dschang',
            'story': 1,
            'story_title': 'The Sacred Forest of Foreke-Dschang',
            'story_slug': 'the-sacred-forest-of-foreke-dschang',
            'passing_score': 70,
            'question_count': 4,
            'xp_reward': 90,
            'best_score': null,
          },
        ],
      });
      final service = QuizApiService(dio: _dioFor(adapter));

      final quizzes = await service.listQuizzes();

      expect(quizzes, hasLength(1));
      final quiz = quizzes.single;
      expect(quiz.id, 9);
      expect(quiz.storyId, 1);
      expect(quiz.storySlug, 'the-sacred-forest-of-foreke-dschang');
      expect(quiz.xpReward, 90);
    });

    test('never carries a correct answer back from the API', () async {
      final adapter = _FakeHttpAdapter({
        'id': 9,
        'title': 'Quiz',
        'story': 1,
        'story_slug': 'a-story',
        'questions': [
          {
            'id': 5,
            'question_text': 'What does the lake represent?',
            'option_a': 'Wealth',
            'option_b': 'A test of faith',
            'option_c': 'A fishing spot',
            'option_d': '',
            'difficulty': 'medium',
            'order': 1,
          },
        ],
      });
      final service = QuizApiService(dio: _dioFor(adapter));

      final quiz = await service.getQuiz(9);

      expect(quiz.questions.single.optionB, 'A test of faith');
      // The model has no field for the answer, so a reader cannot be shown it
      // even if the payload were to carry one.
      expect(quiz.questions.single.toString(), isNot(contains('correct')));
    });
  });

  group('QuizApiService attempt flow', () {
    test('submits an answer and returns the server verdict', () async {
      final adapter = _FakeHttpAdapter(const {
        'is_correct': true,
        'correct_answer': 'b',
        'explanation': 'The Bamileke are guardians of the highlands.',
        'answered_count': 1,
        'total_questions': 4,
      });
      final service = QuizApiService(dio: _dioFor(adapter));

      final result = await service.submitAnswer(
        quizId: 9,
        questionId: 5,
        selectedAnswer: 'b',
      );

      expect(result.isCorrect, isTrue);
      expect(result.correctAnswer, 'b');
      expect(result.explanation, contains('Bamileke'));
      expect(adapter.requests.single.data, {
        'question_id': 5,
        'selected_answer': 'b',
      });
    });

    test('finishing an attempt reports the graded score', () async {
      final adapter = _FakeHttpAdapter(const {
        'id': 3,
        'score': 75,
        'correct_count': 3,
        'total_questions': 4,
        'passed': true,
        'xp_earned': 90,
        'status': 'completed',
      });
      final service = QuizApiService(dio: _dioFor(adapter));

      final result = await service.finishQuiz(9);

      expect(result['score'], 75);
      expect(result['passed'], isTrue);
      expect(result['xp_earned'], 90);
    });
  });

  group('QuizApiService.recordActivity', () {
    test('sends the device timezone so the server keeps the right calendar',
        () async {
      final adapter = _FakeHttpAdapter(const {'current_streak': 3});
      final service = QuizApiService(dio: _dioFor(adapter));

      await service.recordActivity(timezone: 'Africa/Douala');

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/gamification/activity/');
      expect(request.data, {'timezone': 'Africa/Douala'});
    });

    test('omits the key entirely when the platform has no zone name', () async {
      final adapter = _FakeHttpAdapter(const {'current_streak': 3});
      final service = QuizApiService(dio: _dioFor(adapter));

      await service.recordActivity();

      // An empty or null zone must not reach the server as a value it would
      // have to reject: leaving it out lets the stored zone stand.
      expect(adapter.requests.single.data, <String, dynamic>{});
    });
  });
}
