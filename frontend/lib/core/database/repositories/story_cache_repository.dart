import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models/cached_story.dart';

/// Data-access layer over the `story_cache` table.
///
/// Used by the "Saved for Offline" toggle (Phase 4.3) and the library
/// screen (Phase 7.2).
class StoryCacheRepository {
  StoryCacheRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  /// Save (upsert) a story into the offline cache.
  Future<void> saveStory(CachedStory story) async {
    final db = await _db;
    await db.insert(
      'story_cache',
      story.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieve a single cached story by its API id.
  Future<CachedStory?> getStory(int storyId) async {
    final db = await _db;
    final rows = await db.query(
      'story_cache',
      where: 'story_id = ?',
      whereArgs: [storyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CachedStory.fromMap(rows.first);
  }

  /// All stories currently saved offline, newest first.
  Future<List<CachedStory>> getAllStories() async {
    final db = await _db;
    final rows = await db.query(
      'story_cache',
      orderBy: 'saved_at DESC',
    );
    return rows.map(CachedStory.fromMap).toList();
  }

  /// Remove a story from the offline cache.
  Future<int> deleteStory(int storyId) async {
    final db = await _db;
    return db.delete(
      'story_cache',
      where: 'story_id = ?',
      whereArgs: [storyId],
    );
  }

  /// Whether a story is available offline.
  Future<bool> isSaved(int storyId) async => await getStory(storyId) != null;

  /// Toggle the favorite flag.
  Future<void> setFavorite(int storyId, bool favorite) async {
    final db = await _db;
    await db.update(
      'story_cache',
      {'is_favorite': favorite ? 1 : 0},
      where: 'story_id = ?',
      whereArgs: [storyId],
    );
  }

  /// Number of stories cached offline.
  Future<int> count() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM story_cache');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Wipe the entire offline cache.
  Future<void> clear() async {
    final db = await _db;
    await db.delete('story_cache');
  }
}
