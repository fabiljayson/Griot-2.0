import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:griot_ai/core/database/app_database.dart';
import 'package:griot_ai/core/database/models/cached_story.dart';
import 'package:griot_ai/core/database/repositories/reading_progress_repository.dart';
import 'package:griot_ai/core/database/repositories/search_history_repository.dart';
import 'package:griot_ai/core/database/repositories/story_cache_repository.dart';

/// Guards the OTA-facing local repositories against the real SQLite schema.
///
/// Uses the same sqflite_common_ffi fixture as `app_database_schema_test.dart`
/// so `onCreate`/`onUpgrade` (not hand-rolled tables) are what the queries
/// run against.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late String dbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // A dedicated file so this suite never races the shared
    // `AppDatabase.instance` (used by app_database_schema_test.dart) when
    // `flutter test` runs suites in parallel isolates.
    db = AppDatabase.forTesting(name: 'griot_repo_test.db');
    dbPath = p.join(await getDatabasesPath(), 'griot_repo_test.db');
  });

  // Every test starts from a deleted file so the fresh-install path is the one
  // under test.
  setUp(() async {
    await db.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  tearDown(() async {
    await db.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  group('ReadingProgressRepository', () {
    test('returns null for a story that was never opened', () async {
      final repo = ReadingProgressRepository(database: db);
      expect(await repo.getProgress(1), isNull);
    });

    test('saves and reads back scroll + audio resume progress', () async {
      final repo = ReadingProgressRepository(database: db);
      await repo.saveProgress(
        storyId: 7,
        scrollFraction: 0.42,
        audioResumeSeconds: 15,
      );

      final progress = await repo.getProgress(7);
      expect(progress, isNotNull);
      expect(progress!.storyId, 7);
      expect(progress.scrollFraction, closeTo(0.42, 0.001));
      expect(progress.audioResumeSeconds, 15);
    });

    test('upserts by story_id instead of accumulating rows', () async {
      final repo = ReadingProgressRepository(database: db);
      await repo.saveProgress(
        storyId: 7,
        scrollFraction: 0.1,
        audioResumeSeconds: 5,
      );
      await repo.saveProgress(
        storyId: 7,
        scrollFraction: 0.9,
        audioResumeSeconds: 90,
      );

      final progress = await repo.getProgress(7);
      expect(progress!.scrollFraction, closeTo(0.9, 0.001));
      expect(progress.audioResumeSeconds, 90);

      final connection = await db.database;
      final rows = await connection.query(
        'reading_progress',
        where: 'story_id = ?',
        whereArgs: [7],
      );
      expect(rows, hasLength(1));
    });
  });

  group('StoryCacheRepository', () {
    const story = CachedStory(
      storyId: 3,
      title: 'Anansi the Wise',
      category: 'Folklore',
      region: 'Centre',
      contentMarkdown: '# Chapter 1',
      estimatedReadTime: 12,
    );

    test('starts empty', () async {
      final repo = StoryCacheRepository(database: db);
      expect(await repo.count(), 0);
      expect(await repo.isSaved(3), isFalse);
    });

    test('round-trips a cached story', () async {
      final repo = StoryCacheRepository(database: db);
      await repo.saveStory(story);

      expect(await repo.isSaved(3), isTrue);
      final loaded = await repo.getStory(3);
      expect(loaded, isNotNull);
      expect(loaded!.storyId, 3);
      expect(loaded.title, 'Anansi the Wise');
      expect(loaded.category, 'Folklore');
      expect(loaded.contentMarkdown, '# Chapter 1');
      expect(loaded.estimatedReadTime, 12);
    });

    test('update replaces the previous copy in place', () async {
      final repo = StoryCacheRepository(database: db);
      await repo.saveStory(story);
      await repo.saveStory(
        const CachedStory(storyId: 3, title: 'Anansi Rewritten'),
      );

      final loaded = await repo.getStory(3);
      expect(loaded!.title, 'Anansi Rewritten');
      expect(await repo.count(), 1);
    });

    test('flips the favorite flag independently of the story copy', () async {
      final repo = StoryCacheRepository(database: db);
      await repo.saveStory(story);

      await repo.setFavorite(3, true);
      expect((await repo.getStory(3))!.isFavorite, isTrue);

      await repo.setFavorite(3, false);
      expect((await repo.getStory(3))!.isFavorite, isFalse);
    });

    test('deleteStory only removes that story; clear wipes the cache', () async {
      final repo = StoryCacheRepository(database: db);
      await repo.saveStory(story);
      await repo.saveStory(
        const CachedStory(storyId: 9, title: 'Tortoise and the Drum'),
      );

      await repo.deleteStory(3);
      expect(await repo.isSaved(3), isFalse);
      expect(await repo.isSaved(9), isTrue);

      await repo.clear();
      expect(await repo.count(), 0);
    });
  });

  group('SearchHistoryRepository', () {
    test('ignores blank queries', () async {
      final repo = SearchHistoryRepository(database: db);
      await repo.addQuery('   ');
      await repo.addQuery('');
      expect(await repo.recentQueries(), isEmpty);
    });

    test('trims surrounding whitespace', () async {
      final repo = SearchHistoryRepository(database: db);
      await repo.addQuery('  spider  ');
      expect(await repo.recentQueries(), ['spider']);
    });

    test('returns most recent queries first', () async {
      final repo = SearchHistoryRepository(database: db);
      await repo.addQuery('anansi');
      await repo.addQuery('tortoise');
      expect(await repo.recentQueries(), ['tortoise', 'anansi']);
    });

    test('deduplicates identical queries (case-insensitive)', () async {
      final repo = SearchHistoryRepository(database: db);
      await repo.addQuery('Spider');
      await repo.addQuery('spider');
      await repo.addQuery('SPIDER');
      expect(await repo.recentQueries(), ['SPIDER']);
    });

    test('re-running an old query moves it to the front', () async {
      final repo = SearchHistoryRepository(database: db);
      await repo.addQuery('anansi');
      await repo.addQuery('tortoise');
      await repo.addQuery('anansi');
      expect(await repo.recentQueries(), ['anansi', 'tortoise']);
    });

    test('respects the limit argument', () async {
      final repo = SearchHistoryRepository(database: db);
      for (var i = 0; i < 5; i++) {
        await repo.addQuery('query-$i');
      }
      expect(await repo.recentQueries(limit: 2), ['query-4', 'query-3']);
    });

    test('caps history at maxEntries', () async {
      final repo = SearchHistoryRepository(database: db);
      for (var i = 0; i < 35; i++) {
        await repo.addQuery('query-$i');
      }
      final queries = await repo.recentQueries(limit: 100);
      expect(queries, hasLength(SearchHistoryRepository.maxEntries));
      expect(queries.first, 'query-34');
    });

    test('clear removes the whole history', () async {
      final repo = SearchHistoryRepository(database: db);
      await repo.addQuery('anansi');
      await repo.clear();
      expect(await repo.recentQueries(), isEmpty);
    });
  });
}