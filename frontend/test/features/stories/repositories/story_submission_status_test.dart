import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:griot_ai/core/database/app_database.dart';
import 'package:griot_ai/core/database/repositories/local_story_repository.dart';
import 'package:griot_ai/core/network/connectivity_service.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';
import 'package:griot_ai/features/stories/repositories/story_repository.dart';

/// A contributor submission must never read as public content on the device.
/// Before this landed, `LocalStoryRepository.createStory` hardcoded
/// `status = 'published'`, so a story written offline showed up in the public
/// feed as if a reviewer had approved it — and "Submit for Review" never sent
/// a status at all, so the server defaulted it to `draft` while the toast said
/// otherwise.
class _OfflineConnectivity extends Mock implements ConnectivityService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dbFileName = 'griot_submission_status_test.db';

  late AppDatabase appDb;
  late String dbPath;
  late LocalStoryRepository local;
  late _OfflineConnectivity connectivity;
  late StoryRepository repository;

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
    connectivity = _OfflineConnectivity();
    when(() => connectivity.isOnline).thenReturn(false);

    repository = StoryRepository(
      localStory: local,
      connectivityService: connectivity,
    );
  });

  tearDown(() async {
    await appDb.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  test('a locally created story is a draft, never published', () async {
    final created = await local.createStory(
      title: 'The Spider That Married a King',
      content: 'Long ago in Foumban...',
    );

    expect(created.status, 'draft');

    final feed = await local.getStories();
    expect(
      feed.where((s) => s.slug == created.slug),
      isEmpty,
      reason: 'an unreviewed submission must not appear in the public feed',
    );
  });

  test('a pending submission stays pending and out of the public feed',
      () async {
    final created = await local.createStory(
      title: 'Masks of the Kingdom',
      content: 'The masks were kept by the elders...',
      status: 'pending',
    );

    expect(created.status, 'pending');

    final feed = await local.getStories();
    expect(feed.where((s) => s.slug == created.slug), isEmpty);
  });

  test('only an approved story reaches the offline public feed', () async {
    await local.mirrorStories([
      const StoryModel(
        id: 5,
        slug: 'approved-tale',
        title: 'Approved Tale',
        author: UserModel(id: 2, username: 'reviewer'),
        content: 'A story a reviewer published.',
      ),
    ]);

    final feed = await local.getStories();
    expect(feed.map((s) => s.slug), contains('approved-tale'));
  });

  test('StoryRepository forwards the submission status while offline',
      () async {
    final story = await repository.createStory(
      title: 'Submitted Offline',
      content: 'Written on a train with no signal.',
      status: 'pending',
    );

    expect(story.status, 'pending');
    expect(
      (await local.getStory(story.slug)).status,
      'pending',
      reason: 'the queued copy must not claim approval either',
    );
  });

  test('StoryRepository defaults an unlabelled offline create to draft',
      () async {
    final story = await repository.createStory(
      title: 'No Status Given',
      content: 'The form forgot to say.',
    );

    expect(story.status, 'draft');
  });
}
