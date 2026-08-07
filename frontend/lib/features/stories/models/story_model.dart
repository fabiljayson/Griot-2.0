import 'package:flutter/material.dart';

import '../../auth/models/user_model.dart';

/// Story model representing a cultural story or oral tradition.
class StoryModel {
  const StoryModel({
    required this.id,
    required this.title,
    this.slug = '',
    this.content = '',
    this.summary = '',
    required this.author,
    this.categories = const [],
    this.language = 'en',
    this.region = '',
    this.tags = '',
    this.coverImage,
    this.coverImageBlurhash = '',
    this.audioUrl = '',
    this.videoUrl = '',
    this.culturalContext = '',
    this.moralLesson = '',
    this.source = '',
    this.estimatedReadTime = 0,
    this.status = 'published',
    this.viewCount = 0,
    this.likeCount = 0,
    this.bookmarkCount = 0,
    this.isBookmarked = false,
    this.isLiked = false,
    this.readingProgress,
    this.createdAt = '',
    this.publishedAt,
  });

  final int id;
  final String title;
  final String slug;
  final String content;
  final String summary;
  final UserModel author;
  final List<StoryCategory> categories;
  final String language;
  final String region;
  final String tags;
  final String? coverImage;
  final String coverImageBlurhash;
  final String audioUrl;
  final String videoUrl;
  final String culturalContext;
  final String moralLesson;
  final String source;
  final int estimatedReadTime;
  final String status;
  final int viewCount;
  final int likeCount;
  final int bookmarkCount;
  final bool isBookmarked;
  final bool isLiked;
  final ReadingProgressData? readingProgress;
  final String createdAt;
  final String? publishedAt;

