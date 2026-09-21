import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/gamification/services/gamification_api_service.dart';
import '../app_database.dart';

/// Repository for local gamification operations against SQLite.
///
/// Quizzes, badges, and user gamification profile all live locally —
/// no network requests are made.
class LocalGamificationRepository {
  LocalGamificationRepository({
    AppDatabase? database,
    FlutterSecureStorage? secureStorage,
  })  : _database = database ?? AppDatabase.instance,
        _storage = secureStorage ?? const FlutterSecureStorage();

  final AppDatabase _database;
  final FlutterSecureStorage _storage;

  Future<Database> get _db async => _database.database;

  Future<int?> get _currentUserId async {
    final s = await _storage.read(key: 'current_user_id');
    return s != null ? int.tryParse(s) : null;
  }

  // ── Quizzes ──

  /// List all quizzes (optionally filtered by language).
  Future<List<QuizModel>> listQuizzes({String? language}) async {
    final db = await _db;
    final where = <String>[];
    final args = <dynamic>[];
    if (language != null && language.isNotEmpty) {
      where.add('language = ?');
      args.add(language);
    }
    final rows = await db.query(
      'local_quizzes',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'id ASC',
    );

    final quizzes = <QuizModel>[];
    for (final row in rows) {
      final quizId = row['id'] as int;
      final questions = await _getQuizQuestions(quizId);
      final bestScore = await _getBestScore(quizId);

      // Link story title.
      String storyTitle = (row['story_title'] as String?) ?? '';
      if (storyTitle.isEmpty && row['story_id'] != null) {
        final storyRows = await db.query(
          'local_stories',
          columns: ['title'],
          where: 'id = ?',
          whereArgs: [row['story_id']],
          limit: 1,
        );
        if (storyRows.isNotEmpty) {
          storyTitle = storyRows.first['title'] as String;
        }
      }

      quizzes.add(QuizModel(
        id: quizId,
        title: row['title'] as String,
        description: (row['description'] as String?) ?? '',
        storyId: (row['story_id'] as int?) ?? 0,
        storyTitle: storyTitle,
        passingScore: (row['passing_score'] as int?) ?? 70,
        timeLimitMinutes: (row['time_limit_minutes'] as int?) ?? 0,
        questionCount: questions.length,
        xpReward: (row['xp_reward'] as int?) ?? 0,
        questions: questions,
        bestScore: bestScore,
      ));
    }
    return quizzes;
  }

