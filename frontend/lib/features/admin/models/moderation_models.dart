/// Data models for the admin moderation queue.
///
/// Mirrors the backend `StoryViewSet.moderation_queue` / `moderate` responses
/// in `backend/stories/views.py`.
library;

/// A single report/flag on a story.
class FlagDetail {
  const FlagDetail({
    this.id = 0,
    this.reason = '',
    this.reasonDisplay = '',
    this.details = '',
    this.reporter = '',
    this.createdAt = '',
  });

  final int id;
  final String reason;
  final String reasonDisplay;
  final String details;
  final String reporter;
  final String createdAt;

  factory FlagDetail.fromJson(Map<String, dynamic> json) {
    return FlagDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? '',
      reasonDisplay: json['reason_display'] as String? ?? '',
      details: json['details'] as String? ?? '',
      reporter: json['reporter'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

/// A flagged story awaiting moderation, with its unresolved flags.
class FlaggedStory {
  const FlaggedStory({
    this.storyId = 0,
    this.slug = '',
    this.title = '',
    this.status = '',
    this.authorUsername = '',
    this.flags = const [],
  });

  final int storyId;
  final String slug;
  final String title;
  final String status;
  final String authorUsername;
  final List<FlagDetail> flags;

  factory FlaggedStory.fromJson(Map<String, dynamic> json) {
    return FlaggedStory(
      storyId: (json['story_id'] as num?)?.toInt() ?? 0,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? '',
      authorUsername: json['author_username'] as String? ?? '',
      flags: (json['flags'] as List<dynamic>? ?? [])
          .map((e) => FlagDetail.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
