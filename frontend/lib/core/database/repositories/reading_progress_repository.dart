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
    await db.insert('reading_progress', {
      'story_id': storyId,
      'scroll_fraction': scrollFraction,
      'audio_resume_seconds': audioResumeSeconds,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  /// The last saved progress for a story addressed by its slug, or null.
  ///
  /// Resolves the local row id first, so callers that only hold an API slug
  /// (mirrored or local-only) can restore a position without threading ids
  /// through the model layer. `lastPosition` carries the scroll offset in
  /// pixels — the same value `LocalStoryRepository.updateReadingProgress`
  /// writes into the `audio_resume_seconds` column.
  Future<({double scrollFraction, int lastPosition})?> progressForSlug(
    String slug,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'local_stories',
      columns: ['id'],
      where: 'slug = ?',
      whereArgs: [slug],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final progress = await getProgress(rows.first['id'] as int);
    if (progress == null) return null;
    return (
      scrollFraction: progress.scrollFraction,
      lastPosition: progress.audioResumeSeconds,
    );
  }
}
