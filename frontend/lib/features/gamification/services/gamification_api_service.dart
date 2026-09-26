import 'package:dio/dio.dart';

import '../../../core/database/repositories/local_gamification_repository.dart';
import 'quiz_api_service.dart';

/// Quiz question model.
class QuizQuestionModel {
  const QuizQuestionModel({
    required this.id,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    this.optionD = '',
    this.difficulty = 'medium',
  });

  final int id;
  final String questionText;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String difficulty;

  factory QuizQuestionModel.fromJson(Map<String, dynamic> json) {
    return QuizQuestionModel(
      id: json['id'] as int? ?? 0,
      questionText: json['question_text'] as String? ?? '',
      optionA: json['option_a'] as String? ?? '',
      optionB: json['option_b'] as String? ?? '',
      optionC: json['option_c'] as String? ?? '',
      optionD: json['option_d'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? 'medium',
    );
  }

  List<String> get options => [
    optionA,
    optionB,
    optionC,
    if (optionD.isNotEmpty) optionD,
  ];
}

/// Quiz model.
class QuizModel {
  const QuizModel({
    required this.id,
    this.title = '',
    this.description = '',
    this.storyId = 0,
    this.storyTitle = '',
    this.storySlug = '',
    this.passingScore = 70,
    this.timeLimitMinutes = 0,
    this.questionCount = 0,
    this.xpReward = 0,
    this.questions = const [],
    this.bestScore,
  });

  final int id;
  final String title;
  final String description;
  final int storyId;
  final String storyTitle;

  /// Slug of the story this quiz belongs to.
  ///
  /// Ids are only meaningful within one data source: the offline SQLite
  /// catalogue numbers its own stories independently of the API, so matching a
  /// quiz to a story by id alone can pair the wrong quiz with a story. The slug
  /// is stable across both.
  final String storySlug;
  final int passingScore;
  final int timeLimitMinutes;
  final int questionCount;
  final int xpReward;
  final List<QuizQuestionModel> questions;
  final int? bestScore;

  factory QuizModel.fromJson(Map<String, dynamic> json) {
    return QuizModel(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      storyId: json['story'] as int? ?? 0,
      storyTitle: json['story_title'] as String? ?? '',
      storySlug: json['story_slug'] as String? ?? '',
      passingScore: json['passing_score'] as int? ?? 70,
      timeLimitMinutes: json['time_limit_minutes'] as int? ?? 0,
      questionCount: json['question_count'] as int? ?? 0,
      xpReward: json['xp_reward'] as int? ?? 0,
      questions:
          (json['questions'] as List<dynamic>?)
              ?.map(
                (q) => QuizQuestionModel.fromJson(q as Map<String, dynamic>),
              )
              .toList() ??
          [],
      bestScore: json['best_score'] as int?,
    );
  }
}

/// Badge model.
class BadgeModel {
  const BadgeModel({
    required this.id,
    required this.name,
    required this.slug,
    this.description = '',
    this.emoji = '🏆',
    this.category = 'reading',
    this.xpRequired = 0,
    this.color = '#C85A32',
    this.isSecret = false,
    this.earned = false,
  });

  final int id;
  final String name;
  final String slug;
  final String description;
  final String emoji;
  final String category;
  final int xpRequired;
  final String color;
  final bool isSecret;
  final bool earned;

  factory BadgeModel.fromJson(Map<String, dynamic> json) {
    return BadgeModel(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      description: json['description'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '🏆',
      category: json['category'] as String? ?? 'reading',
      xpRequired: json['xp_required'] as int? ?? 0,
      color: json['color'] as String? ?? '#C85A32',
      isSecret: json['is_secret'] as bool? ?? false,
      earned: json['earned'] as bool? ?? false,
    );
  }
}

/// User profile model.
class GamificationProfileModel {
  const GamificationProfileModel({
    this.username = '',
    this.totalXp = 0,
    this.level = 1,
    this.storiesRead = 0,
    this.storiesCompleted = 0,
    this.quizzesPassed = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.activeToday = false,
    this.lastActiveDate,
    this.timezone = 'Africa/Douala',
    this.xpForNextLevel = 100,
    this.xpProgress = 0.0,
    this.badgesCount = 0,
    this.recentBadges = const [],
  });