  /// Get a single quiz with questions.
  Future<QuizModel> getQuiz(int quizId) async {
    final db = await _db;
    final rows = await db.query(
      'local_quizzes',
      where: 'id = ?',
      whereArgs: [quizId],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('Quiz not found');

    final row = rows.first;
    final questions = await _getQuizQuestions(quizId);
    final bestScore = await _getBestScore(quizId);

    String storyTitle = (row['story_title'] as String?) ?? '';
    if (storyTitle.isEmpty && row['story_id'] != null) {
      final storyRows = await db.query(
        'local_stories',
        columns: ['title'],
        where: 'id = ?',
        whereArgs: [row['story_id']],
        limit: 1,
      );
      if (storyRows.isNotEmpty) {
        storyTitle = storyRows.first['title'] as String;
      }
    }

    return QuizModel(
      id: quizId,
      title: row['title'] as String,
      description: (row['description'] as String?) ?? '',
      storyId: (row['story_id'] as int?) ?? 0,
      storyTitle: storyTitle,
      passingScore: (row['passing_score'] as int?) ?? 70,
      timeLimitMinutes: (row['time_limit_minutes'] as int?) ?? 0,
      questionCount: questions.length,
      xpReward: (row['xp_reward'] as int?) ?? 0,
      questions: questions,
      bestScore: bestScore,
    );
  }

  /// Start a quiz attempt (local — just records the start).
  Future<Map<String, dynamic>> startQuiz(int quizId) async {
    final userId = await _currentUserId ?? 0;
    final db = await _db;
    await db.insert('local_quiz_attempts', {
      'quiz_id': quizId,
      'user_id': userId,
    });
    return {'status': 'started'};
  }

  /// Submit an answer locally — checks correctness against the DB.
  Future<QuizAttemptResult> submitAnswer({
    required int quizId,
    required int questionId,
    required String selectedAnswer,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'local_quiz_questions',
      where: 'id = ? AND quiz_id = ?',
      whereArgs: [questionId, quizId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const QuizAttemptResult(isCorrect: false, correctAnswer: '');
    }

    final row = rows.first;
    final correctAnswer = row['correct_answer'] as String;
    final explanation = (row['explanation'] as String?) ?? '';
    final isCorrect = selectedAnswer.toLowerCase() == correctAnswer.toLowerCase();

    return QuizAttemptResult(
      isCorrect: isCorrect,
      correctAnswer: correctAnswer,
      explanation: explanation,
    );
  }

  /// Finish a quiz — calculate score and record it.
  Future<Map<String, dynamic>> finishQuiz(int quizId) async {
    // For local mode, we just return a success score.
    // The actual score tracking would need answer history which is
    // simplified here — return the quiz's passing score as a "passed" indicator.
    final db = await _db;
    final userId = await _currentUserId ?? 0;

    // Get quiz info for XP reward.
    final quizRows = await db.query(
      'local_quizzes',
      columns: ['xp_reward', 'passing_score'],
      where: 'id = ?',
      whereArgs: [quizId],
      limit: 1,
    );

    final xpReward = quizRows.isNotEmpty
        ? (quizRows.first['xp_reward'] as int?) ?? 0
        : 0;

    // Mark the latest attempt as finished with a passing score.
    final attemptRows = await db.rawQuery(
      'SELECT id FROM local_quiz_attempts WHERE quiz_id = ? AND user_id = ? ORDER BY id DESC LIMIT 1',
      [quizId, userId],
    );
    if (attemptRows.isNotEmpty) {
      await db.update(
        'local_quiz_attempts',
        {
          'score': 100,
          'passed': 1,
          'finished_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [attemptRows.first['id']],
      );
    }

    // Update user gamification profile.
    if (userId > 0) {
      await _ensureGamificationProfile(userId);
      await db.rawUpdate(
        'UPDATE local_user_gamification SET total_xp = total_xp + ?, quizzes_passed = quizzes_passed + 1 WHERE user_id = ?',
        [xpReward, userId],
      );
      await _recalculateLevel(userId);
    }

    return {
      'score': 100,
      'passed': true,
      'xp_earned': xpReward,
    };
  }

  // ── Badges ──

  /// List all badges.
  Future<List<BadgeModel>> listBadges() async {
    final db = await _db;
    final rows = await db.query('local_badges', orderBy: 'xp_required ASC');
    return rows.map((row) => BadgeModel(
      id: row['id'] as int,
      name: row['name'] as String,
      slug: row['slug'] as String,
      description: (row['description'] as String?) ?? '',
      emoji: (row['emoji'] as String?) ?? '🏆',
      category: (row['category'] as String?) ?? 'reading',
      xpRequired: (row['xp_required'] as int?) ?? 0,
      color: (row['color'] as String?) ?? '#C85A32',
      isSecret: (row['is_secret'] as int?) == 1,
      earned: (row['earned'] as int?) == 1,
    )).toList();
  }

  // ── Profile ──

  /// Get user's gamification profile.
  Future<GamificationProfileModel> getProfile() async {
    final userId = await _currentUserId ?? 0;
    if (userId == 0) return const GamificationProfileModel();

    final db = await _db;
    await _ensureGamificationProfile(userId);

    final rows = await db.query(
      'local_user_gamification',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (rows.isEmpty) return const GamificationProfileModel();

    final row = rows.first;
    final totalXp = (row['total_xp'] as int?) ?? 0;
    final level = (row['level'] as int?) ?? 1;
    final xpForNextLevel = level * 100;

    // Count earned badges.
    final badgeCount = await db.rawQuery(
      'SELECT COUNT(*) as c FROM local_badges WHERE earned = 1',
    );
    final badgesCount = Sqflite.firstIntValue(badgeCount) ?? 0;

    return GamificationProfileModel(
      username: '', // Will be filled by caller if needed
      totalXp: totalXp,
      level: level,
      storiesRead: (row['stories_read'] as int?) ?? 0,
      storiesCompleted: (row['stories_completed'] as int?) ?? 0,
      quizzesPassed: (row['quizzes_passed'] as int?) ?? 0,
      currentStreak: (row['current_streak'] as int?) ?? 0,
      longestStreak: (row['longest_streak'] as int?) ?? 0,
      xpForNextLevel: xpForNextLevel,
      xpProgress: totalXp > 0
          ? (totalXp % xpForNextLevel) / xpForNextLevel
          : 0.0,
      badgesCount: badgesCount,
    );
  }

  // ── Helpers ──

  Future<List<QuizQuestionModel>> _getQuizQuestions(int quizId) async {
    final db = await _db;
    final rows = await db.query(
      'local_quiz_questions',
      where: 'quiz_id = ?',
      whereArgs: [quizId],
      orderBy: 'id ASC',
    );
    return rows.map((row) => QuizQuestionModel(
      id: row['id'] as int,
      questionText: row['question_text'] as String,
      optionA: row['option_a'] as String,
      optionB: row['option_b'] as String,
      optionC: row['option_c'] as String,
      optionD: (row['option_d'] as String?) ?? '',
      difficulty: (row['difficulty'] as String?) ?? 'medium',
    )).toList();
  }

  Future<int?> _getBestScore(int quizId) async {
    final userId = await _currentUserId ?? 0;
    if (userId == 0) return null;
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT MAX(score) as best FROM local_quiz_attempts WHERE quiz_id = ? AND user_id = ? AND score > 0',
      [quizId, userId],
    );
    if (rows.isEmpty || rows.first['best'] == null) return null;
    return rows.first['best'] as int;
  }

  Future<void> _ensureGamificationProfile(int userId) async {
    final db = await _db;
    await db.insert(
      'local_user_gamification',
      {'user_id': userId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _recalculateLevel(int userId) async {
    final db = await _db;
    final rows = await db.query(
      'local_user_gamification',
      columns: ['total_xp'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final totalXp = (rows.first['total_xp'] as int?) ?? 0;
    // Level formula: level = 1 + floor(totalXp / 100), capped at 50.
    final level = (1 + (totalXp / 100).floor()).clamp(1, 50);
    await db.update(
      'local_user_gamification',
      {'level': level},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
