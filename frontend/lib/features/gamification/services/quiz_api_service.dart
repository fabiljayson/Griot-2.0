import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import 'gamification_api_service.dart';

/// API service for the gamification backend.
///
/// Quizzes are authored, graded and rewarded server-side: the API never sends
/// `correct_answer` in a question payload, so a reader cannot read the answers
/// out of the response, and XP plus badges are awarded by the same code path
/// that grades the attempt.
///
/// Construct this with the authenticated Dio from
/// `authenticatedApiClientProvider`. Starting, answering and finishing an
/// attempt all require a signed-in user; the bare `ApiClient.instance` has no
/// `AuthInterceptor` and every such call would be rejected with 401.
class QuizApiService {
  QuizApiService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static const _path = '/api/gamification';

  /// Quizzes, optionally narrowed to a single story.
  ///
  /// The story reader only ever needs its own story's quiz, so pass [storyId]
  /// to avoid downloading the whole catalogue. [storyId] is the API's story
  /// id — the same value `StoryModel.id` carries.
  Future<List<QuizModel>> listQuizzes({int? storyId}) async {
    final response = await _dio.get(
      '$_path/quizzes/',
      queryParameters: storyId == null ? null : {'story': storyId},
    );
    final data = response.data as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>?) ?? const [];
    return results
        .map((json) => QuizModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// A quiz with its questions. Correct answers are withheld by the API.
  Future<QuizModel> getQuiz(int quizId) async {
    final response = await _dio.get('$_path/quizzes/$quizId/');
    return QuizModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Log that the reader opened the app today.
  ///
  /// Any activity keeps a streak alive, so the app-open ping is what a reader
  /// who only browses still counts. The server dedupes by the reader's local
  /// calendar day, so calling this on every launch and every resume is safe.
  ///
  /// [timezone] is the device's IANA zone name. The server keeps the streak's
  /// "today" in this zone, so passing it is what stops the streak from rolling
  /// over at the wrong hour for a reader abroad.
  Future<void> recordActivity({String? timezone}) async {
    await _dio.post(
      '$_path/activity/',
      data: {'timezone': ?timezone},
    );
  }

  /// Start (or resume) the current user's attempt at [quizId].
  Future<Map<String, dynamic>> startQuiz(int quizId) async {
    final response = await _dio.post('$_path/quizzes/$quizId/start/');
    return response.data as Map<String, dynamic>;
  }

  /// Grade a single answer server-side and return the verdict.
  Future<QuizAttemptResult> submitAnswer({
    required int quizId,
    required int questionId,
    required String selectedAnswer,
  }) async {
    final response = await _dio.post(
      '$_path/quizzes/$quizId/submit_answer/',
      data: {'question_id': questionId, 'selected_answer': selectedAnswer},
    );
    return QuizAttemptResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// Finish the attempt, returning the graded result (score, pass, XP earned).
  Future<Map<String, dynamic>> finishQuiz(int quizId) async {
    final response = await _dio.post('$_path/quizzes/$quizId/finish/');
    return response.data as Map<String, dynamic>;
  }

  /// The signed-in user's XP, level, streak and quiz progress.
  Future<GamificationProfileModel> getProfile() async {
    final response = await _dio.get('$_path/profile/');
    return GamificationProfileModel.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Badges, flagged with whether the current user has earned each one.
  Future<List<BadgeModel>> listBadges() async {
    final response = await _dio.get('$_path/badges/');
    final data = response.data as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>?) ?? const [];
    return results
        .map((json) => BadgeModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
