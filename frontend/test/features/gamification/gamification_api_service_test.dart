import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/database/repositories/local_gamification_repository.dart';
import 'package:griot_ai/features/gamification/services/gamification_api_service.dart';
import 'package:griot_ai/features/gamification/services/quiz_api_service.dart';

class _MockLocalRepository extends Mock
    implements LocalGamificationRepository {}

/// Replies with [payload], or fails with [statusCode] when one is given.
class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter({this.payload, this.statusCode = 200, this.fail = false});

  final Object? payload;
  final int statusCode;

  /// Simulate the request never reaching the server.
  final bool fail;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fail) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'network unreachable',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(payload),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The quizzes a reader sees must come from the API, which owns the authoritative
/// quiz for every published story and grades attempts server-side. The bundled
/// offline catalogue covers a different set of stories, so serving it while the
/// API is reachable is what left production showing the wrong quiz — or none at
/// all — for every real story.
void main() {
  late _MockLocalRepository local;

  setUp(() => local = _MockLocalRepository());

  GamificationApiService serviceWith(_FakeHttpAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://backend.test'))
      ..httpClientAdapter = adapter;
    return GamificationApiService(
      local: local,
      remote: QuizApiService(dio: dio),
    );
  }

  test('serves quizzes from the API while it is reachable', () async {
    when(() => local.listQuizzes()).thenAnswer((_) async => const []);
    final service = serviceWith(
      _FakeHttpAdapter(
        payload: {
          'count': 1,
          'results': [
            {
              'id': 42,
              'title': 'From the API',
              'story': 1,
              'story_slug': 'a-story',
              'question_count': 4,
            },
          ],
        },
      ),
    );

    final quizzes = await service.listQuizzes();

    expect(quizzes.single.id, 42);
    verifyNever(() => local.listQuizzes());
  });

  test(
    'falls back to the offline catalogue when the API is unreachable',
    () async {
      when(() => local.listQuizzes()).thenAnswer(
        (_) async => [const QuizModel(id: 1, title: 'From the bundle')],
      );
      final service = serviceWith(_FakeHttpAdapter(fail: true));

      final quizzes = await service.listQuizzes();

      expect(quizzes.single.title, 'From the bundle');
      verify(() => local.listQuizzes()).called(1);
    },
  );

  test('uses the local catalogue when no remote is configured', () async {
    when(
      () => local.getQuiz(any()),
    ).thenAnswer((_) async => const QuizModel(id: 3, title: 'Offline only'));
    final service = GamificationApiService(local: local);

    expect((await service.getQuiz(3)).title, 'Offline only');
  });

  test('respects a real answer from the server instead of substituting a '
      'bundled quiz', () async {
    when(() => local.listQuizzes()).thenAnswer((_) async => const []);
    final service = serviceWith(
      _FakeHttpAdapter(
        payload: const {'detail': 'Not found.'},
        statusCode: 404,
      ),
    );

    // The server said this story has no quiz. Falling back here would offer the
    // reader an unrelated bundled quiz, which is the bug this guards.
    expect(
      () => service.listQuizzes(storyId: 999),
      throwsA(isA<DioException>()),
    );
    verifyNever(() => local.listQuizzes());
  });

  group('attempt grading', () {
    test('grades answers on the server, never locally', () async {
      final service = serviceWith(
        _FakeHttpAdapter(
          payload: const {
            'is_correct': false,
            'correct_answer': 'c',
            'explanation': 'The lake is sacred to the Dschang people.',
            'answered_count': 2,
            'total_questions': 4,
          },
        ),
      );

      final result = await service.submitAnswer(
        quizId: 42,
        questionId: 7,
        selectedAnswer: 'a',
      );

      expect(result.isCorrect, isFalse);
      expect(result.correctAnswer, 'c');
      expect(result.totalQuestions, 4);
    });
  });
}
