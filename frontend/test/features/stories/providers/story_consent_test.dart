import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';
import 'package:griot_ai/features/stories/providers/story_provider.dart';
import 'package:griot_ai/features/stories/repositories/story_repository.dart';

class MockStoryRepository extends Mock implements StoryRepository {}

/// The author's half of the consent record, from the notifier's side.
///
/// The decision itself belongs to a moderator on another screen; what is
/// asserted here is that pressing "I have asked" actually reaches the server
/// and that the story on screen then says `pending` — the failure mode being a
/// button that reports success and leaves the field at `not_requested`.
void main() {
  late MockStoryRepository repository;
  late ProviderContainer container;

  StoryModel storyWithConsent(String consentStatus) => StoryModel(
    id: 1,
    title: 'The Baobab and the Drum',
    slug: 'the-baobab-and-the-drum',
    author: const UserModel(id: 7, username: 'moussa'),
    consentStatus: consentStatus,
  );

  setUp(() {
    repository = MockStoryRepository();
    container = ProviderContainer(
      overrides: [storyRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  test('records that the author asked, and shows the server\'s answer', () async {
    when(() => repository.getStory(any()))
        .thenAnswer((_) async => storyWithConsent('not_requested'));
    when(() => repository.requestConsent('the-baobab-and-the-drum'))
        .thenAnswer((_) async => 'pending');

    await container.read(storyDetailProvider.notifier).loadStory(
      'the-baobab-and-the-drum',
    );
    final status = await container
        .read(storyDetailProvider.notifier)
        .requestConsent();

    expect(status, 'pending');
    verify(() => repository.requestConsent('the-baobab-and-the-drum')).called(1);

    final state = container.read(storyDetailProvider);
    expect(state, isA<StoryDetailReady>());
    expect(
      (state as StoryDetailReady).story.consentStatus,
      'pending',
      reason: 'the screen must stop offering "I have asked" once it is on record',
    );
  });

  test('does nothing when no story is loaded', () async {
    final status = await container
        .read(storyDetailProvider.notifier)
        .requestConsent();

    expect(status, isNull);
    verifyNever(() => repository.requestConsent(any()));
  });

  test('a failure is not swallowed', () async {
    when(() => repository.getStory(any()))
        .thenAnswer((_) async => storyWithConsent('not_requested'));
    when(() => repository.requestConsent(any())).thenThrow(Exception('offline'));

    await container.read(storyDetailProvider.notifier).loadStory('any-slug');

    // Rethrown, so the button can tell the contributor it did not save rather
    // than leaving them believing they had asked.
    await expectLater(
      container.read(storyDetailProvider.notifier).requestConsent(),
      throwsA(isA<Exception>()),
    );
    final state = container.read(storyDetailProvider);
    expect((state as StoryDetailReady).story.consentStatus, 'not_requested');
  });
}