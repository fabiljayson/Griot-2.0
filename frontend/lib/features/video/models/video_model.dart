/// Video model representing an AI-generated story video from Luma AI.
class VideoModel {
  const VideoModel({
    required this.id,
    required this.storyId,
    required this.storyTitle,
    this.url = '',
    this.thumbnailUrl = '',
    this.duration = 0,
    this.status = VideoStatus.pending,
    this.lumaJobId = '',
    this.prompt = '',
    this.createdAt = '',
    this.completedAt,
    this.errorMessage,
  });

  final int id;
  final int storyId;
  final String storyTitle;
  final String url;
  final String thumbnailUrl;
  final int duration; // in seconds
  final VideoStatus status;
  final String lumaJobId;
  final String prompt;
  final String createdAt;
  final String? completedAt;
  final String? errorMessage;

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    return VideoModel(
      id: json['id'] as int? ?? 0,
      storyId: json['story_id'] as int? ?? 0,
      storyTitle: json['story_title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      status: VideoStatus.fromString(json['status'] as String? ?? 'pending'),
      lumaJobId: json['luma_job_id'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      completedAt: json['completed_at'] as String?,
      errorMessage: json['error_message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'story_id': storyId,
        'story_title': storyTitle,
        'url': url,
        'thumbnail_url': thumbnailUrl,
        'duration': duration,
        'status': status.value,
        'luma_job_id': lumaJobId,
        'prompt': prompt,
        'created_at': createdAt,
        'completed_at': completedAt,
        'error_message': errorMessage,
      };

  /// Whether the video is ready to play.
  bool get isReady => status == VideoStatus.completed && url.isNotEmpty;

  /// Whether the video is still processing.
  bool get isProcessing =>
      status == VideoStatus.pending || status == VideoStatus.processing;

  /// Whether the video failed to render.
  bool get hasFailed => status == VideoStatus.failed;

  /// Formatted duration (e.g., "1:30").
  String get formattedDuration {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  VideoModel copyWith({
    int? id,
    int? storyId,
    String? storyTitle,
    String? url,
    String? thumbnailUrl,
    int? duration,
    VideoStatus? status,
    String? lumaJobId,
    String? prompt,
    String? createdAt,
    String? completedAt,
    String? errorMessage,
    bool clearError = false,
    bool clearCompletedAt = false,
  }) {
    return VideoModel(
      id: id ?? this.id,
      storyId: storyId ?? this.storyId,
      storyTitle: storyTitle ?? this.storyTitle,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      status: status ?? this.status,
      lumaJobId: lumaJobId ?? this.lumaJobId,
      prompt: prompt ?? this.prompt,
      createdAt: createdAt ?? this.createdAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Video rendering status.
enum VideoStatus {
  pending('pending', 'Pending', '⏳'),
  processing('processing', 'Processing', '⚙️'),
  completed('completed', 'Completed', '✅'),
  failed('failed', 'Failed', '❌');

  const VideoStatus(this.value, this.label, this.emoji);

  final String value;
  final String label;
  final String emoji;

  factory VideoStatus.fromString(String value) {
    return VideoStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => VideoStatus.pending,
    );
  }
}

/// Video player state.
class VideoPlayerState {
  const VideoPlayerState({
    this.currentVideo,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isBuffering = false,
    this.isFullscreen = false,
    this.errorMessage,
  });

  final VideoModel? currentVideo;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool isBuffering;
  final bool isFullscreen;
  final String? errorMessage;

  bool get hasVideo => currentVideo != null;
  bool get isPaused => hasVideo && !isPlaying;

  /// Progress as a percentage (0.0 to 1.0).
  double get progress {
    if (duration.inSeconds == 0) return 0.0;
    return (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);
  }

  /// Formatted position (e.g., "2:30").
  String get formattedPosition {
    final minutes = position.inMinutes;
    final seconds = position.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Formatted duration (e.g., "10:00").
  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  VideoPlayerState copyWith({
    VideoModel? currentVideo,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? isBuffering,
    bool? isFullscreen,
    String? errorMessage,
    bool clearVideo = false,
    bool clearError = false,
  }) {
    return VideoPlayerState(
      currentVideo: clearVideo ? null : (currentVideo ?? this.currentVideo),
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isBuffering: isBuffering ?? this.isBuffering,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}