import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_error.dart';
import '../../qr_scanner/services/qr_api_service.dart';

/// Filter value meaning "every category".
const String kAllArtifactCategories = 'all';

/// State for the artifacts catalogue.
@immutable
class ArtifactsState {
  const ArtifactsState({
    this.artifacts = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.page = 1,
    this.errorMessage,
    this.category = kAllArtifactCategories,
    this.query = '',
  });

  final List<ArtifactModel> artifacts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int page;
  final String? errorMessage;
  final String category;
  final String query;

  /// Artifacts after the active category + search filters are applied.
  List<ArtifactModel> get visible {
    final needle = query.trim().toLowerCase();
    return artifacts.where((artifact) {
      if (category != kAllArtifactCategories && artifact.category != category) {
        return false;
      }
      if (needle.isEmpty) return true;
      return artifact.title.toLowerCase().contains(needle) ||
          artifact.culture.toLowerCase().contains(needle) ||
          artifact.region.toLowerCase().contains(needle) ||
          artifact.museumName.toLowerCase().contains(needle);
    }).toList(growable: false);
  }

  /// Categories present in the loaded set, for the filter strip.
  List<String> get availableCategories {
    final set = <String>{for (final a in artifacts) a.category};
    final list = set.toList()..sort();
    return [kAllArtifactCategories, ...list];
  }

  /// True when the catalogue itself is empty (as opposed to filtered empty).
  bool get isEmpty => artifacts.isEmpty;

  ArtifactsState copyWith({
    List<ArtifactModel>? artifacts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    String? errorMessage,
    String? category,
    String? query,
    bool clearError = false,
  }) {
    return ArtifactsState(
      artifacts: artifacts ?? this.artifacts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      category: category ?? this.category,
      query: query ?? this.query,
    );
  }
}

/// Loads the artifact catalogue from the backend.
///
/// `QrApiService.listArtifacts` already existed but had **no caller at all**,
/// which is why the app had no Artifacts screen. This notifier is that caller.
class ArtifactsNotifier extends StateNotifier<ArtifactsState> {
  ArtifactsNotifier({QrApiService? apiService})
    : _api = apiService ?? QrApiService.instance,
      super(const ArtifactsState());

  final QrApiService _api;

  /// Load the first page of artifacts.
  Future<void> load({bool refresh = false}) async {
    if (state.isLoading) return;
    if (!refresh && state.artifacts.isNotEmpty) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      artifacts: refresh ? const [] : state.artifacts,
      page: 1,
    );

    try {
      final artifacts = await _api.listArtifacts(page: 1);
      state = state.copyWith(
        isLoading: false,
        artifacts: artifacts,
        page: 2,
        hasMore: artifacts.isNotEmpty,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _messageFor(error),
      );
    }
  }

  /// Load the next page, appending to the current list.
  Future<void> loadMore() async {
    if (state.isLoadingMore || state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final next = await _api.listArtifacts(page: state.page);
      if (next.isEmpty) {
        state = state.copyWith(isLoadingMore: false, hasMore: false);
        return;
      }
      state = state.copyWith(
        isLoadingMore: false,
        artifacts: [...state.artifacts, ...next],
        page: state.page + 1,
      );
    } catch (error) {
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: _messageFor(error),
      );
    }
  }

  void setCategory(String category) => state = state.copyWith(category: category);

  void search(String query) => state = state.copyWith(query: query);

  void clearFilters() =>
      state = state.copyWith(category: kAllArtifactCategories, query: '');

  static String _messageFor(Object error) {
    if (error is Exception) return AppErrorMapper.fromException(error).message;
    return 'Could not load the artifact catalogue.';
  }
}

/// Catalogues state.
final artifactsProvider =
    StateNotifierProvider<ArtifactsNotifier, ArtifactsState>((ref) {
      return ArtifactsNotifier();
    });