  final String username;
  final int totalXp;
  final int level;
  final int storiesRead;
  final int storiesCompleted;
  final int quizzesPassed;
  /// The streak still standing today, which the API reports as 0 once a day
  /// has been missed. It is not the raw stored run: a reader who last opened
  /// the app three weeks ago has no current streak, whatever the database
  /// still remembers about their best run.
  final int currentStreak;

  /// The reader's longest run ever, which does not decay.
  final int longestStreak;

  /// Whether today already counts towards the streak. False with a non-zero
  /// [currentStreak] means the run is still alive but expires at the reader's
  /// midnight — the case the "keep it alive" prompt is for.
  final bool activeToday;

  /// The reader's last active day as `yyyy-MM-dd`, or null if never active.
  final DateTime? lastActiveDate;

  /// The IANA zone the server decides "today" in.
  final String timezone;
  final int xpForNextLevel;
  final double xpProgress;
  final int badgesCount;
  final List<dynamic> recentBadges;

  /// Parses the API's `yyyy-MM-dd` day, tolerating both string and epoch forms.
  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
    }
    return DateTime.tryParse(raw as String);
  }

  factory GamificationProfileModel.fromJson(Map<String, dynamic> json) {
    return GamificationProfileModel(
      username: json['username'] as String? ?? '',
      totalXp: json['total_xp'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      storiesRead: json['stories_read'] as int? ?? 0,
      storiesCompleted: json['stories_completed'] as int? ?? 0,
      quizzesPassed: json['quizzes_passed'] as int? ?? 0,
      currentStreak: json['current_streak'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      activeToday: json['active_today'] as bool? ?? false,
      lastActiveDate: _parseDate(json['last_active_date'] as String?),
      timezone: json['timezone'] as String? ?? 'Africa/Douala',
      xpForNextLevel: json['xp_for_next_level'] as int? ?? 100,
      xpProgress: (json['xp_progress'] as num?)?.toDouble() ?? 0.0,
      badgesCount: json['badges_count'] as int? ?? 0,
      recentBadges: json['recent_badges'] as List<dynamic>? ?? [],
    );
  }
}

/// Quiz attempt result.
class QuizAttemptResult {
  const QuizAttemptResult({
    this.isCorrect,
    this.correctAnswer = '',
    this.explanation = '',
    this.answeredCount = 0,
    this.totalQuestions = 0,
  });

  final bool? isCorrect;
  final String correctAnswer;
  final String explanation;
  final int answeredCount;
  final int totalQuestions;

  factory QuizAttemptResult.fromJson(Map<String, dynamic> json) {
    return QuizAttemptResult(
      isCorrect: json['is_correct'] as bool?,
      correctAnswer: json['correct_answer'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      answeredCount: json['answered_count'] as int? ?? 0,
      totalQuestions: json['total_questions'] as int? ?? 0,
    );
  }
}

/// Gamification service — server-backed, with the offline catalogue as backup.
///
/// The API is the source of truth: it owns the authoritative quiz for every
/// published story, grades attempts, and awards XP and badges. The bundled
/// SQLite catalogue is only consulted when the API cannot be reached, so a
/// reader offline still has something to play.
///
/// Pass a [remote] to use the API. [instance] is the local-only default kept for
/// callers that have no authenticated client to hand.
class GamificationApiService {
  GamificationApiService({
    LocalGamificationRepository? local,
    QuizApiService? remote,
  }) : _local = local ?? LocalGamificationRepository(),
       _remote = remote;

  final LocalGamificationRepository _local;
  final QuizApiService? _remote;

  /// Local-only instance, for callers without an authenticated client.
  static final GamificationApiService instance = GamificationApiService();

  /// Whether [error] means the request never reached the server.
  ///
  /// A status code proves the server answered, so only transport-level failures
  /// count as being offline.
  static bool _isOffline(DioException error) => switch (error.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          true,
        _ => false,
      };

  /// Run [remote] and fall back to the offline catalogue when the request never
  /// reached the server.
  ///
  /// Only transport failures fall back. A response the server actually sent —
  /// 404, 401, 500 — is an answer about the quiz, and quietly replacing it with
  /// a bundled quiz for some other story is how a reader ends up playing the
  /// wrong quiz. Those propagate to the caller instead.
  Future<T> _withOfflineFallback<T>(
    Future<T> Function(QuizApiService remote) remoteCall,
    Future<T> Function() localCall,
  ) async {
    final remote = _remote;
    if (remote == null) return localCall();
    try {
      return await remoteCall(remote);
    } on DioException catch (error) {
      if (!_isOffline(error)) rethrow;
      return localCall();
    }
  }

  /// Quizzes, optionally narrowed to one story.
  ///
  /// [storyId] is the API's story id. Offline, the bundled catalogue is keyed
  /// by its own story ids, so callers should pair this with the story slug (see
  /// [QuizModel.storySlug]) rather than trusting the id alone.
  Future<List<QuizModel>> listQuizzes({int? storyId}) {
    return _withOfflineFallback(
      (remote) => remote.listQuizzes(storyId: storyId),
      () => _local.listQuizzes(),
    );
  }

  /// Quiz detail with its questions.
  Future<QuizModel> getQuiz(int quizId) {
    return _withOfflineFallback(
      (remote) => remote.getQuiz(quizId),
      () => _local.getQuiz(quizId),
    );
  }

  /// Start a quiz attempt.
  Future<Map<String, dynamic>> startQuiz(int quizId) {
    return _withOfflineFallback(
      (remote) => remote.startQuiz(quizId),
      () => _local.startQuiz(quizId),
    );
  }

  /// Submit an answer for grading.
  Future<QuizAttemptResult> submitAnswer({
    required int quizId,
    required int questionId,
    required String selectedAnswer,
  }) {
    return _withOfflineFallback(
      (remote) => remote.submitAnswer(
        quizId: quizId,
        questionId: questionId,
        selectedAnswer: selectedAnswer,
      ),
      () => _local.submitAnswer(
        quizId: quizId,
        questionId: questionId,
        selectedAnswer: selectedAnswer,
      ),
    );
  }

  /// Finish and grade a quiz attempt.
  Future<Map<String, dynamic>> finishQuiz(
    int quizId, {
    Map<int, String> answers = const {},
  }) {
    return _withOfflineFallback(
      (remote) => remote.finishQuiz(quizId),
      () => _local.finishQuiz(quizId, answers: answers),
    );
  }

  /// List all badges.
  Future<List<BadgeModel>> listBadges() {
    return _withOfflineFallback(
      (remote) => remote.listBadges(),
      () => _local.listBadges(),
    );
  }

  /// Get user's gamification profile.
  Future<GamificationProfileModel> getProfile() {
    return _withOfflineFallback(
      (remote) => remote.getProfile(),
      () => _local.getProfile(),
    );
  }

  /// Log that the reader was present today, and hand back the device's IANA
  /// timezone name when the platform can supply one.
  ///
  /// Deliberately has no offline fallback: unlike a quiz catalogue there is no
  /// bundled truth to fall back to, and a locally-recorded day would claim
  /// attendance the server never saw. Failing is correct here — the next resume
  /// pings again.
  Future<void> recordActivity({String? timezone}) async {
    final remote = _remote;
    if (remote == null) return;
    await remote.recordActivity(timezone: timezone);
  }

  /// Leaderboard rows.
  ///
  /// Not part of the reader's quiz flow yet, so it stays empty rather than
  /// inventing an endpoint the app does not have.
  Future<List<Map<String, dynamic>>> getLeaderboard() async => [];
}
