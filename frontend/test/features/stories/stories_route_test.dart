import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';
import 'package:griot_ai/features/stories/providers/story_provider.dart';
import 'package:griot_ai/features/stories/repositories/story_repository.dart';
import 'package:griot_ai/features/stories/screens/stories_screen.dart';
import 'package:griot_ai/features/stories/widgets/story_card.dart';

class _MockStoryRepository extends Mock implements StoryRepository {}

/// Stories without `coverImage` so the test never reaches the asset bundle.
List<StoryModel> _stories() => [
  StoryModel(
    id: 1,
    title: 'The Talking Drum of Foumban',
    slug: 'talking-drum-foumban',
    summary: 'The legendary drum that spoke the truth.',
    region: 'Bamoun',
    estimatedReadTime: 7,
    author: const UserModel(id: 1, username: 'nana'),
  ),
  StoryModel(
    id: 2,
    title: 'Why the Chameleon Changes Color',
    slug: 'chameleon-color',
    summary: 'A cautionary tale about pride.',
    region: 'Adamawa',
    estimatedReadTime: 5,
    author: const UserModel(id: 2, username: 'amara'),
  ),
];

void main() {
  late _MockStoryRepository repository;

  setUp(() {
    repository = _MockStoryRepository();
    when(
      () => repository.getStories(
        page: any(named: 'page'),
        sort: any(named: 'sort'),
      ),
    ).thenAnswer((_) async => _stories());
    when(repository.getCategories).thenAnswer((_) async => const []);
  });

  /// The screen is reachable as a pushed route (Home's "See all" and the
  /// category pills), which renders it outside `MainShell`. It previously
  /// returned a bare `Column`, so a pushed instance had no background and no
  /// safe insets — content ran under the status bar over a transparent page.
  testWidgets('StoriesScreen supplies its own Scaffold and SafeArea', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storyRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(theme: AppTheme.light, home: const StoriesScreen()),
      ),
    );
    await tester.pump();

    final scaffoldFinder = find.byType(Scaffold);
    expect(scaffoldFinder, findsOneWidget);

    // The app bar-less screen still needs a background and status-bar inset.
    final scaffold = tester.widget<Scaffold>(scaffoldFinder);
    expect(scaffold.body, isA<SafeArea>());
    expect(
      scaffold.backgroundColor ?? AppTheme.light.scaffoldBackgroundColor,
      isNotNull,
    );

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('StoriesScreen renders the seeded cards inside its own route', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storyRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(theme: AppTheme.light, home: const StoriesScreen()),
      ),
    );
    // initState schedules the first load on a post-frame callback.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(StoryCard), findsNWidgets(2));
    expect(find.text('The Talking Drum of Foumban'), findsOneWidget);
  });
}
