import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import '../constants/story_assets.dart';
import 'seed/seed_badges.dart';
import 'seed/seed_quizzes.dart';
import 'seed/seed_stories.dart';

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

  /// Production singleton. Tests should build their own instance with
  /// [AppDatabase.forTesting] so suites run in parallel isolates without
  /// racing on the same on-disk file.
  static final AppDatabase instance = AppDatabase._();

  /// An isolated database under a distinct name, so repository tests never
  /// collide with the shared [instance] when suites run concurrently.
  @visibleForTesting
  factory AppDatabase.forTesting({required String name}) {
    final database = AppDatabase._();
    database._nameOverride = name;
    return database;
  }

  String? _nameOverride;

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
    final name = _nameOverride ?? AppConstants.databaseName;
    final path = kIsWeb ? name : p.join(await getDatabasesPath(), name);
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

    // A fresh install has no `user_version` to upgrade *from*, so sqflite only
    // calls this method — never `_onUpgrade`. The v1 baseline above was
    // therefore the only schema a brand-new install ever received, leaving the
    // whole `local_*` content layer (stories, categories, quizzes, badges)
    // missing and every screen empty. Replay the remaining steps from v4:
    // v2/v3 are already created above, so start at 3 to avoid duplicating them.
    await _onUpgrade(db, 3, version);
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

    if (oldVersion < 4) {
      // ── Full local data layer: local_users, local_stories, local_categories ──

      // Active local user (one row at a time, representing the logged-in user).
      await db.execute('''
        CREATE TABLE local_users (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          username      TEXT NOT NULL UNIQUE,
          email         TEXT NOT NULL UNIQUE,
          password      TEXT NOT NULL,
          first_name    TEXT DEFAULT '',
          last_name     TEXT DEFAULT '',
          role          TEXT NOT NULL DEFAULT 'visitor',
          institution   TEXT DEFAULT '',
          created_at    TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');

      // Local story categories.
      await db.execute('''
        CREATE TABLE local_categories (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          name          TEXT NOT NULL,
          slug          TEXT NOT NULL UNIQUE,
          description   TEXT DEFAULT '',
          icon          TEXT DEFAULT '📖',
          color         TEXT DEFAULT '#8B4513'
        )
      ''');

      // Full local stories (read/write offline).
      await db.execute('''
        CREATE TABLE local_stories (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          title         TEXT NOT NULL,
          slug          TEXT NOT NULL UNIQUE,
          content       TEXT DEFAULT '',
          summary       TEXT DEFAULT '',
          author_id     INTEGER,
          language      TEXT DEFAULT 'en',
          region        TEXT DEFAULT '',
          tags          TEXT DEFAULT '',
          cover_image   TEXT,
          audio_url     TEXT DEFAULT '',
          video_url     TEXT DEFAULT '',
          cultural_context TEXT DEFAULT '',
          moral_lesson  TEXT DEFAULT '',
          source        TEXT DEFAULT '',
          estimated_read_time INTEGER DEFAULT 0,
          status        TEXT DEFAULT 'published',
          view_count    INTEGER DEFAULT 0,
          like_count    INTEGER DEFAULT 0,
          bookmark_count INTEGER DEFAULT 0,
          is_bookmarked  INTEGER DEFAULT 0,
          is_liked      INTEGER DEFAULT 0,
          created_at    TEXT NOT NULL DEFAULT (datetime('now')),
          published_at  TEXT,
          FOREIGN KEY (author_id) REFERENCES local_users(id)
        )
      ''');

      // Story-category junction table.
      await db.execute('''
        CREATE TABLE local_story_categories (
          story_id      INTEGER NOT NULL,
          category_id   INTEGER NOT NULL,
          PRIMARY KEY (story_id, category_id),
          FOREIGN KEY (story_id)    REFERENCES local_stories(id) ON DELETE CASCADE,
          FOREIGN KEY (category_id) REFERENCES local_categories(id) ON DELETE CASCADE
        )
      ''');

      await db.execute(
        'CREATE INDEX idx_local_stories_slug ON local_stories (slug)',
      );
      await db.execute(
        'CREATE INDEX idx_local_stories_status ON local_stories (status)',
      );
      await db.execute(
        'CREATE INDEX idx_local_stories_region ON local_stories (region)',
      );

      // Seed default user and categories, then stories.
      await _seedDefaultUser(db);
      await _seedCategories(db);
      await _seedStories(db);
    }

    if (oldVersion < 5) {
      // ── Gamification: local_quizzes, local_quiz_questions, local_badges,
      //    local_user_gamification ──

      await db.execute('''
        CREATE TABLE local_quizzes (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          title           TEXT NOT NULL,
          description     TEXT DEFAULT '',
          story_id        INTEGER,
          story_title     TEXT DEFAULT '',
          passing_score   INTEGER DEFAULT 70,
          time_limit_minutes INTEGER DEFAULT 0,
          question_count  INTEGER DEFAULT 0,
          xp_reward       INTEGER DEFAULT 0,
          language        TEXT DEFAULT 'en',
          FOREIGN KEY (story_id) REFERENCES local_stories(id)
        )
      ''');

      await db.execute('''
        CREATE TABLE local_quiz_questions (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          quiz_id         INTEGER NOT NULL,
          question_text   TEXT NOT NULL,
          option_a        TEXT NOT NULL,
          option_b        TEXT NOT NULL,
          option_c        TEXT NOT NULL,
          option_d        TEXT DEFAULT '',
          correct_answer  TEXT NOT NULL,
          explanation     TEXT DEFAULT '',
          difficulty      TEXT DEFAULT 'medium',
          FOREIGN KEY (quiz_id) REFERENCES local_quizzes(id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE local_badges (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          name            TEXT NOT NULL,
          slug            TEXT NOT NULL UNIQUE,
          description     TEXT DEFAULT '',
          emoji           TEXT DEFAULT '🏆',
          category        TEXT DEFAULT 'reading',
          xp_required     INTEGER DEFAULT 0,
          color           TEXT DEFAULT '#C85A32',
          is_secret       INTEGER DEFAULT 0,
          earned          INTEGER DEFAULT 0
        )
      ''');

      await db.execute('''
        CREATE TABLE local_user_gamification (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id         INTEGER NOT NULL,
          total_xp        INTEGER DEFAULT 0,
          level           INTEGER DEFAULT 1,
          stories_read    INTEGER DEFAULT 0,
          stories_completed INTEGER DEFAULT 0,
          quizzes_passed  INTEGER DEFAULT 0,
          current_streak  INTEGER DEFAULT 0,
          longest_streak  INTEGER DEFAULT 0,
          UNIQUE(user_id)
        )
      ''');

      await db.execute('''
        CREATE TABLE local_quiz_attempts (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          quiz_id         INTEGER NOT NULL,
          user_id         INTEGER NOT NULL,
          score           INTEGER DEFAULT 0,
          passed          INTEGER DEFAULT 0,
          started_at      TEXT NOT NULL DEFAULT (datetime('now')),
          finished_at     TEXT,
          FOREIGN KEY (quiz_id) REFERENCES local_quizzes(id) ON DELETE CASCADE,
          FOREIGN KEY (user_id) REFERENCES local_users(id) ON DELETE CASCADE
        )
      ''');

      // Seed badges.
      await _seedBadges(db);

      // Seed quizzes with questions.
      await _seedQuizzes(db);
    }

    if (oldVersion < 6) {
      // v6 — attach bundled cover art to stories that predate it. Installations
      // created by v5 or earlier have `cover_image = NULL` for every seeded
      // story, so their cards rendered placeholders forever.
      await _backfillCoverImages(db);
    }

    if (oldVersion < 7) {
      // v7 — two repairs.
      //
      // 1. Installations stamped v4-v6 but created by the old `_onCreate` (which
      //    built only the v1 baseline, see the note there) have no `local_*`
      //    tables at all. Rebuild the missing half of the schema by replaying the
      //    matching migration steps, so reusing the DDL instead of duplicating it.
      if (!await _hasTable(db, 'local_stories')) {
        await _onUpgrade(db, 3, 4);
      }
      if (!await _hasTable(db, 'local_quizzes')) {
        await _onUpgrade(db, 4, 5);
      }

      // 2. A seeded quiz whose `story_id` was never set can never be resolved
      //    from the reader's "Take Quiz" CTA, so it always reported "quiz
      //    coming soon". Link every unlinked quiz to its story.
      await _linkUnlinkedQuizzes(db);
    }
  }

  /// True when [name] exists as a table in the current database.
  Future<bool> _hasTable(Database db, String name) async {
    final rows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Attach any quiz with no `story_id` to the story whose title matches its
  /// `story_title`.
  ///
  /// Seeded quizzes carry the title of the story they belong to, so a title
  /// lookup repairs links that were never made (the French Anansi quiz was
  /// seeded without one). Matching on title rather than slug keeps this working
  /// for quizzes added by contributors. Safe to run repeatedly.
  Future<void> _linkUnlinkedQuizzes(Database db) async {
    final rows = await db.query(
      'local_quizzes',
      columns: ['id', 'story_title'],
      where: 'story_id IS NULL',
    );

    for (final row in rows) {
      final title = (row['story_title'] as String?)?.trim() ?? '';
      if (title.isEmpty) continue;

      final matches = await db.query(
        'local_stories',
        columns: ['id'],
        where: 'title = ?',
        whereArgs: [title],
        limit: 1,
      );
      if (matches.isEmpty) continue;

      await db.update(
        'local_quizzes',
        {'story_id': matches.first['id']},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  /// Attach bundled cover art to any seeded story whose slug has art but no
  /// stored `cover_image`. Safe to run repeatedly; only touches NULL/empty
  /// values so user-supplied covers are never overwritten.
  Future<void> _backfillCoverImages(Database db) async {
    final rows = await db.query(
      'local_stories',
      columns: ['id', 'slug', 'cover_image'],
    );
    for (final row in rows) {
      final existing = row['cover_image'] as String?;
      if (existing != null && existing.trim().isNotEmpty) continue;
      final asset = StoryCoverAssets.forSlug(row['slug'] as String);
      if (asset == null) continue;
      await db.update(
        'local_stories',
        {'cover_image': asset},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  /// Seed a default local user for immediate offline login.
  Future<void> _seedDefaultUser(Database db) async {
    await db.insert('local_users', {
      'username': 'admin',
      'email': 'admin@griot-ai.com',
      'password': 'admin123',
      'first_name': 'Super',
      'last_name': 'Admin',
      'role': 'admin',
      'institution': '',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert('local_users', {
      'username': 'visitor1',
      'email': 'visitor1@griot-ai.com',
      'password': 'visitor123',
      'first_name': 'Amara',
      'last_name': 'Nkomo',
      'role': 'visitor',
      'institution': '',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert('local_users', {
      'username': 'contributor1',
      'email': 'contributor1@griot-ai.com',
      'password': 'contributor123',
      'first_name': 'Nana',
      'last_name': 'Yemo',
      'role': 'contributor',
      'institution': '',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Seed default story categories.
  Future<void> _seedCategories(Database db) async {
    final categories = [
      {
        'name': 'Folktales',
        'slug': 'folktales',
        'description':
            'Traditional folk tales passed down through generations.',
        'icon': '📖',
        'color': '#8B4513',
      },
      {
        'name': 'Myths',
        'slug': 'myths',
        'description':
            'Mythological stories about gods, spirits, and creation.',
        'icon': '🌌',
        'color': '#4A6741',
      },
      {
        'name': 'Legends',
        'slug': 'legends',
        'description': 'Legendary tales of heroes and historical events.',
        'icon': '⚔️',
        'color': '#C68B29',
      },
      {
        'name': 'Proverbs',
        'slug': 'proverbs',
        'description': 'Wise sayings and traditional wisdom.',
        'icon': '💡',
        'color': '#6B4C8A',
      },
      {
        'name': 'Songs',
        'slug': 'songs',
        'description': 'Traditional songs and oral poetry.',
        'icon': '🎵',
        'color': '#B85C38',
      },
    ];
    for (final c in categories) {
      await db.insert(
        'local_categories',
        c,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Seed sample stories with full content.
  Future<void> _seedStories(Database db) async {
    for (final s in kSeedStories) {
      final categorySlug = s.remove('category_slug') as String?;
      // Look up author_id — use first local_user or null.
      final userRows = await db.query('local_users', limit: 1);
      final authorId = userRows.isNotEmpty ? userRows.first['id'] : null;
      // Attach the bundled cover art for this slug. Without this the seeded
      // collection renders with placeholders on every card (see
      // StoryCoverAssets).
      final slug = s['slug'] as String;
      final coverImage = StoryCoverAssets.forSlug(slug);
      final storyId = await db.insert('local_stories', {
        ...s,
        'author_id': authorId,
        'cover_image': ?coverImage,
      });
      if (categorySlug != null) {
        final catRows = await db.query(
          'local_categories',
          where: 'slug = ?',
          whereArgs: [categorySlug],
          limit: 1,
        );
        if (catRows.isNotEmpty) {
          await db.insert('local_story_categories', {
            'story_id': storyId,
            'category_id': catRows.first['id'],
          });
        }
      }
    }
  }

  /// Seed achievement badges.
  Future<void> _seedBadges(Database db) async {
    for (final b in kSeedBadges) {
      await db.insert(
        'local_badges',
        b,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Seed quizzes with questions (linked to stories where possible).
  Future<void> _seedQuizzes(Database db) async {
    // Story-specific quizzes are linked by slug; the collection-wide culture
    // quiz and the French edition are resolved afterwards via story title.
    for (final seed in kSeedQuizzes) {
      final quizId = await db.insert('local_quizzes', seed.quiz);
      if (seed.storySlug != null) {
        await _linkQuizToStory(db, quizId, seed.storySlug!);
      }
      for (final question in seed.questions) {
        await db.insert('local_quiz_questions', {
          'quiz_id': quizId,
          ...question,
        });
      }
    }

    // The French quiz is seeded without an explicit slug link above, so resolve
    // any remaining unlinked quiz by story title. Without this its reader still
    // reports "quiz coming soon".
    await _linkUnlinkedQuizzes(db);
  }

  /// Link a quiz to its story by slug.
  Future<void> _linkQuizToStory(
    Database db,
    int quizId,
    String storySlug,
  ) async {
    final rows = await db.query(
      'local_stories',
      columns: ['id'],
      where: 'slug = ?',
      whereArgs: [storySlug],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      await db.update(
        'local_quizzes',
        {'story_id': rows.first['id']},
        where: 'id = ?',
        whereArgs: [quizId],
      );
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
