import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/widgets/app_components.dart';
import 'package:griot_ai/features/audio/models/audio_model.dart';
import 'package:griot_ai/features/audio/providers/audio_provider.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/auth/providers/auth_provider.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';
import 'package:griot_ai/features/stories/providers/story_provider.dart';
import 'package:griot_ai/features/stories/repositories/story_repository.dart';
import 'package:griot_ai/features/stories/screens/story_detail_screen.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

class _SignedOutAuthNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      const AuthState(status: AuthStatus.unauthenticated);
}

class _IdleAudioPlayerNotifier extends AudioPlayerNotifier {
  _IdleAudioPlayerNotifier() {
    state = const AudioPlayerState();
  }
}

/// Saved reading progress must actually put the reader back where they were:
/// the detail screen collects `reading_progress` on every load, but a value
/// nobody restores from is decoration. The jump also has to stay silent —
/// the restore fires scroll events, and letting them reach the progress
/// listener would persist the position the reader had *before* the jump.
void main() {
  final longContent = List.filled(
    100,
    'A paragraph of the story, long enough that the page must scroll.',
  ).join('\n\n');

  StoryModel storyWithProgress({int percent = 50, int lastPosition = 1200}) =>
      StoryModel(
        id: 7,
        slug: 'the-restored-reading',
        title: 'The Restored Reading',
        author: const UserModel(id: 1, username: 'tester'),
        content: longContent,
        readingProgress: ReadingProgressData(
          percent: percent,
          lastPosition: lastPosition,
          completed: percent >= 95,
        ),
      );

  Future<void> pumpStoryScreen(
    WidgetTester tester,
    _MockStoryRepository repository,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storyRepositoryProvider.overrideWithValue(repository),
          authProvider.overrideWith(() => _SignedOutAuthNotifier()),
          audioPlayerProvider.overrideWith((ref) => _IdleAudioPlayerNotifier()),
        ],
        child: const MaterialApp(
          home: StoryDetailScreen(slug: 'the-restored-reading'),
        ),
      ),
    );
    // Frames: loadStory resolves → Ready builds → restore schedules →
    // restore jumps (or exhausts its retries) → finish reconciles.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  ScrollableState scrollableState(WidgetTester tester) {
    // The story is selectable, so every paragraph owns a zero-extent
    // Scrollable too; the reader's is the only one that can actually scroll.
    final states =
        tester.stateList<ScrollableState>(find.byType(Scrollable)).toList()
          ..sort(
            (a, b) => b.position.maxScrollExtent.compareTo(
              a.position.maxScrollExtent,
            ),
          );
    expect(states.first.position.maxScrollExtent, greaterThan(1000));
    return states.first;
  }

  testWidgets('resumes the reader at the saved scroll offset', (tester) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.getStory(any()),
    ).thenAnswer((_) async => storyWithProgress());

    await pumpStoryScreen(tester, repository);

    // The row lives above the story body, so the restored jump scrolls it
    // out of the viewport — it is still in the tree, just no longer onstage.
    final progressRow = tester.widget<ProgressRow>(
      find.byType(ProgressRow, skipOffstage: false),
    );

    final readerScroll = scrollableState(tester);
    expect(
      readerScroll.position.pixels,
      inInclusiveRange(1150, 1250),
      reason: 'the viewport must jump to the saved offset',
    );
    expect(
      progressRow.fraction,
      closeTo(
        readerScroll.position.pixels / readerScroll.position.maxScrollExtent,
        0.01,
      ),
      reason: 'after the jump the bar must show where the reader actually is',
    );

    verifyNever(
      () => repository.updateReadingProgress(
        any(),
        percent: any(named: 'percent'),
        lastPosition: any(named: 'lastPosition'),
        completed: any(named: 'completed'),
      ),
    );
  });

  testWidgets('seeds the percent but stays put when no offset is saved', (
    tester,
  ) async {
    final repository = _MockStoryRepository();
    when(
      () => repository.getStory(any()),
    ).thenAnswer((_) async => storyWithProgress(percent: 60, lastPosition: 0));

    await pumpStoryScreen(tester, repository);

    expect(
      tester.widget<ProgressRow>(find.byType(ProgressRow)).fraction,
      closeTo(0.6, 0.001),
    );
    expect(scrollableState(tester).position.pixels, 0);
  });

  testWidgets('a never-read story starts at the top with an empty bar', (
    tester,
  ) async {
    final repository = _MockStoryRepository();
    when(() => repository.getStory(any())).thenAnswer(
      (_) async => StoryModel(
        id: 7,
        slug: 'the-restored-reading',
        title: 'The Restored Reading',
        author: const UserModel(id: 1, username: 'tester'),
        content: longContent,
      ),
    );

    await pumpStoryScreen(tester, repository);

    expect(tester.widget<ProgressRow>(find.byType(ProgressRow)).fraction, 0.0);
    expect(scrollableState(tester).position.pixels, 0);
  });
}
