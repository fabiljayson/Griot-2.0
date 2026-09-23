import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/repositories/story_cache_repository.dart';
import '../../../core/network/app_error.dart';
import '../../../core/network/connectivity_service.dart';
import '../../auth/models/user_model.dart';
import '../models/story_model.dart';
import '../repositories/story_repository.dart';
import '../../../core/debug/debug_log.dart';

// ---------------------------------------------------------------------------
// Story List — sealed union state
// ---------------------------------------------------------------------------

/// Sealed union for the story list async lifecycle.
///
/// Filter/search state lives on the notifier so it persists across
/// state transitions (loading → ready → loading again with same filters).
sealed class StoryListState {
  const StoryListState();
}

/// No stories loaded yet; the notifier has just been created.
final class StoryListInitial extends StoryListState {
  const StoryListInitial();
}

/// A fetch is in progress.
final class StoryListLoading extends StoryListState {
  const StoryListLoading({this.stories = const []});

  /// Existing stories when refreshing (so the UI can keep showing them).
  final List<StoryModel> stories;
}

/// Stories loaded successfully.
final class StoryListReady extends StoryListState {
  const StoryListReady({
    required this.stories,
    this.hasMore = true,
    this.currentPage = 1,
  });

  final List<StoryModel> stories;
  final bool hasMore;
  final int currentPage;

