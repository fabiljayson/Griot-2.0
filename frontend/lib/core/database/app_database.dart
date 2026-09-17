import 'package:flutter/foundation.dart';
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
/// Mobile uses the sqflite plugin; on web the sqflite_common_ffi_web factory
/// (installed in `main()`) backs the same API with SQLite/wasm over IndexedDB.
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
    // On web the database lives in the browser's IndexedDB (Phase 9): the
    // sqflite_common_ffi_web factory keys databases by name rather than by a
    // filesystem path, so pass the bare name instead of joining a path.
    final path = kIsWeb
        ? AppConstants.databaseName
        : p.join(await getDatabasesPath(), AppConstants.databaseName);
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

    await db.execute('''
      CREATE TABLE offline_requests (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        method        TEXT NOT NULL,
        path          TEXT NOT NULL,
        body          TEXT,
        headers       TEXT,
        created_at    TEXT NOT NULL DEFAULT (datetime('now')),
        retry_count   INTEGER NOT NULL DEFAULT 0,
        max_retries   INTEGER NOT NULL DEFAULT 3,
        status        TEXT NOT NULL DEFAULT 'pending',
        error_message TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE offline_users (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        username      TEXT NOT NULL UNIQUE,
        email         TEXT NOT NULL UNIQUE,
        password      TEXT NOT NULL,
        first_name    TEXT DEFAULT '',
        last_name     TEXT DEFAULT '',
        role          TEXT NOT NULL DEFAULT 'visitor',
        institution   TEXT DEFAULT '',
        created_at    TEXT NOT NULL DEFAULT (datetime('now')),
        status        TEXT NOT NULL DEFAULT 'pending',
        server_user_id INTEGER,
        error_message TEXT
      )
    ''');

    // Index for fast story lookups.
    await db.execute(
      'CREATE INDEX idx_story_cache_region ON story_cache (region)',
    );

    // Index for offline request queue.
    await db.execute(
      'CREATE INDEX idx_offline_requests_status ON offline_requests (status)',
    );

    // Index for offline users.
    await db.execute(
      'CREATE INDEX idx_offline_users_status ON offline_users (status)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Schema v1 is the baseline; future migrations append here.
    if (oldVersion < 2) {
      // Add offline_requests table for queueing API calls when offline.
      await db.execute('''
        CREATE TABLE offline_requests (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          method        TEXT NOT NULL,
          path          TEXT NOT NULL,
          body          TEXT,
          headers       TEXT,
          created_at    TEXT NOT NULL DEFAULT (datetime('now')),
          retry_count   INTEGER NOT NULL DEFAULT 0,
          max_retries   INTEGER NOT NULL DEFAULT 3,
          status        TEXT NOT NULL DEFAULT 'pending',
          error_message TEXT
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_offline_requests_status ON offline_requests (status)',
      );
    }

    if (oldVersion < 3) {
      // Add offline_users table for offline registration.
      await db.execute('''
        CREATE TABLE offline_users (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          username      TEXT NOT NULL UNIQUE,
          email         TEXT NOT NULL UNIQUE,
          password      TEXT NOT NULL,
          first_name    TEXT DEFAULT '',
          last_name     TEXT DEFAULT '',
          role          TEXT NOT NULL DEFAULT 'visitor',
          institution   TEXT DEFAULT '',
          created_at    TEXT NOT NULL DEFAULT (datetime('now')),
          status        TEXT NOT NULL DEFAULT 'pending',
          server_user_id INTEGER,
          error_message TEXT
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_offline_users_status ON offline_users (status)',
      );
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
