import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';

/// Local SQLite database helper for offline caching (Task 1.3).
///
/// Owns the schema and migrations for all client-side tables:
///   - `story_cache`      — stories saved for offline reading (Phase 4.3)
///   - `search_history`   — local fuzzy-search history (Phase 3.2)
///   - `reading_progress` — scroll depth & audio resume (Phase 7.2)
///
/// Mobile uses sqflite; the web client swaps this for IndexedDB (Phase 9).
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  /// Lazily opens (and caches) the database connection.
  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, AppConstants.databaseName);
    return openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onConfigure: (db) async {
        // Enable foreign keys for referential integrity.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE story_cache (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        story_id      INTEGER NOT NULL UNIQUE,
        title         TEXT NOT NULL,
        category      TEXT,
        region        TEXT,
        content_markdown TEXT,
        hero_image_path TEXT,
        audio_path    TEXT,
        video_url     TEXT,
        historical_context TEXT,
        estimated_read_time INTEGER,
        saved_at      TEXT NOT NULL DEFAULT (datetime('now')),
        is_favorite   INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE search_history (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        query      TEXT NOT NULL,
        searched_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE reading_progress (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        story_id             INTEGER NOT NULL UNIQUE,
        scroll_fraction     REAL NOT NULL DEFAULT 0,
        audio_resume_seconds INTEGER NOT NULL DEFAULT 0,
        updated_at           TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // Index for fast story lookups.
    await db.execute(
      'CREATE INDEX idx_story_cache_region ON story_cache (region)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Schema v1 is the baseline; future migrations append here.
    // e.g. if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
