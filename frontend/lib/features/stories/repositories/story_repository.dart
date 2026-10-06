import 'package:dio/dio.dart';

import '../../../core/database/repositories/local_story_repository.dart';
import '../../../core/database/repositories/reading_progress_repository.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/security/secure_storage_factory.dart';
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
    ReadingProgressRepository? readingProgress,
  }) : _api = apiClient ?? ApiClient.instance,
       _local = localStory ?? LocalStoryRepository(),
       _connectivity = connectivityService,
       _readingProgress = readingProgress ?? ReadingProgressRepository();

  final ApiClient _api;
  final LocalStoryRepository _local;
  final ConnectivityService? _connectivity;
  final ReadingProgressRepository _readingProgress;

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
      final queryParams = <String, dynamic>{'page': page, 'sort': sort};
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
    if (_offline) return _withLocalProgress(await _local.getStory(slug));

    try {
      final response = await _api.dio.get('/api/stories/$slug/');
      final story = StoryModel.fromJson(response.data as Map<String, dynamic>);
      await _local.mirrorStories([story]);
      return await _withLocalProgress(story);
    } on DioException {
      // Offline: the mirrored copy, or a real "not found" when the story was
      // never synced — surfaced as an error state, never faked.
      return _withLocalProgress(await _local.getStory(slug));
    }
  }

  /// Fill in locally stored progress when the payload carries none.
  ///
  /// The API only knows a reader's position once they are authenticated and
  /// the push has landed — a guest, a local-only account, or a write still
  /// queued offline all come back with `reading_progress: null`. The local
  /// `reading_progress` row is still authoritative for those readers, so the
  /// detail screen can resume them like anyone else. A server value always
  /// wins: it is what other devices have seen.
  Future<StoryModel> _withLocalProgress(StoryModel story) async {
    if (story.readingProgress != null) return story;
    final local = await _readingProgress.progressForSlug(story.slug);
    if (local == null) return story;
    final percent = (local.scrollFraction * 100).round();
    return story.copyWith(
      readingProgress: ReadingProgressData(
        percent: percent,
        lastPosition: local.lastPosition,
        completed: percent >= 95,
      ),
    );
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
    String? origin,
    String? provenanceNotes,
    String? rightsHolder,
    String? licence,
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
        origin: origin,
        provenanceNotes: provenanceNotes,
        rightsHolder: rightsHolder,
        licence: licence,
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
    // Provenance a contributor declares about their own text. `consent_status`
    // is deliberately absent: the server owns that field, and a self-declared
    // "consent granted" is precisely the claim the app must not make.
    if (origin != null) data['origin'] = origin;
    if (provenanceNotes != null) data['provenance_notes'] = provenanceNotes;
    if (rightsHolder != null) data['rights_holder'] = rightsHolder;
    if (licence != null) data['licence'] = licence;

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
        origin: origin,
        provenanceNotes: provenanceNotes,
        rightsHolder: rightsHolder,
        licence: licence,
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
    String? origin,
    String? provenanceNotes,
    String? rightsHolder,
    String? licence,
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
        origin: origin,
        provenanceNotes: provenanceNotes,
        rightsHolder: rightsHolder,
        licence: licence,
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
    if (origin != null) data['origin'] = origin;
    if (provenanceNotes != null) data['provenance_notes'] = provenanceNotes;
    if (rightsHolder != null) data['rights_holder'] = rightsHolder;
    if (licence != null) data['licence'] = licence;

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
        origin: origin,
        provenanceNotes: provenanceNotes,
        rightsHolder: rightsHolder,
        licence: licence,
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
      final userIdStr = await SecureStorageFactory.instance.read(
        key: 'current_user_id',
      );
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
      final userIdStr = await SecureStorageFactory.instance.read(
        key: 'current_user_id',
      );
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
    final data = <String, dynamic>{'reason': reason};
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

    final data = <String, dynamic>{'progress_percent': percent};
    if (lastPosition != null) data['last_read_position'] = lastPosition;
    if (completed != null) data['completed'] = completed;
    try {
      await _api.dio.post('/api/stories/$slug/progress/', data: data);
    } on DioException {
      // Offline: the local record stands; the queued request replays later.
    }
  }

  /// Record that we have *asked* the source community about this story.
  ///
  /// Moves `not_requested` → `pending`, and is idempotent. This is only ever
  /// the author's half of the record: what the community answered is recorded
  /// by a moderator, because a contributor declaring their own community's
  /// agreement is precisely the claim the field exists to keep trustworthy.
  /// Returns the consent status the server settled on.
  Future<String> requestConsent(String slug) async {
    final response = await _api.dio.post('/api/stories/$slug/request_consent/');
    return response.data['consent_status'] as String? ?? 'pending';
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
