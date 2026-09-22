import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/database/repositories/local_story_repository.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/connectivity_service.dart';
import '../models/story_model.dart';

/// Repository handling Story API calls with an offline mirror.
///
/// Reads go to the Django API first — this is what brings the backend's real
/// story covers (`/media/stories/covers/...`) into the app. Every successful
/// fetch is upserted into the local SQLite mirror ([LocalStoryRepository]),
/// so when the device is offline (or the API is unreachable) the last synced
/// collection is served from SQLite instead of an empty screen.
///
/// The mirror upsert is slug-keyed and never overwrites locally-owned data
/// (bookmarks, likes, local author links, non-empty local covers).
///
/// Mutations try the API and fall back to the local store so interactions
/// keep working while offline or unauthenticated; the offline request queue
/// replays queued API calls when connectivity returns.
class StoryRepository {
  StoryRepository({
    ApiClient? apiClient,
    LocalStoryRepository? localStory,
    ConnectivityService? connectivityService,
  })  : _api = apiClient ?? ApiClient.instance,
        _local = localStory ?? LocalStoryRepository(),
        _connectivity = connectivityService;

  final ApiClient _api;
  final LocalStoryRepository _local;
  final ConnectivityService? _connectivity;

  /// Connectivity guard: when the device is known offline, skip the network
  /// entirely instead of waiting out Dio's retry/backoff cycle. Unknown
  /// (null service, e.g. in tests) means "try".
  bool get _offline => _connectivity?.isOnline == false;

  // --- Stories ---

  /// Get list of stories with optional filters.
  Future<List<StoryModel>> getStories({
    String? search,
    String? language,
    String? category,
    String? region,
    String sort = '-created_at',
    int page = 1,
  }) async {
    if (_offline) {
      return _local.getStories(
        search: search,
        language: language,
        category: category,
        region: region,
        sort: sort,
        page: page,
      );
    }

    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'sort': sort,
      };
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (language != null && language.isNotEmpty) {
        queryParams['language'] = language;
      }
      if (category != null && category.isNotEmpty) {
        queryParams['category'] = category;
      }
      if (region != null && region.isNotEmpty) queryParams['region'] = region;

      final response = await _api.dio.get(
        '/api/stories/',
        queryParameters: queryParams,
      );

      final results = response.data['results'] as List<dynamic>? ?? const [];
      final stories = results
          .map((json) => StoryModel.fromJson(json as Map<String, dynamic>))
          .toList();

