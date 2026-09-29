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

  group('v8 removes the plaintext credential columns', () {
    Future<Set<String>> columnsOf(Database db, String table) async {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      return rows.map((r) => r['name'] as String).toSet();
    }

    test('a fresh install has no password column on either user table',
        () async {
      final db = await AppDatabase.instance.database;

      final local = await columnsOf(db, 'local_users');
      expect(local, isNot(contains('password')));
      expect(local, contains('password_hash'));

      final offline = await columnsOf(db, 'offline_users');
      expect(offline, isNot(contains('password')));
    });

    test('a fresh install stores no plaintext password anywhere', () async {
      final db = await AppDatabase.instance.database;

      // Debug builds seed demo accounts; they must be hashed like any other
      // local account rather than carrying the password itself.
      final rows = await db.query(
        'local_users',
        columns: ['username', 'password_hash'],
      );
      for (final row in rows) {
        final hash = row['password_hash'] as String?;
        if (hash == null) continue;
        expect(
          hash,
          startsWith(r'pbkdf2_sha256$'),
          reason: '${row['username']} is not hashed',
        );
        expect(hash, isNot(contains('123')));
      }
    });

    test(
        'an upgraded install drops the stored plaintext but keeps the account',
        () async {
      // A device from before v8: full v4/v3 shape, with a real reader account
      // whose password is sitting in the clear.
      final old = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, _) async {
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
              "INSERT INTO local_users "
              "(username, email, password, first_name, last_name, role) "
              "VALUES ('amara', 'amara@example.com', 'plaintext-secret', "
              "'Amara', 'Nkomo', 'visitor')",
            );
            await db.execute(
              "INSERT INTO offline_users "
              "(username, email, password, status) "
              "VALUES ('queued', 'queued@example.com', 'queued-secret', "
              "'pending')",
            );
          },
        ),
      );
      await old.close();

      final db = await AppDatabase.instance.database;

      expect(await columnsOf(db, 'local_users'), isNot(contains('password')));

      // The reader's account survives; only the secret is gone.
      final kept = await db.query(
        'local_users',
        where: 'username = ?',
        whereArgs: ['amara'],
      );
      expect(kept, hasLength(1));
      expect(kept.first['email'], 'amara@example.com');
      // NULL means "no local password" — the reader must reset rather than
      // fall back to accepting the old plaintext.
      expect(kept.first['password_hash'], isNull);

      // The secret is genuinely gone from the file, not merely hidden behind a
      // different column name.
      final dump = await db.rawQuery('SELECT * FROM local_users');
      expect(dump.toString(), isNot(contains('plaintext-secret')));

      // A queued registration cannot be replayed, so it is reported as failed
      // rather than retried with a secret that is no longer available.
      final queued = await db.query('offline_users');
      expect(queued, hasLength(1));
      expect(queued.first['status'], 'failed');
      expect(await columnsOf(db, 'offline_users'), isNot(contains('password')));
      expect((await db.rawQuery('SELECT * FROM offline_users')).toString(),
          isNot(contains('queued-secret')));
    });

    test('v8 deletes the demo accounts seeded by earlier versions', () async {
      final old = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, _) async {
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
            for (final row in [
              ('admin', 'admin@griot-ai.com'),
              ('visitor1', 'visitor1@griot-ai.com'),
              ('contributor1', 'contributor1@griot-ai.com'),
              ('amara', 'amara@example.com'),
            ]) {
              await db.execute(
                'INSERT INTO local_users (username, email, password) '
                "VALUES ('${row.$1}', '${row.$2}', 'admin123')",
              );
            }
          },
        ),
      );
      await old.close();

      final db = await AppDatabase.instance.database;
      final remaining = await db.query('local_users', columns: ['username']);

      expect(
        remaining.map((r) => r['username']),
        ['amara'],
        reason: 'known-credential demo accounts must not survive the upgrade',
      );
    });
  });
}