  StoryListReady copyWith({
    List<StoryModel>? stories,
    bool? hasMore,
    int? currentPage,
  }) {
    return StoryListReady(
      stories: stories ?? this.stories,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}

/// A fetch failed.
final class StoryListFailure extends StoryListState {
  const StoryListFailure({required this.message, this.stories = const []});

  final String message;

  /// Existing stories when a refresh fails (so the UI can keep showing them).
  final List<StoryModel> stories;
}

/// Notifier managing story list state with filter persistence.
class StoryListNotifier extends StateNotifier<StoryListState> {
  StoryListNotifier(this._repository, {StoryCacheRepository? cacheRepository})
    : _cacheRepository = cacheRepository ?? StoryCacheRepository(),
      super(const StoryListInitial());

  final StoryRepository _repository;
  final StoryCacheRepository _cacheRepository;

  // --- Filter state (persists across async transitions) ---

  String _searchQuery = '';
  String? _selectedLanguage;
  String? _selectedCategory;
  String? _selectedRegion;
  String _sortBy = '-created_at';

  String get searchQuery => _searchQuery;
  String? get selectedLanguage => _selectedLanguage;
  String? get selectedCategory => _selectedCategory;
  String? get selectedRegion => _selectedRegion;
  String get currentSortBy => _sortBy;

  // --- Load stories ---

  Future<void> loadStories({bool refresh = false}) async {
    if (state is StoryListLoading) return;

    final existingStories = switch (state) {
      StoryListReady(:final stories) => stories,
      StoryListLoading(:final stories) => stories,
      _ => <StoryModel>[],
    };

    final prevPage = switch (state) {
      StoryListReady(:final currentPage) => currentPage,
      _ => 1,
    };
    final page = refresh ? 1 : prevPage;
    state = StoryListLoading(stories: refresh ? const [] : existingStories);

    try {
      final stories = await _repository.getStories(
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        language: _selectedLanguage,
        category: _selectedCategory,
        region: _selectedRegion,
        sort: _sortBy,
        page: page,
      );

      final allStories = refresh ? stories : [...existingStories, ...stories];
      state = StoryListReady(
        stories: allStories,
        hasMore: stories.length >= 20,
        currentPage: page + 1,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        await _loadFromCache();
      } else {
        state = StoryListFailure(
          message: AppErrorMapper.fromDio(e).message,
          stories: refresh ? const [] : existingStories,
        );
      }
    } catch (e) {
      state = StoryListFailure(
        message: AppErrorMapper.fromException(e).message,
        stories: refresh ? const [] : existingStories,
      );
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final cachedStories = await _cacheRepository.getAllStories();

      final storyModels = cachedStories
          .map(
            (cached) => StoryModel(
              id: cached.storyId,
              slug: 'cached-${cached.storyId}',
              title: cached.title,
              summary: '',
              content: cached.contentMarkdown ?? '',
              author: UserModel(id: 0, username: 'offline'),
              language: 'en',
              region: cached.region ?? '',
              categories: [],
              coverImage: cached.heroImagePath,
              audioUrl: cached.audioPath ?? '',
              videoUrl: cached.videoUrl ?? '',
              estimatedReadTime: cached.estimatedReadTime ?? 0,
              isBookmarked: cached.isFavorite,
            ),
          )
          .toList();

      state = StoryListReady(stories: storyModels, hasMore: false);
    } catch (e) {
      state = const StoryListFailure(
        message: 'No cached stories available offline',
      );
    }
  }

  // --- Pagination ---

  Future<void> loadMore() async {
    final current = state;
    if (current is StoryListLoading || current is! StoryListReady) return;
    if (!current.hasMore) return;
    await loadStories();
  }

  // --- Search & filters ---

  Future<void> search(String query) async {
    _searchQuery = query;
    await loadStories(refresh: true);
  }

  Future<void> filterByLanguage(String? language) async {
    _selectedLanguage = language;
    await loadStories(refresh: true);
  }

  Future<void> filterByCategory(String? category) async {
    _selectedCategory = category;
    await loadStories(refresh: true);
  }

  Future<void> filterByRegion(String? region) async {
    _selectedRegion = region;
    await loadStories(refresh: true);
  }

  Future<void> sortStories(String sort) async {
    _sortBy = sort;
    await loadStories(refresh: true);
  }

  Future<void> clearFilters() async {
    _searchQuery = '';
    _selectedLanguage = null;
    _selectedCategory = null;
    _selectedRegion = null;
    _sortBy = '-created_at';
    await loadStories(refresh: true);
  }

  // --- Interactions ---

  Future<void> toggleBookmark(String slug) async {
    try {
      final isBookmarked = await _repository.toggleBookmark(slug);
      final current = state;
      if (current is StoryListReady) {
        state = current.copyWith(
          stories: current.stories.map((s) {
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
      }
    } catch (e) {
      debugLog('[StoryProvider] toggleBookmark failed: $e');
    }
  }

  Future<void> toggleLike(String slug) async {
    try {
      final isLiked = await _repository.toggleLike(slug);
      final current = state;
      if (current is StoryListReady) {
        state = current.copyWith(
          stories: current.stories.map((s) {
            if (s.slug == slug) {
              return s.copyWith(
                isLiked: isLiked,
                likeCount: isLiked ? s.likeCount + 1 : s.likeCount - 1,
              );
            }
            return s;
          }).toList(),
        );
      }
    } catch (e) {
      debugLog('[StoryProvider] toggleLike failed: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Story Detail — sealed union state
// ---------------------------------------------------------------------------

/// Sealed union for single story detail async lifecycle.
sealed class StoryDetailState {
  const StoryDetailState();
}

final class StoryDetailInitial extends StoryDetailState {
  const StoryDetailInitial();
}

final class StoryDetailLoading extends StoryDetailState {
  const StoryDetailLoading();
}

final class StoryDetailReady extends StoryDetailState {
  const StoryDetailReady({required this.story});

  final StoryModel story;
}

final class StoryDetailFailure extends StoryDetailState {
  const StoryDetailFailure({required this.message});

  final String message;
}

/// Notifier managing single story detail state.
class StoryDetailNotifier extends StateNotifier<StoryDetailState> {
  StoryDetailNotifier(this._repository) : super(const StoryDetailInitial());

  final StoryRepository _repository;

  Future<void> loadStory(String slug) async {
    state = const StoryDetailLoading();

    try {
      final story = await _repository.getStory(slug);
      state = StoryDetailReady(story: story);
    } on DioException catch (e) {
      state = StoryDetailFailure(message: AppErrorMapper.fromDio(e).message);
    } catch (e) {
      state = StoryDetailFailure(
        message: AppErrorMapper.fromException(e).message,
      );
    }
  }

  Future<void> toggleBookmark() async {
    final current = state;
    if (current is! StoryDetailReady) return;

    try {
      final isBookmarked = await _repository.toggleBookmark(current.story.slug);
      state = StoryDetailReady(
        story: current.story.copyWith(
          isBookmarked: isBookmarked,
          bookmarkCount: isBookmarked
              ? current.story.bookmarkCount + 1
              : current.story.bookmarkCount - 1,
        ),
      );
    } catch (e) {
      debugLog('[StoryDetailNotifier] toggleBookmark failed: $e');
    }
  }

  Future<void> toggleLike() async {
    final current = state;
    if (current is! StoryDetailReady) return;

    try {
      final isLiked = await _repository.toggleLike(current.story.slug);
      state = StoryDetailReady(
        story: current.story.copyWith(
          isLiked: isLiked,
          likeCount: isLiked
              ? current.story.likeCount + 1
              : current.story.likeCount - 1,
        ),
      );
    } catch (e) {
      debugLog('[StoryDetailNotifier] toggleLike failed: $e');
    }
  }

  Future<void> updateProgress({
    required int percent,
    int? lastPosition,
    bool? completed,
  }) async {
    final current = state;
    if (current is! StoryDetailReady) return;

    try {
      await _repository.updateReadingProgress(
        current.story.slug,
        percent: percent,
        lastPosition: lastPosition,
        completed: completed,
      );
      state = StoryDetailReady(
        story: current.story.copyWith(
          readingProgress: ReadingProgressData(
            percent: percent,
            lastPosition:
                lastPosition ??
                current.story.readingProgress?.lastPosition ??
                0,
            completed: completed ?? false,
          ),
        ),
      );
    } catch (e) {
      debugLog('[StoryDetailNotifier] updateProgress failed: $e');
    }
  }

  Future<void> flagStory({required String reason, String? details}) async {
    final current = state;
    if (current is! StoryDetailReady) return;

    try {
      await _repository.flagStory(
        current.story.slug,
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
  return StoryRepository(
    // The repository skips the network entirely while the device is known
    // offline and serves the SQLite mirror instead.
    connectivityService: ref.watch(connectivityServiceProvider),
  );
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
