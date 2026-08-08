/// Audio model representing a story narration or audio content.
class AudioModel {
  const AudioModel({
    required this.id,
    required this.storyId,
    required this.storyTitle,
    this.url = '',
    this.duration = 0,
    this.narrator = '',
    this.language = 'en',
    this.playbackSpeed = 1.0,
    this.createdAt = '',
  });

  final int id;
  final int storyId;
  final String storyTitle;
  final String url;
  final int duration; // in seconds
  final String narrator;
  final String language;
  final double playbackSpeed;
  final String createdAt;

  factory AudioModel.fromJson(Map<String, dynamic> json) {
    return AudioModel(
      id: json['id'] as int? ?? 0,
      storyId: json['story_id'] as int? ?? 0,
      storyTitle: json['story_title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      narrator: json['narrator'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
      playbackSpeed: (json['playback_speed'] as num?)?.toDouble() ?? 1.0,
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'story_id': storyId,
    'story_title': storyTitle,
    'url': url,
    'duration': duration,
    'narrator': narrator,
    'language': language,
    'playback_speed': playbackSpeed,
    'created_at': createdAt,
  };

  /// Formatted duration (e.g., "5:30").
  String get formattedDuration {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  AudioModel copyWith({
    int? id,
    int? storyId,
    String? storyTitle,
    String? url,
    int? duration,
    String? narrator,
    String? language,
    double? playbackSpeed,
    String? createdAt,
  }) {
    return AudioModel(
      id: id ?? this.id,
      storyId: storyId ?? this.storyId,
      storyTitle: storyTitle ?? this.storyTitle,
      url: url ?? this.url,
      duration: duration ?? this.duration,
      narrator: narrator ?? this.narrator,
      language: language ?? this.language,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Playback speed options.
enum PlaybackSpeed {
  slow(0.75, '0.75x'),
  normal(1.0, '1x'),
  fast(1.25, '1.25x'),
  faster(1.5, '1.5x'),
  fastest(2.0, '2x');

  const PlaybackSpeed(this.value, this.label);

  final double value;
  final String label;
}

/// Sleep timer options (in minutes).
enum SleepTimer {
  off(0, 'Off'),
  five(5, '5 min'),
  fifteen(15, '15 min'),
  thirty(30, '30 min'),
  fortyFive(45, '45 min'),
  sixty(60, '60 min');

  const SleepTimer(this.minutes, this.label);

  final int minutes;
  final String label;
}

/// Audio player state.
class AudioPlayerState {
  const AudioPlayerState({
    this.currentAudio,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playbackSpeed = 1.0,
    this.sleepTimer = SleepTimer.off,
    this.isRepeatEnabled = false,
    this.volume = 1.0,
    this.isBuffering = false,
    this.errorMessage,
  });

  final AudioModel? currentAudio;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double playbackSpeed;
  final SleepTimer sleepTimer;
  final bool isRepeatEnabled;
  final double volume;
  final bool isBuffering;
  final String? errorMessage;

  bool get hasAudio => currentAudio != null;
  bool get isPaused => hasAudio && !isPlaying;

  /// Progress as a percentage (0.0 to 1.0).
  double get progress {
    if (duration.inSeconds == 0) return 0.0;
    return (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);
  }

  /// Remaining time.
  Duration get remaining => duration - position;

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

  /// Formatted remaining time (e.g., "-7:30").
  String get formattedRemaining {
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '-$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  AudioPlayerState copyWith({
    AudioModel? currentAudio,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? playbackSpeed,
    SleepTimer? sleepTimer,
    bool? isRepeatEnabled,
    double? volume,
    bool? isBuffering,
    String? errorMessage,
    bool clearAudio = false,
    bool clearError = false,
  }) {
    return AudioPlayerState(
      currentAudio: clearAudio ? null : (currentAudio ?? this.currentAudio),
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      sleepTimer: sleepTimer ?? this.sleepTimer,
      isRepeatEnabled: isRepeatEnabled ?? this.isRepeatEnabled,
      volume: volume ?? this.volume,
      isBuffering: isBuffering ?? this.isBuffering,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