      // Offline mirror: keep the last synced pages on device.
      await _local.mirrorStories(stories);
      return stories;
    } on DioException {
      // Offline / API unreachable: serve the local mirror (seeded stories +
      // everything previously synced from the API).
      return _local.getStories(
        search: search,
        language: language,
        category: category,
        region: region,
        sort: sort,
        page: page,
      );
    }
  }

  /// Get story by slug.
  Future<StoryModel> getStory(String slug) async {
    if (_offline) return _local.getStory(slug);

    try {
      final response = await _api.dio.get('/api/stories/$slug/');
      final story = StoryModel.fromJson(response.data as Map<String, dynamic>);
      await _local.mirrorStories([story]);
      return story;
    } on DioException {
      // Offline: the mirrored copy, or a real "not found" when the story was
      // never synced — surfaced as an error state, never faked.
      return _local.getStory(slug);
    }
  }

  /// Create a new story.
  Future<StoryModel> createStory({
    required String title,
    required String content,
    String? summary,
    List<int>? categoryIds,
    String language = 'en',
    String? region,
    String? tags,
    String? coverImage,
    String? audioUrl,
    String? videoUrl,
    String? culturalContext,
    String? moralLesson,
    String? source,
  }) async {
    if (_offline) {
      return _local.createStory(
        title: title,
        content: content,
        summary: summary,
        categoryIds: categoryIds,
        language: language,
        region: region,
        tags: tags,
        coverImage: coverImage,
        audioUrl: audioUrl,
        videoUrl: videoUrl,
        culturalContext: culturalContext,
        moralLesson: moralLesson,
        source: source,
      );
    }

    final data = <String, dynamic>{
      'title': title,
      'content': content,
      'language': language,
    };
    if (summary != null) data['summary'] = summary;
    if (categoryIds != null) data['category_ids'] = categoryIds;
    if (region != null) data['region'] = region;
    if (tags != null) data['tags'] = tags;
    if (coverImage != null) data['cover_image'] = coverImage;
    if (audioUrl != null) data['audio_url'] = audioUrl;
    if (videoUrl != null) data['video_url'] = videoUrl;
    if (culturalContext != null) data['cultural_context'] = culturalContext;
    if (moralLesson != null) data['moral_lesson'] = moralLesson;
    if (source != null) data['source'] = source;

    try {
      final response = await _api.dio.post('/api/stories/', data: data);
      final story = StoryModel.fromJson(response.data as Map<String, dynamic>);
      await _local.mirrorStories([story]);
      return story;
    } on DioException {
      // Offline / unauthenticated: create locally so the draft still exists;
      // the offline request queue replays the API call when possible.
      return _local.createStory(
        title: title,
        content: content,
        summary: summary,
        categoryIds: categoryIds,
        language: language,
        region: region,
        tags: tags,
        coverImage: coverImage,
        audioUrl: audioUrl,
        videoUrl: videoUrl,
        culturalContext: culturalContext,
        moralLesson: moralLesson,
        source: source,
      );
    }
  }

  /// Update an existing story.
  Future<StoryModel> updateStory(
    String slug, {
    String? title,
    String? content,
    String? summary,
    List<int>? categoryIds,
    String? language,
    String? region,
    String? tags,
    String? status,
  }) async {
    if (_offline) {
      return _local.updateStory(
        slug,
        title: title,
        content: content,
        summary: summary,
        categoryIds: categoryIds,
        language: language,
        region: region,
        tags: tags,
        status: status,
      );
    }

    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (content != null) data['content'] = content;
    if (summary != null) data['summary'] = summary;
    if (categoryIds != null) data['category_ids'] = categoryIds;
    if (language != null) data['language'] = language;
    if (region != null) data['region'] = region;
    if (tags != null) data['tags'] = tags;
    if (status != null) data['status'] = status;

    try {
      final response = await _api.dio.patch('/api/stories/$slug/', data: data);
      final story = StoryModel.fromJson(response.data as Map<String, dynamic>);
      await _local.mirrorStories([story]);
      return story;
    } on DioException {
      return _local.updateStory(
        slug,
        title: title,
        content: content,
        summary: summary,
        categoryIds: categoryIds,
        language: language,
        region: region,
        tags: tags,
        status: status,
      );
    }
  }

  /// Delete a story.
  Future<void> deleteStory(String slug) async {
    if (!_offline) {
      try {
        await _api.dio.delete('/api/stories/$slug/');
      } on DioException {
        // Queued for replay; the local delete below still happens.
      }
    }
    // Offline: delete locally; the queued API delete replays later.
    await _local.deleteStory(slug);
  }

  /// Get current user's stories.
  Future<List<StoryModel>> getMyStories() async {
    if (_offline) {
      final userIdStr =
          await const FlutterSecureStorage().read(key: 'current_user_id');
      final userId = int.tryParse(userIdStr ?? '') ?? 0;
      return _local.getMyStories(userId);
    }

    try {
      final response = await _api.dio.get('/api/stories/my/');
      final results = response.data as List<dynamic>? ?? const [];
      final stories = results
          .map((json) => StoryModel.fromJson(json as Map<String, dynamic>))
          .toList();
      await _local.mirrorStories(stories);
      return stories;
    } on DioException {
      // Offline: locally-created stories only.
      final userIdStr =
          await const FlutterSecureStorage().read(key: 'current_user_id');
      final userId = int.tryParse(userIdStr ?? '') ?? 0;
      return _local.getMyStories(userId);
    }
  }

  /// Get current user's bookmarked stories.
  Future<List<StoryModel>> getBookmarks() async {
    if (_offline) return _local.getBookmarks();

    try {
      final response = await _api.dio.get('/api/stories/bookmarks/');
      final results = response.data as List<dynamic>? ?? const [];
      return results
          .map((json) => StoryModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException {
      return _local.getBookmarks();
    }
  }

  // --- Interactions ---

  /// Toggle bookmark on a story.
  Future<bool> toggleBookmark(String slug) async {
    if (_offline) return _local.toggleBookmark(slug);

    try {
      final response = await _api.dio.post('/api/stories/$slug/bookmark/');
      final result = response.data['bookmarked'] as bool? ?? false;
      await _local.setBookmarked(slug, result);
      return result;
    } on DioException {
      // Offline / unauthenticated: toggle on the local mirror. Returns false
      // when the story was never mirrored, which the UI treats as "off".
      return _local.toggleBookmark(slug);
    }
  }

  /// Toggle like on a story.
  Future<bool> toggleLike(String slug) async {
    if (_offline) return _local.toggleLike(slug);

    try {
      final response = await _api.dio.post('/api/stories/$slug/like/');
      final result = response.data['liked'] as bool? ?? false;
      await _local.setLiked(slug, result);
      return result;
    } on DioException {
      return _local.toggleLike(slug);
    }
  }

  /// Flag a story for cultural inaccuracy or other issues.
  Future<void> flagStory(
    String slug, {
    required String reason,
    String? details,
  }) async {
    final data = <String, dynamic>{
      'reason': reason,
    };
    if (details != null) data['details'] = details;
    await _api.dio.post('/api/stories/$slug/flag/', data: data);
  }

  /// Update reading progress for a story.
  ///
  /// Stored locally first (so resume position works offline), then pushed to
  /// the API best-effort.
  Future<void> updateReadingProgress(
    String slug, {
    required int percent,
    int? lastPosition,
    bool? completed,
  }) async {
    await _local.updateReadingProgress(
      slug,
      percent: percent,
      lastPosition: lastPosition,
      completed: completed,
    );

    if (_offline) return;

    final data = <String, dynamic>{
      'progress_percent': percent,
    };
    if (lastPosition != null) data['last_read_position'] = lastPosition;
    if (completed != null) data['completed'] = completed;
    try {
      await _api.dio.post('/api/stories/$slug/progress/', data: data);
    } on DioException {
      // Offline: the local record stands; the queued request replays later.
    }
  }

  // --- Categories ---

  /// Get all story categories.
  Future<List<StoryCategory>> getCategories() async {
    if (_offline) return _local.getCategories();

    try {
      final response = await _api.dio.get('/api/stories/categories/');
      final results = response.data as List<dynamic>? ?? const [];
      return results
          .map((json) => StoryCategory.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException {
      return _local.getCategories();
    }
  }
}
