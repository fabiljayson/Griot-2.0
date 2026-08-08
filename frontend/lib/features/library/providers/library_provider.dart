import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/library_api_service.dart';

/// Library state.
class LibraryState {
  const LibraryState({
    this.recentlyRead = const [],
    this.continueReading = const [],
    this.bookmarks = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<LibraryStoryModel> recentlyRead;
  final List<LibraryStoryModel> continueReading;
  final List<LibraryStoryModel> bookmarks;
  final bool isLoading;
  final String? errorMessage;

  LibraryState copyWith({
    List<LibraryStoryModel>? recentlyRead,
    List<LibraryStoryModel>? continueReading,
    List<LibraryStoryModel>? bookmarks,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LibraryState(
      recentlyRead: recentlyRead ?? this.recentlyRead,
      continueReading: continueReading ?? this.continueReading,
      bookmarks: bookmarks ?? this.bookmarks,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Notifier for library state.
class LibraryNotifier extends StateNotifier<LibraryState> {
  LibraryNotifier() : _apiService = LibraryApiService.instance, super(const LibraryState());

  final LibraryApiService _apiService;

  /// Load all library data.
  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final results = await Future.wait([
        _apiService.getRecentlyRead(),
        _apiService.getContinueReading(),
        _apiService.getBookmarks(),
      ]);

      state = state.copyWith(
        isLoading: false,
        recentlyRead: results[0],
        continueReading: results[1],
        bookmarks: results[2],
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load library: $e',
      );
    }
  }

  /// Load recently read stories.
  Future<void> loadRecentlyRead() async {
    try {
      final stories = await _apiService.getRecentlyRead();
      state = state.copyWith(recentlyRead: stories);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load recent stories: $e');
    }
  }

  /// Load continue reading stories.
  Future<void> loadContinueReading() async {
    try {
      final stories = await _apiService.getContinueReading();
      state = state.copyWith(continueReading: stories);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load continue reading: $e');
    }
  }

  /// Load bookmarks.
  Future<void> loadBookmarks() async {
    try {
      final stories = await _apiService.getBookmarks();
      state = state.copyWith(bookmarks: stories);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to load bookmarks: $e');
    }
  }
}

/// Library provider.
final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  return LibraryNotifier();
});
