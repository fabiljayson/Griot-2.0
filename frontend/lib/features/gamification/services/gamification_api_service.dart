import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

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

  List<String> get options => [optionA, optionB, optionC, if (optionD.isNotEmpty) optionD];
}

/// Quiz model.
class QuizModel {
  const QuizModel({
    required this.id,
    this.title = '',
    this.description = '',
    this.storyId = 0,
    this.storyTitle = '',
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
      passingScore: json['passing_score'] as int? ?? 70,
      timeLimitMinutes: json['time_limit_minutes'] as int? ?? 0,
      questionCount: json['question_count'] as int? ?? 0,
      xpReward: json['xp_reward'] as int? ?? 0,
      questions: (json['questions'] as List<dynamic>?)
              ?.map((q) => QuizQuestionModel.fromJson(q as Map<String, dynamic>))
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
  final int currentStreak;
  final int longestStreak;
  final int xpForNextLevel;
  final double xpProgress;
  final int badgesCount;
  final List<dynamic> recentBadges;

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

/// API service for gamification endpoints.
class GamificationApiService {
  GamificationApiService._({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static final GamificationApiService instance = GamificationApiService._();

  static const _basePath = '/api/gamification';

  /// List all quizzes.
  Future<List<QuizModel>> listQuizzes() async {
    final response = await _dio.get('$_basePath/quizzes/');
    final results = response.data['results'] as List<dynamic>;
    return results
        .map((json) => QuizModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get quiz detail with questions.
  Future<QuizModel> getQuiz(int quizId) async {
    final response = await _dio.get('$_basePath/quizzes/$quizId/');
    return QuizModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Start a quiz attempt.
  Future<Map<String, dynamic>> startQuiz(int quizId) async {
    final response = await _dio.post('$_basePath/quizzes/$quizId/start/');
    return response.data as Map<String, dynamic>;
  }

  /// Submit an answer.
  Future<QuizAttemptResult> submitAnswer({
    required int quizId,
    required int questionId,
    required String selectedAnswer,
  }) async {
    final response = await _dio.post(
      '$_basePath/quizzes/$quizId/submit_answer/',
      data: {
        'question_id': questionId,
        'selected_answer': selectedAnswer,
      },
    );
    return QuizAttemptResult.fromJson(response.data as Map<String, dynamic>);
  }

  /// Finish a quiz attempt.
  Future<Map<String, dynamic>> finishQuiz(int quizId) async {
    final response = await _dio.post('$_basePath/quizzes/$quizId/finish/');
    return response.data as Map<String, dynamic>;
  }

  /// List all badges.
  Future<List<BadgeModel>> listBadges() async {
    final response = await _dio.get('$_basePath/badges/');
    final results = response.data['results'] as List<dynamic>;
    return results
        .map((json) => BadgeModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get user's gamification profile.
  Future<GamificationProfileModel> getProfile() async {
    final response = await _dio.get('$_basePath/profile/');
    return GamificationProfileModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get leaderboard.
  Future<List<Map<String, dynamic>>> getLeaderboard() async {
    final response = await _dio.get('$_basePath/leaderboard/');
    return (response.data as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }
}
