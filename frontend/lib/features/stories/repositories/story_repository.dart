import '../../../core/network/api_client.dart';
import '../models/story_model.dart';

/// Repository handling Story API calls.
///
/// Provides methods for CRUD operations, search, filtering,
/// and story interactions (bookmark, like, flag, progress).
class StoryRepository {
  StoryRepository({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient.instance;

  final ApiClient _api;

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
    final queryParams = <String, dynamic>{
      'page': page,
      'sort': sort,
    };
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (language != null && language.isNotEmpty) queryParams['language'] = language;
    if (category != null && category.isNotEmpty) queryParams['category'] = category;
    if (region != null && region.isNotEmpty) queryParams['region'] = region;

    final response = await _api.dio.get(
      '/api/stories/',
      queryParameters: queryParams,
    );

    final results = response.data['results'] as List<dynamic>? ?? [];
    return results
        .map((json) => StoryModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get story by slug.
  Future<StoryModel> getStory(String slug) async {
    final response = await _api.dio.get('/api/stories/$slug/');
    return StoryModel.fromJson(response.data as Map<String, dynamic>);
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
    final data = <String, dynamic>{
      'title': title,
      'content': content,
      'language': language,
    };
    if (summary != null) data['summary'] = summary;
    if (categoryIds != null) data['category_ids'] = categoryIds;
    if (region != null) data['region'] = region;
    if (tags != null) data['tags'] = tags;
    if (audioUrl != null) data['audio_url'] = audioUrl;
    if (videoUrl != null) data['video_url'] = videoUrl;
    if (culturalContext != null) data['cultural_context'] = culturalContext;
    if (moralLesson != null) data['moral_lesson'] = moralLesson;
    if (source != null) data['source'] = source;

    final response = await _api.dio.post('/api/stories/', data: data);
    return StoryModel.fromJson(response.data as Map<String, dynamic>);
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
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (content != null) data['content'] = content;
    if (summary != null) data['summary'] = summary;
    if (categoryIds != null) data['category_ids'] = categoryIds;
    if (language != null) data['language'] = language;
    if (region != null) data['region'] = region;
    if (tags != null) data['tags'] = tags;
    if (status != null) data['status'] = status;

    final response = await _api.dio.patch('/api/stories/$slug/', data: data);
    return StoryModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete a story.
  Future<void> deleteStory(String slug) async {
    await _api.dio.delete('/api/stories/$slug/');
  }

  /// Get current user's stories.
  Future<List<StoryModel>> getMyStories() async {
    final response = await _api.dio.get('/api/stories/my/');
    final results = response.data as List<dynamic>? ?? [];
    return results
        .map((json) => StoryModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get current user's bookmarked stories.
  Future<List<StoryModel>> getBookmarks() async {
    final response = await _api.dio.get('/api/stories/bookmarks/');
    final results = response.data as List<dynamic>? ?? [];
    return results
        .map((json) => StoryModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // --- Interactions ---

  /// Toggle bookmark on a story.
  Future<bool> toggleBookmark(String slug) async {
    final response = await _api.dio.post('/api/stories/$slug/bookmark/');
    return response.data['bookmarked'] as bool? ?? false;
  }

  /// Toggle like on a story.
  Future<bool> toggleLike(String slug) async {
    final response = await _api.dio.post('/api/stories/$slug/like/');
    return response.data['liked'] as bool? ?? false;
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
  Future<void> updateReadingProgress(
    String slug, {
    required int percent,
    int? lastPosition,
    bool? completed,
  }) async {
    final data = <String, dynamic>{
      'progress_percent': percent,
    };
    if (lastPosition != null) data['last_read_position'] = lastPosition;
    if (completed != null) data['completed'] = completed;
    await _api.dio.post('/api/stories/$slug/progress/', data: data);
  }

  // --- Categories ---

  /// Get all story categories.
  Future<List<StoryCategory>> getCategories() async {
    final response = await _api.dio.get('/api/stories/categories/');
    final results = response.data as List<dynamic>? ?? [];
    return results
        .map((json) => StoryCategory.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}