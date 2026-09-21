import 'package:sqflite/sqflite.dart';

import '../../../features/library/services/library_api_service.dart';
import '../app_database.dart';

/// Repository for local library operations against SQLite.
///
/// Provides continue reading, recently read, and bookmarks — all from
/// the local database with no network requests.
class LocalLibraryRepository {
  LocalLibraryRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  /// Get stories the user has started but not completed (progress > 0, < 100%).
  Future<List<LibraryStoryModel>> getContinueReading() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT s.*, rp.scroll_fraction, rp.updated_at as last_read_at '
      'FROM local_stories s '
      'JOIN reading_progress rp ON rp.story_id = s.id '
      'WHERE rp.scroll_fraction > 0 AND rp.scroll_fraction < 1.0 '
      'ORDER BY rp.updated_at DESC',
    );
    return rows.map(_rowToLibraryStory).toList();
  }

  /// Get stories the user has read recently (any progress, sorted by last read).
  Future<List<LibraryStoryModel>> getRecentlyRead() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT s.*, rp.scroll_fraction, rp.updated_at as last_read_at '
      'FROM local_stories s '
      'JOIN reading_progress rp ON rp.story_id = s.id '
      'WHERE rp.scroll_fraction > 0 '
      'ORDER BY rp.updated_at DESC '
      'LIMIT 20',
    );
    return rows.map(_rowToLibraryStory).toList();
  }

  /// Get bookmarked stories.
  Future<List<LibraryStoryModel>> getBookmarks() async {
    final db = await _db;
    final rows = await db.query(
      'local_stories',
      where: 'is_bookmarked = 1',
      orderBy: 'created_at DESC',
    );
    return rows.map((row) => _rowToLibraryStory(
      {...row, 'scroll_fraction': 0.0, 'last_read_at': row['created_at']},
    )).toList();
  }

  LibraryStoryModel _rowToLibraryStory(Map<String, dynamic> row) {
    final progress = ((row['scroll_fraction'] as num?) ?? 0.0).toDouble();
    return LibraryStoryModel(
      id: row['id'] as int,
      slug: row['slug'] as String,
      title: row['title'] as String,
      summary: (row['summary'] as String?) ?? '',
      language: (row['language'] as String?) ?? 'en',
      region: (row['region'] as String?) ?? '',
      coverImage: row['cover_image'] as String?,
      estimatedReadTime: (row['estimated_read_time'] as int?) ?? 0,
      progressPercent: (progress * 100).round(),
      completed: progress >= 1.0,
      lastReadAt: (row['last_read_at'] as String?) ?? '',
      isBookmarked: (row['is_bookmarked'] as int?) == 1,
    );
  }
}
