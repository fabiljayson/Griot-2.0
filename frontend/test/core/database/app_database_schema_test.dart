import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:griot_ai/core/constants/app_constants.dart';
import 'package:griot_ai/core/database/app_database.dart';
import 'package:griot_ai/features/discover/models/region_model.dart';

/// Guards the schema a **fresh install** receives.
///
/// `_onCreate` previously built only the v1 baseline tables and never replayed
/// the later migrations — sqflite does not call `onUpgrade` when it creates a
/// database — so a brand-new install had no `local_*` tables and every content
/// screen (stories, regions, artifacts, quizzes) came up empty. It also locks
/// in the v7 repair that links seeded quizzes to their story.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String dbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbPath = p.join(await getDatabasesPath(), AppConstants.databaseName);
  });

  // Every test starts from a deleted file so the fresh-install path (`onCreate`)
  // is the one under test. The database lives in the package's own
  // `.dart_tool/sqflite_common_ffi/databases` directory.
  setUp(() async {
    await AppDatabase.instance.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  Future<bool> hasTable(Database db, String name) async {
    final rows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  test('creates the whole local content schema on a fresh install', () async {
    final db = await AppDatabase.instance.database;

    for (final table in const [
      'local_users',
      'local_categories',
      'local_stories',
      'local_story_categories',
      'local_quizzes',
      'local_quiz_questions',
      'local_badges',
      'local_user_gamification',
      'local_quiz_attempts',
    ]) {
      expect(await hasTable(db, table), isTrue, reason: 'missing $table');
    }
  });

  test('seeds stories, each with cover art that exists on disk', () async {
    final db = await AppDatabase.instance.database;
    final stories = await db.query('local_stories');

    expect(stories, isNotEmpty);
    for (final story in stories) {
      final cover = story['cover_image'] as String?;
      expect(cover, isNotNull, reason: '${story['slug']} has no cover image');
      expect(
        File(cover as String).existsSync(),
        isTrue,
        reason: '${story['slug']} points at a missing asset ($cover)',
      );
    }
  });

  test('seeds categories and badges for the Home and Rewards rails', () async {
    final db = await AppDatabase.instance.database;

    expect(await db.query('local_categories'), isNotEmpty);
    expect(await db.query('local_badges'), isNotEmpty);
  });

  test('links every story-specific quiz to its story', () async {
    final db = await AppDatabase.instance.database;

    final orphans = await db.query(
      'local_quizzes',
      columns: ['title'],
      where: 'story_id IS NULL',
    );

    // The collection-wide culture quiz belongs to no single story, so it is the
    // only quiz allowed to stay unlinked.
    expect(orphans.map((q) => q['title']).toList(), [
      'Cameroon Cultural Heritage',
    ], reason: 'a story quiz with no story_id can never open from the reader');
  });

  test('links the French quiz to the French story edition', () async {
    final db = await AppDatabase.instance.database;

    final rows = await db.rawQuery('''
      SELECT s.slug AS slug
      FROM local_quizzes q
      JOIN local_stories s ON s.id = q.story_id
      WHERE q.language = 'fr'
    ''');

    expect(rows, isNotEmpty);
    expect(
      rows.map((r) => r['slug']).toList(),
      contains('anansi-wisdom-pot-fr'),
    );
  });

  test(
    'v7 repairs an install created without the local content schema',
    () async {
      // Simulate a device that ran the old `_onCreate`: v1 baseline tables only,
      // stamped at v6. This is exactly the state a device that has been running
      // the app since before the content layer landed is in.
      final broken = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (db, _) async {
            await db.execute('''
            CREATE TABLE story_cache (
              id       INTEGER PRIMARY KEY AUTOINCREMENT,
              story_id INTEGER NOT NULL UNIQUE,
              title    TEXT NOT NULL
            )
          ''');
            await db.execute('''
            CREATE TABLE search_history (
              id    INTEGER PRIMARY KEY AUTOINCREMENT,
              query TEXT NOT NULL
            )
          ''');
            await db.execute('''
            CREATE TABLE reading_progress (
              id              INTEGER PRIMARY KEY AUTOINCREMENT,
              story_id        INTEGER NOT NULL UNIQUE,
              scroll_fraction REAL NOT NULL DEFAULT 0
            )
          ''');
            await db.execute('''
            CREATE TABLE offline_requests (
              id     INTEGER PRIMARY KEY AUTOINCREMENT,
              method TEXT NOT NULL,
              path   TEXT NOT NULL
            )
          ''');
            await db.execute('''
            CREATE TABLE offline_users (
              id       INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              email    TEXT NOT NULL UNIQUE,
              password TEXT NOT NULL
            )
          ''');
          },
        ),
      );
      await broken.close();

      // Reopen through the app, which upgrades it to the current version.
      final db = await AppDatabase.instance.database;

      expect(await db.query('local_stories'), isNotEmpty);
      expect(await db.query('local_quiz_questions'), isNotEmpty);

      final orphans = await db.query(
        'local_quizzes',
        columns: ['title'],
        where: 'story_id IS NULL',
      );
      expect(orphans.map((q) => q['title']).toList(), [
        'Cameroon Cultural Heritage',
      ]);
    },
  );

  test('every Discover region owns a distinct image that exists', () {
    final seen = <String>{};

    for (final region in Regions.all) {
      expect(
        File(region.imageAsset).existsSync(),
        isTrue,
        reason: '${region.label} is missing ${region.imageAsset}',
      );
      expect(
        seen.add(region.imageAsset),
        isTrue,
        reason: '${region.label} reuses another region\'s image',
      );
    }
  });
}
