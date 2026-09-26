/// One message in the reader's inbox.
///
/// The API is the only source: there is no offline bundle for notifications,
/// because a message the server never sent must not be able to appear here, and
/// a stored one that the server has since withdrawn would be a lie.
class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.kind,
    required this.title,
    this.body = '',
    this.storyId,
    this.storyTitle = '',
    this.storySlug = '',
    this.isRead = false,
    required this.createdAt,
  });

  final int id;

  /// One of the server's `kind` values; see [NotificationKind].
  final String kind;
  final String title;
  final String body;

  /// The story this message points at, if any. Null for announcements.
  final int? storyId;

  /// Snapshotted server-side so the row still reads sensibly if the story is
  /// deleted, which nulls the live link.
  final String storyTitle;

  /// The deep link. Preferred over [storyId] because slugs survive a re-import.
  final String storySlug;
  final bool isRead;
  final DateTime createdAt;

  bool get hasStory => (storyId != null || storySlug.isNotEmpty);

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as int? ?? 0,
      kind: json['kind'] as String? ?? NotificationKind.system,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      storyId: json['story'] as int?,
      storyTitle: json['story_title'] as String? ?? '',
      storySlug: json['story_slug'] as String? ?? '',
      isRead: json['is_read'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,
      kind: kind,
      title: title,
      body: body,
      storyId: storyId,
      storyTitle: storyTitle,
      storySlug: storySlug,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}

/// The server's `kind` values.
///
/// Kept as strings rather than an enum because the API may add a kind before
/// this app ships support for it; an unknown value renders as a generic
/// message instead of crashing the inbox.
abstract final class NotificationKind {
  static const newStory = 'new_story';
  static const trending = 'trending';
  static const streak = 'streak';
  static const badge = 'badge';
  static const announcement = 'announcement';
  static const system = 'system';
}