  factory StoryModel.fromJson(Map<String, dynamic> json) {
    return StoryModel(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      content: json['content'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      author: UserModel.fromJson(json['author'] as Map<String, dynamic>? ?? {}),
      categories: (json['categories'] as List<dynamic>?)
              ?.map((c) => StoryCategory.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      language: json['language'] as String? ?? 'en',
      region: json['region'] as String? ?? '',
      tags: json['tags'] as String? ?? '',
      coverImage: json['cover_image'] as String?,
      coverImageBlurhash: json['cover_image_blurhash'] as String? ?? '',
      audioUrl: json['audio_url'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      culturalContext: json['cultural_context'] as String? ?? '',
      moralLesson: json['moral_lesson'] as String? ?? '',
      source: json['source'] as String? ?? '',
      estimatedReadTime: json['estimated_read_time'] as int? ?? 0,
      status: json['status'] as String? ?? 'published',
      viewCount: json['view_count'] as int? ?? 0,
      likeCount: json['like_count'] as int? ?? 0,
      bookmarkCount: json['bookmark_count'] as int? ?? 0,
      isBookmarked: json['is_bookmarked'] as bool? ?? false,
      isLiked: json['is_liked'] as bool? ?? false,
      readingProgress: json['reading_progress'] != null
          ? ReadingProgressData.fromJson(
              json['reading_progress'] as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] as String? ?? '',
      publishedAt: json['published_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'slug': slug,
        'content': content,
        'summary': summary,
        'author': author.toJson(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'language': language,
        'region': region,
        'tags': tags,
        'cover_image': coverImage,
        'cover_image_blurhash': coverImageBlurhash,
        'audio_url': audioUrl,
        'video_url': videoUrl,
        'cultural_context': culturalContext,
        'moral_lesson': moralLesson,
        'source': source,
        'estimated_read_time': estimatedReadTime,
        'status': status,
        'view_count': viewCount,
        'like_count': likeCount,
        'bookmark_count': bookmarkCount,
        'is_bookmarked': isBookmarked,
        'is_liked': isLiked,
        'reading_progress': readingProgress?.toJson(),
        'created_at': createdAt,
        'published_at': publishedAt,
      };

  /// List of tags parsed from comma-separated string.
  List<String> get tagList {
    if (tags.isEmpty) return [];
    return tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  }

  /// Formatted view count (e.g., "1.2K").
  String get formattedViewCount => _formatCount(viewCount);

  /// Formatted like count.
  String get formattedLikeCount => _formatCount(likeCount);

  /// Formatted bookmark count.
  String get formattedBookmarkCount => _formatCount(bookmarkCount);

  /// Estimated read time display.
  String get readTimeDisplay => '$estimatedReadTime min read';

  static String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  StoryModel copyWith({
    int? id,
    String? title,
    String? slug,
    String? content,
    String? summary,
    UserModel? author,
    List<StoryCategory>? categories,
    String? language,
    String? region,
    String? tags,
    String? coverImage,
    String? coverImageBlurhash,
    String? audioUrl,
    String? videoUrl,
    String? culturalContext,
    String? moralLesson,
    String? source,
    int? estimatedReadTime,
    String? status,
    int? viewCount,
    int? likeCount,
    int? bookmarkCount,
    bool? isBookmarked,
    bool? isLiked,
    ReadingProgressData? readingProgress,
    String? createdAt,
    String? publishedAt,
  }) {
    return StoryModel(
      id: id ?? this.id,
      title: title ?? this.title,
      slug: slug ?? this.slug,
      content: content ?? this.content,
      summary: summary ?? this.summary,
      author: author ?? this.author,
      categories: categories ?? this.categories,
      language: language ?? this.language,
      region: region ?? this.region,
      tags: tags ?? this.tags,
      coverImage: coverImage ?? this.coverImage,
      coverImageBlurhash: coverImageBlurhash ?? this.coverImageBlurhash,
      audioUrl: audioUrl ?? this.audioUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      culturalContext: culturalContext ?? this.culturalContext,
      moralLesson: moralLesson ?? this.moralLesson,
      source: source ?? this.source,
      estimatedReadTime: estimatedReadTime ?? this.estimatedReadTime,
      status: status ?? this.status,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      bookmarkCount: bookmarkCount ?? this.bookmarkCount,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      isLiked: isLiked ?? this.isLiked,
      readingProgress: readingProgress ?? this.readingProgress,
      createdAt: createdAt ?? this.createdAt,
      publishedAt: publishedAt ?? this.publishedAt,
    );
  }
}

/// Story category model.
class StoryCategory {
  const StoryCategory({
    required this.id,
    required this.name,
    this.slug = '',
    this.description = '',
    this.icon = '📖',
    this.color = '#8B4513',
    this.storyCount = 0,
  });

  final int id;
  final String name;
  final String slug;
  final String description;
  final String icon;
  final String color;
  final int storyCount;

  factory StoryCategory.fromJson(Map<String, dynamic> json) {
    return StoryCategory(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '📖',
      color: json['color'] as String? ?? '#8B4513',
      storyCount: json['story_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'description': description,
        'icon': icon,
        'color': color,
        'story_count': storyCount,
      };

  /// Convert hex color string to Color.
  Color get colorValue {
    try {
      final hex = color.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF8B4513); // Default brown
    }
  }
}

/// Reading progress data.
class ReadingProgressData {
  const ReadingProgressData({
    this.percent = 0,
    this.lastPosition = 0,
    this.completed = false,
  });

  final int percent;
  final int lastPosition;
  final bool completed;

  factory ReadingProgressData.fromJson(Map<String, dynamic> json) {
    return ReadingProgressData(
      percent: json['percent'] as int? ?? 0,
      lastPosition: json['last_position'] as int? ?? 0,
      completed: json['completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'percent': percent,
        'last_position': lastPosition,
        'completed': completed,
      };
}

/// Story status enum.
enum StoryStatus {
  draft('draft', 'Draft'),
  pending('pending', 'Pending Review'),
  published('published', 'Published'),
  rejected('rejected', 'Rejected'),
  archived('archived', 'Archived');

  const StoryStatus(this.value, this.label);

  final String value;
  final String label;

  factory StoryStatus.fromString(String value) {
    return StoryStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => StoryStatus.draft,
    );
  }
}

/// Story language enum.
enum StoryLanguage {
  english('en', 'English', '🇬🇧'),
  french('fr', 'French', '🇫🇷'),
  fula('ful', 'Fula', '🌍'),
  duala('dua', 'Duala', '🌍'),
  ewondo('ewo', 'Ewondo', '🌍'),
  bamileke('bml', 'Bamileke', '🌍'),
  other('other', 'Other', '🌐');

  const StoryLanguage(this.value, this.label, this.flag);

  final String value;
  final String label;
  final String flag;

  factory StoryLanguage.fromString(String value) {
    return StoryLanguage.values.firstWhere(
      (l) => l.value == value,
      orElse: () => StoryLanguage.english,
    );
  }
}