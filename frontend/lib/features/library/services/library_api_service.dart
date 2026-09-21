import '../../../core/database/repositories/local_library_repository.dart';

/// Model for a story in the library (recently read, bookmarks, etc.).
class LibraryStoryModel {
  const LibraryStoryModel({
    required this.id,
    required this.slug,
    required this.title,
    this.summary = '',
    this.language = 'en',
    this.region = '',
    this.coverImage,
    this.estimatedReadTime = 0,
    this.progressPercent = 0,
    this.completed = false,
    this.lastReadAt = '',
    this.bookmarkCount = 0,
    this.isBookmarked = false,
  });

  final int id;
  final String slug;
  final String title;
  final String summary;
  final String language;
  final String region;
  final String? coverImage;
  final int estimatedReadTime;
  final int progressPercent;
  final bool completed;
  final String lastReadAt;
  final int bookmarkCount;
  final bool isBookmarked;

  factory LibraryStoryModel.fromJson(Map<String, dynamic> json) {
    return LibraryStoryModel(
      id: json['id'] as int? ?? 0,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
      region: json['region'] as String? ?? '',
      coverImage: json['cover_image'] as String?,
      estimatedReadTime: json['estimated_read_time'] as int? ?? 0,
      progressPercent: json['progress_percent'] as int? ?? 0,
      completed: json['completed'] as bool? ?? false,
      lastReadAt: json['last_read_at'] as String? ?? '',
      bookmarkCount: json['bookmark_count'] as int? ?? 0,
      isBookmarked: json['is_bookmarked'] as bool? ?? false,
    );
  }

  /// Progress as a fraction (0.0 to 1.0).
  double get progressFraction => progressPercent / 100.0;
}

/// Service for library operations — delegates entirely to local SQLite.
class LibraryApiService {
  LibraryApiService._({LocalLibraryRepository? local})
      : _local = local ?? LocalLibraryRepository();

  final LocalLibraryRepository _local;

  static final LibraryApiService instance = LibraryApiService._();

  /// Get recently read stories.
  Future<List<LibraryStoryModel>> getRecentlyRead() =>
      _local.getRecentlyRead();

  /// Get stories in progress (not completed).
  Future<List<LibraryStoryModel>> getContinueReading() =>
      _local.getContinueReading();

  /// Get bookmarked stories.
  Future<List<LibraryStoryModel>> getBookmarks() => _local.getBookmarks();
}
