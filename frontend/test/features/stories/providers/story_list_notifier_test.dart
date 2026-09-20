import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';
import 'package:griot_ai/features/stories/providers/story_provider.dart';
import 'package:griot_ai/features/stories/repositories/story_repository.dart';

// --- Mocks ---

class MockStoryRepository extends Mock implements StoryRepository {}

// --- Helpers ---

StoryModel _fakeStory({int id = 1, String title = 'Test Story'}) {
  return StoryModel(
    id: id,
    title: title,
    slug: 'test-$id',
    author: const UserModel(id: 1, username: 'author'),
  );
}

List<StoryModel> _fakeStories(int count, {int startId = 1}) {
  return List.generate(
    count,
    (i) => _fakeStory(id: startId + i, title: 'Story ${startId + i}'),
  );
}

/// Helper to extract stories from any StoryListState subtype.
List<StoryModel> _stories(StoryListState s) => switch (s) {
  StoryListReady(:final stories) => stories,
  StoryListLoading(:final stories) => stories,
  _ => [],
};

/// Helper to get hasMore from StoryListReady.
bool _hasMore(StoryListState s) =>
    s is StoryListReady ? s.hasMore : false;

/// Helper to get currentPage from StoryListReady.
int _currentPage(StoryListState s) =>
    s is StoryListReady ? s.currentPage : 1;

void main() {
  setUpAll(() {
    registerFallbackValue(const StoryListInitial());
  });

  group('StoryListNotifier', () {
    late MockStoryRepository mockRepo;
    late ProviderContainer container;

    setUp(() {
      mockRepo = MockStoryRepository();
      container = ProviderContainer(
        overrides: [
          storyRepositoryProvider.overrideWithValue(mockRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    // --- Initial state ---

    test('should start as StoryListInitial', () {
      final s = container.read(storyListProvider);
      expect(s, isA<StoryListInitial>());
    });

    // --- Load stories ---

    test('should transition to StoryListReady with loaded stories', () async {
      final fakeStories = _fakeStories(5);
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => fakeStories);

      await container.read(storyListProvider.notifier).loadStories();

      final s = container.read(storyListProvider);
      expect(s, isA<StoryListReady>());
      expect(_stories(s), hasLength(5));
      expect(_hasMore(s), false); // 5 < 20 = incomplete page
      expect(_currentPage(s), 2);
    });

    test('should set hasMore to false when fewer than 20 stories returned',
        () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => _fakeStories(15));

      await container.read(storyListProvider.notifier).loadStories();

      expect(_hasMore(container.read(storyListProvider)), false);
    });

    test('should set hasMore to true when 20 or more stories returned',
        () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => _fakeStories(20));

      await container.read(storyListProvider.notifier).loadStories();

      expect(_hasMore(container.read(storyListProvider)), true);
    });

    test('should append stories on loadMore', () async {
      final page1 = _fakeStories(20, startId: 1);
      final page2 = _fakeStories(5, startId: 21);
      final notifier = container.read(storyListProvider.notifier);

      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => page1);

      await notifier.loadStories();
      expect(_stories(container.read(storyListProvider)), hasLength(20));
      expect(_hasMore(container.read(storyListProvider)), true);

      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => page2);

      await notifier.loadMore();
      expect(_stories(container.read(storyListProvider)), hasLength(25));
    });

    test('should refresh from page 1 when refresh is true', () async {
      final page1 = _fakeStories(5, startId: 1);
      final fresh = _fakeStories(3, startId: 100);
      final notifier = container.read(storyListProvider.notifier);

      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => page1);

      await notifier.loadStories();
      expect(_stories(container.read(storyListProvider)), hasLength(5));

      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => fresh);

      await notifier.loadStories(refresh: true);
      final stories = _stories(container.read(storyListProvider));
      expect(stories, hasLength(3));
      expect(stories.first.title, 'Story 100');
    });

    // --- Filters ---

    test('should pass language filter to repository', () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
            language: any(named: 'language'),
          )).thenAnswer((_) async => []);

      await container.read(storyListProvider.notifier).filterByLanguage('fr');

      verify(() => mockRepo.getStories(
            page: 1,
            sort: '-created_at',
            language: 'fr',
          )).called(1);
    });

    test('should pass category filter to repository', () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
            category: any(named: 'category'),
          )).thenAnswer((_) async => []);

      await container
          .read(storyListProvider.notifier)
          .filterByCategory('Folktales');

      verify(() => mockRepo.getStories(
            page: 1,
            sort: '-created_at',
            category: 'Folktales',
          )).called(1);
    });

    test('should pass region filter to repository', () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
            region: any(named: 'region'),
          )).thenAnswer((_) async => []);

      await container.read(storyListProvider.notifier).filterByRegion('Bamoun');

      verify(() => mockRepo.getStories(
            page: 1,
            sort: '-created_at',
            region: 'Bamoun',
          )).called(1);
    });

    test('should preserve language filter when category is set', () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
            language: any(named: 'language'),
            category: any(named: 'category'),
          )).thenAnswer((_) async => []);

      final notifier = container.read(storyListProvider.notifier);
      await notifier.filterByLanguage('fr');
      await notifier.filterByCategory('Folktales');

      verify(() => mockRepo.getStories(
            page: 1,
            sort: '-created_at',
            language: 'fr',
            category: 'Folktales',
          )).called(1);
    });

    test('should preserve all filters when region is set', () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
            language: any(named: 'language'),
            category: any(named: 'category'),
            region: any(named: 'region'),
          )).thenAnswer((_) async => []);

      final notifier = container.read(storyListProvider.notifier);
      await notifier.filterByLanguage('en');
      await notifier.filterByCategory('Myths');
      await notifier.filterByRegion('Adamawa');

      verify(() => mockRepo.getStories(
            page: 1,
            sort: '-created_at',
            language: 'en',
            category: 'Myths',
            region: 'Adamawa',
          )).called(1);
    });

    // --- Clear filters ---

    test('clearFilters should reset all filters', () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
            language: any(named: 'language'),
            category: any(named: 'category'),
            region: any(named: 'region'),
          )).thenAnswer((_) async => []);

      final notifier = container.read(storyListProvider.notifier);
      await notifier.filterByLanguage('fr');
      await notifier.filterByCategory('Folktales');
      await notifier.filterByRegion('Bamoun');

      // Now clear
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async => []);

      await notifier.clearFilters();

      verify(() => mockRepo.getStories(
            page: 1,
            sort: '-created_at',
          )).called(1);
    });

    // --- Search ---

    test('should pass search query to repository', () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
            search: any(named: 'search'),
          )).thenAnswer((_) async => []);

      await container.read(storyListProvider.notifier).search('lion');

      verify(() => mockRepo.getStories(
            page: 1,
            sort: '-created_at',
            search: 'lion',
          )).called(1);
    });

    // --- Error handling ---

    test('should transition to StoryListFailure on exception', () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).thenThrow(Exception('Network error'));

      await container.read(storyListProvider.notifier).loadStories();

      final s = container.read(storyListProvider);
      expect(s, isA<StoryListFailure>());
      expect((s as StoryListFailure).message, isNotEmpty);
    });

    // --- Duplicate load prevention ---

    test('should not load if already loading', () async {
      when(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 5));
        return _fakeStories(3);
      });

      final notifier = container.read(storyListProvider.notifier);
      final future1 = notifier.loadStories();
      await notifier.loadStories();

      await future1;

      verify(() => mockRepo.getStories(
            page: any(named: 'page'),
            sort: any(named: 'sort'),
          )).called(1);
    });
  });
}
