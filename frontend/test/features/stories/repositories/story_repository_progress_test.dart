import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:griot_ai/core/database/app_database.dart';
import 'package:griot_ai/core/database/repositories/local_story_repository.dart';
import 'package:griot_ai/core/database/repositories/reading_progress_repository.dart';
import 'package:griot_ai/core/network/connectivity_service.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';
import 'package:griot_ai/features/stories/repositories/story_repository.dart';

/// The API only knows a reader's position once they are authenticated and
/// the push has landed — guests, local-only accounts and writes still queued
/// offline all come back with `reading_progress: null`. The detail screen
/// still has to resume those readers, which means `getStory` folds in the
/// locally stored position whenever the payload carries none.
class _OfflineConnectivity extends Mock implements ConnectivityService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dbFileName = 'griot_progress_merge_test.db';

  late AppDatabase appDb;
  late String dbPath;
  late LocalStoryRepository local;
  late ReadingProgressRepository progress;
  late _OfflineConnectivity connectivity;
  late StoryRepository repository;

  final story = StoryModel(
    id: 77,
    slug: 'the-restored-reading',
    title: 'The Restored Reading',
    author: const UserModel(id: 1, username: 'tester'),
    content: 'A story long enough to scroll.',
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbPath = p.join(await getDatabasesPath(), dbFileName);
  });

  setUp(() async {
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
    appDb = AppDatabase.forTesting(name: dbFileName);

    local = LocalStoryRepository(database: appDb);
    progress = ReadingProgressRepository(database: appDb);
    connectivity = _OfflineConnectivity();
    when(() => connectivity.isOnline).thenReturn(false);

    repository = StoryRepository(
      localStory: local,
      connectivityService: connectivity,
      readingProgress: progress,
    );
  });

  tearDown(() async {
    await appDb.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  test('an offline reader resumes from the locally stored position', () async {
    await local.mirrorStories([story]);
    await local.updateReadingProgress(
      story.slug,
      percent: 42,
      lastPosition: 1200,
    );

    final result = await repository.getStory(story.slug);

    expect(result.readingProgress, isNotNull);
    expect(result.readingProgress!.percent, 42);
    expect(result.readingProgress!.lastPosition, 1200);
    expect(result.readingProgress!.completed, isFalse);
  });

  test('a story never read keeps a null reading_progress', () async {
    await local.mirrorStories([story]);

    final result = await repository.getStory(story.slug);

    expect(result.readingProgress, isNull);
  });

  test('progress past the completed threshold is reported completed', () async {
    await local.mirrorStories([story]);
    await local.updateReadingProgress(story.slug, percent: 97);

    final result = await repository.getStory(story.slug);

    expect(result.readingProgress!.percent, 97);
    expect(result.readingProgress!.completed, isTrue);
  });
}
