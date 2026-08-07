/// A story stored locally for offline reading.
///
/// Mirrors the Django `Story` serializer fields so cached payloads map
/// 1:1 to what the API returns (Phase 3.1).
class CachedStory {
  const CachedStory({
    required this.storyId,
    required this.title,
    this.category,
    this.region,
    this.contentMarkdown,
    this.heroImagePath,
    this.audioPath,
    this.videoUrl,
    this.historicalContext,
    this.estimatedReadTime,
    this.savedAt,
    this.isFavorite = false,
  });

  final int storyId;
  final String title;
  final String? category;
  final String? region;
  final String? contentMarkdown;
  final String? heroImagePath;
  final String? audioPath;
  final String? videoUrl;
  final String? historicalContext;
  final int? estimatedReadTime;
  final String? savedAt;
  final bool isFavorite;

  Map<String, Object?> toMap() => {
        'story_id': storyId,
        'title': title,
        'category': category,
        'region': region,
        'content_markdown': contentMarkdown,
        'hero_image_path': heroImagePath,
        'audio_path': audioPath,
        'video_url': videoUrl,
        'historical_context': historicalContext,
        'estimated_read_time': estimatedReadTime,
        'is_favorite': isFavorite ? 1 : 0,
      };

  factory CachedStory.fromMap(Map<String, Object?> map) => CachedStory(
        storyId: map['story_id'] as int,
        title: map['title'] as String,
        category: map['category'] as String?,
        region: map['region'] as String?,
        contentMarkdown: map['content_markdown'] as String?,
        heroImagePath: map['hero_image_path'] as String?,
        audioPath: map['audio_path'] as String?,
        videoUrl: map['video_url'] as String?,
        historicalContext: map['historical_context'] as String?,
        estimatedReadTime: map['estimated_read_time'] as int?,
        savedAt: map['saved_at'] as String?,
        isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      );
}
