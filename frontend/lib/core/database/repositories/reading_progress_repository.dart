import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

/// Data-access layer over the `reading_progress` table.
///
/// Saves scroll depth + audio resume timestamps so users can continue
/// exactly where they left off (Phase 7.2).
class ReadingProgressRepository {
  ReadingProgressRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  /// Save reading progress for a story (upsert by story_id).
  Future<void> saveProgress({
    required int storyId,
    double scrollFraction = 0,
    int audioResumeSeconds = 0,
  }) async {
    final db = await _db;
    await db.insert(
      'reading_progress',
      {
        'story_id': storyId,
        'scroll_fraction': scrollFraction,
        'audio_resume_seconds': audioResumeSeconds,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The last saved progress for a story, or null if never opened.
  Future<({int storyId, double scrollFraction, int audioResumeSeconds})?>
      getProgress(int storyId) async {
    final db = await _db;
    final rows = await db.query(
      'reading_progress',
      where: 'story_id = ?',
      whereArgs: [storyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (
      storyId: r['story_id'] as int,
      scrollFraction: (r['scroll_fraction'] as num).toDouble(),
      audioResumeSeconds: r['audio_resume_seconds'] as int,
    );
  }
}
