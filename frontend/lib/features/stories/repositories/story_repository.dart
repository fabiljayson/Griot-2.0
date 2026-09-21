import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/database/repositories/local_story_repository.dart';
import '../models/story_model.dart';

/// Repository handling local story operations against SQLite.
///
/// All story CRUD, search, filtering, and interactions happen locally —
/// no network requests are made.
class StoryRepository {
  StoryRepository({LocalStoryRepository? localStory})
      : _local = localStory ?? LocalStoryRepository();

  final LocalStoryRepository _local;

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
    return _local.getStories(
      search: search,
      language: language,
      category: category,
      region: region,
      sort: sort,
      page: page,
    );
  }

  /// Get story by slug.
  Future<StoryModel> getStory(String slug) => _local.getStory(slug);

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
    // Try to get current user id from secure storage.
    int? authorId;
    final userIdStr = await const FlutterSecureStorage().read(key: 'current_user_id');
    if (userIdStr != null) authorId = int.tryParse(userIdStr);

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
      authorId: authorId,
    );
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
  }) {
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

  /// Delete a story.
  Future<void> deleteStory(String slug) => _local.deleteStory(slug);

  /// Get current user's stories.
  Future<List<StoryModel>> getMyStories() async {
    final userIdStr = await const FlutterSecureStorage().read(key: 'current_user_id');
    final userId = int.tryParse(userIdStr ?? '') ?? 0;
    return _local.getMyStories(userId);
  }

  /// Get current user's bookmarked stories.
  Future<List<StoryModel>> getBookmarks() => _local.getBookmarks();

  // --- Interactions ---

  /// Toggle bookmark on a story.
  Future<bool> toggleBookmark(String slug) => _local.toggleBookmark(slug);

  /// Toggle like on a story.
  Future<bool> toggleLike(String slug) => _local.toggleLike(slug);

  /// Flag a story (local no-op, stored as-is).
  Future<void> flagStory(
    String slug, {
    required String reason,
    String? details,
  }) async {
    // Local-only: flagging is not persisted for offline-only mode.
  }

  /// Update reading progress for a story.
  Future<void> updateReadingProgress(
    String slug, {
    required int percent,
    int? lastPosition,
    bool? completed,
  }) {
    return _local.updateReadingProgress(
      slug,
      percent: percent,
      lastPosition: lastPosition,
      completed: completed,
    );
  }

  // --- Categories ---

  /// Get all story categories.
  Future<List<StoryCategory>> getCategories() => _local.getCategories();
}
