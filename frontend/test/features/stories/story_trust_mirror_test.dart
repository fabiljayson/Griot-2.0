import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:griot_ai/core/database/app_database.dart';
import 'package:griot_ai/core/database/repositories/local_story_repository.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';

/// The offline mirror must carry the Cultural Trust Score with it.
///
/// Offline is exactly where a reader cannot check anything, so a story whose
/// review was dropped on the way into SQLite would render identically to an
/// unchecked one — the failure mode v10 of the schema exists to prevent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late String dbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = AppDatabase.forTesting(name: 'griot_trust_mirror_test.db');
    dbPath = p.join(await getDatabasesPath(), 'griot_trust_mirror_test.db');
  });

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

  StoryModel storyWithTrust() {
    return StoryModel.fromJson(const {
      'id': 9,
      'title': 'A Reviewed Tale',
      'slug': 'a-reviewed-tale',
      'content': 'Long enough to matter.',
      'author': {'id': 1, 'username': 'teller'},
      'trust_score': 65,
      'trust_level': 'partial',
      'sources': [
        {
          'id': 3,
          'source_type': 'ORAL_TRADITION',
          'name': 'Foumban elders',
          'is_verified': true,
        },
      ],
      'verification': {
        'source_verified': true,
        'community_validated': true,
        'trust_score': 65,
        'trust_level': 'partial',
        'disclaimer': 'Measures documentation strength, not truth.',
        'reviewer': 'manager1',
      },
    });
  }

  test('a mirrored story keeps its score, sources and verification', () async {
    final repo = LocalStoryRepository(database: db);
    await repo.mirrorStories([storyWithTrust()]);

    final restored = await repo.getStory('a-reviewed-tale');

    expect(restored.trustScore, 65);
    expect(restored.trustLevel, 'partial');
    expect(restored.sources, hasLength(1));
    expect(restored.sources.first.name, 'Foumban elders');
    expect(restored.sources.first.isVerified, isTrue);
    expect(restored.verification, isNotNull);
    expect(restored.verification!.trustScore, 65);
    expect(restored.verification!.reviewer, 'manager1');
    expect(restored.verification!.disclaimer, contains('not truth'));
  });

  test('a story cached before review tracks it defaults to unverified',
      () async {
    final repo = LocalStoryRepository(database: db);
    await repo.mirrorStories([
      StoryModel.fromJson(const {
        'id': 10,
        'title': 'An Untouched Tale',
        'slug': 'an-untouched-tale',
        'content': 'Nothing reviewed here.',
        'author': {'id': 1, 'username': 'teller'},
      }),
    ]);

    final restored = await repo.getStory('an-untouched-tale');

    expect(restored.trustScore, 0);
    expect(restored.trustLevel, 'unverified');
    expect(restored.sources, isEmpty);
    expect(restored.verification, isNull);
  });

  test('re-mirroring replaces the previous review with the server copy',
      () async {
    final repo = LocalStoryRepository(database: db);
    await repo.mirrorStories([storyWithTrust()]);
    await repo.mirrorStories([
      storyWithTrust().copyWith(trustScore: 100, trustLevel: 'verified'),
    ]);

    final restored = await repo.getStory('a-reviewed-tale');

    expect(restored.trustScore, 100);
    expect(restored.trustLevel, 'verified');
  });
}
