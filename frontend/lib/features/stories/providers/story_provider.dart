import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/story_model.dart';
import '../repositories/story_repository.dart';

/// State for story list.
class StoryListState {
  const StoryListState({
    this.stories = const [],
    this.isLoading = false,
    this.errorMessage,
    this.hasMore = true,
    this.currentPage = 1,
    this.searchQuery = '',
    this.selectedLanguage,
    this.selectedCategory,
    this.selectedRegion,
    this.sortBy = '-created_at',
  });

  final List<StoryModel> stories;
  final bool isLoading;
  final String? errorMessage;
  final bool hasMore;
  final int currentPage;
  final String searchQuery;
  final String? selectedLanguage;
  final String? selectedCategory;
  final String? selectedRegion;
  final String sortBy;

  StoryListState copyWith({
    List<StoryModel>? stories,
    bool? isLoading,
    String? errorMessage,
    bool? hasMore,
    int? currentPage,
    String? searchQuery,
    String? selectedLanguage,
    String? selectedCategory,
    String? selectedRegion,
    String? sortBy,
  }) {
    return StoryListState(
      stories: stories ?? this.stories,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedLanguage: selectedLanguage,
      selectedCategory: selectedCategory,
      selectedRegion: selectedRegion,
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

/// Notifier managing story list state.
class StoryListNotifier extends StateNotifier<StoryListState> {
  StoryListNotifier(this._repository) : super(const StoryListState());

  final StoryRepository _repository;

  /// Load stories (initial load or refresh).
  Future<void> loadStories({bool refresh = false}) async {
    if (state.isLoading) return;

    final page = refresh ? 1 : state.currentPage;
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final stories = await _repository.getStories(
        search: state.searchQuery.isNotEmpty ? state.searchQuery : null,
        language: state.selectedLanguage,
        category: state.selectedCategory,
        region: state.selectedRegion,
        sort: state.sortBy,
        page: page,
      );

      state = state.copyWith(
        stories: refresh ? stories : [...state.stories, ...stories],
        isLoading: false,
        hasMore: stories.length >= 20, // PAGE_SIZE from backend
        currentPage: page + 1,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _extractErrorMessage(e),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Load more stories (pagination).
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    await loadStories();
  }

  /// Search stories.
  Future<void> search(String query) async {
    state = state.copyWith(searchQuery: query);
    await loadStories(refresh: true);
  }

  /// Filter by language.
  Future<void> filterByLanguage(String? language) async {
    state = state.copyWith(selectedLanguage: language);
    await loadStories(refresh: true);
  }

  /// Filter by category.
  Future<void> filterByCategory(String? category) async {
    state = state.copyWith(selectedCategory: category);
    await loadStories(refresh: true);
  }

  /// Filter by region.
  Future<void> filterByRegion(String? region) async {
    state = state.copyWith(selectedRegion: region);
    await loadStories(refresh: true);
  }

  /// Sort stories.
  Future<void> sortBy(String sort) async {
    state = state.copyWith(sortBy: sort);
    await loadStories(refresh: true);
  }

  /// Clear all filters.
  Future<void> clearFilters() async {
    state = const StoryListState();
    await loadStories(refresh: true);
  }

  /// Toggle bookmark on a story.
  Future<void> toggleBookmark(String slug) async {
    try {
      final isBookmarked = await _repository.toggleBookmark(slug);
      state = state.copyWith(
        stories: state.stories.map((s) {
          if (s.slug == slug) {
            return s.copyWith(
              isBookmarked: isBookmarked,
              bookmarkCount: isBookmarked
                  ? s.bookmarkCount + 1
                  : s.bookmarkCount - 1,
            );
          }
          return s;
        }).toList(),
      );
    } catch (e) {
      // Silently fail for interactions
    }
  }

  /// Toggle like on a story.
  Future<void> toggleLike(String slug) async {
    try {
      final isLiked = await _repository.toggleLike(slug);
      state = state.copyWith(
        stories: state.stories.map((s) {
          if (s.slug == slug) {
            return s.copyWith(
              isLiked: isLiked,
              likeCount: isLiked ? s.likeCount + 1 : s.likeCount - 1,
            );
          }
          return s;
        }).toList(),
      );
    } catch (e) {
      // Silently fail for interactions
    }
  }

  String _extractErrorMessage(DioException e) {
    if (e.response?.data is Map) {
      final data = e.response!.data as Map<String, dynamic>;
      if (data.containsKey('detail')) {
        return data['detail'] as String;
      }
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timed out. Please check your network.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Unable to connect to the server.';
    }
    return 'An unexpected error occurred. Please try again.';
  }
}

/// State for single story detail.
class StoryDetailState {
  const StoryDetailState({
    this.story,
    this.isLoading = false,
    this.errorMessage,
  });

  final StoryModel? story;
  final bool isLoading;
  final String? errorMessage;

  StoryDetailState copyWith({
    StoryModel? story,
    bool? isLoading,
    String? errorMessage,
  }) {
    return StoryDetailState(
      story: story ?? this.story,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Notifier managing single story detail state.
class StoryDetailNotifier extends StateNotifier<StoryDetailState> {
  StoryDetailNotifier(this._repository) : super(const StoryDetailState());

  final StoryRepository _repository;

  /// Load story by slug.
  Future<void> loadStory(String slug) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final story = await _repository.getStory(slug);
      state = state.copyWith(story: story, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.response?.data['detail'] as String? ?? 'Failed to load story',
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Toggle bookmark.
  Future<void> toggleBookmark() async {
    if (state.story == null) return;

    try {
      final isBookmarked = await _repository.toggleBookmark(state.story!.slug);
      state = state.copyWith(
        story: state.story!.copyWith(
          isBookmarked: isBookmarked,
          bookmarkCount: isBookmarked
              ? state.story!.bookmarkCount + 1
              : state.story!.bookmarkCount - 1,
        ),
      );
    } catch (e) {
      // Silently fail
    }
  }

  /// Toggle like.
  Future<void> toggleLike() async {
    if (state.story == null) return;

    try {
      final isLiked = await _repository.toggleLike(state.story!.slug);
      state = state.copyWith(
        story: state.story!.copyWith(
          isLiked: isLiked,
          likeCount: isLiked ? state.story!.likeCount + 1 : state.story!.likeCount - 1,
        ),
      );
    } catch (e) {
      // Silently fail
    }
  }

  /// Update reading progress.
  Future<void> updateProgress({
    required int percent,
    int? lastPosition,
    bool? completed,
  }) async {
    if (state.story == null) return;

    try {
      await _repository.updateReadingProgress(
        state.story!.slug,
        percent: percent,
        lastPosition: lastPosition,
        completed: completed,
      );
      state = state.copyWith(
        story: state.story!.copyWith(
          readingProgress: ReadingProgressData(
            percent: percent,
            lastPosition: lastPosition ?? state.story!.readingProgress?.lastPosition ?? 0,
            completed: completed ?? false,
          ),
        ),
      );
    } catch (e) {
      // Silently fail
    }
  }

  /// Flag story.
  Future<void> flagStory({
    required String reason,
    String? details,
  }) async {
    if (state.story == null) return;

    try {
      await _repository.flagStory(
        state.story!.slug,
        reason: reason,
        details: details,
      );
    } catch (e) {
      rethrow;
    }
  }
}

// --- Providers ---

/// Repository provider.
final storyRepositoryProvider = Provider<StoryRepository>((ref) {
  return StoryRepository();
});

/// Story list provider.
final storyListProvider =
    StateNotifierProvider<StoryListNotifier, StoryListState>((ref) {
  return StoryListNotifier(ref.read(storyRepositoryProvider));
});

/// Story detail provider.
final storyDetailProvider =
    StateNotifierProvider<StoryDetailNotifier, StoryDetailState>((ref) {
  return StoryDetailNotifier(ref.read(storyRepositoryProvider));
});

/// Categories provider.
final categoriesProvider = FutureProvider<List<StoryCategory>>((ref) async {
  final repository = ref.read(storyRepositoryProvider);
  return repository.getCategories();
});

/// My stories provider.
final myStoriesProvider = FutureProvider<List<StoryModel>>((ref) async {
  final repository = ref.read(storyRepositoryProvider);
  return repository.getMyStories();
});

/// Bookmarks provider.
final bookmarksProvider = FutureProvider<List<StoryModel>>((ref) async {
  final repository = ref.read(storyRepositoryProvider);
  return repository.getBookmarks();
});