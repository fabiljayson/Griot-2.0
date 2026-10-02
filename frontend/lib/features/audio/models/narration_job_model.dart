import 'audio_model.dart';

/// Model for a text-to-speech narration job.
///
/// A narration job converts the story of a story or artifact into speech
/// via the backend gTTS service and exposes the generated audio for
/// playback in the app's audio player.
class NarrationJobModel {
  const NarrationJobModel({
    required this.id,
    this.storyId,
    this.artifactId,
    this.title = '',
    this.narrationText = '',
    this.language = 'en',
    this.voiceId = 'default',
    this.speed = 1.0,
    this.status = NarrationStatus.processing,
    this.audioUrl = '',
    this.duration = 0,
    this.fileSize = 0,
    this.errorMessage,
    this.originKind = 'synthetic',
    this.engine = '',
    this.reviewedBySource = false,
    this.attribution = '',
    this.isSynthetic = true,
    this.createdAt = '',
    this.completedAt,
  });

  final int id;
  final int? storyId;
  final int? artifactId;

  /// Display title: the story title, or the artifact title for audio guides.
  final String title;

  /// Snapshot of the text that was converted to speech.
  final String narrationText;
  final String language;
  final String voiceId;
  final double speed;
  final NarrationStatus status;
  final String audioUrl;
  final int duration; // in seconds
  final int fileSize; // in bytes
  final String? errorMessage;

  // --- Provenance ---
  //
  // A text-to-speech voice reciting an oral tradition is not the teller. These
  // fields let the player say which engine spoke rather than presenting a
  // machine's output as a recorded narrator.
  final String originKind;

  /// Name/version of the engine that produced the audio (e.g. `gtts`).
  final String engine;

  /// Whether a source community member reviewed and approved this narration.
  final bool reviewedBySource;

  /// Credit line composed server-side, so the app never words it differently
  /// from the web.
  final String attribution;

  /// True when a model produced this audio rather than a human narrator.
  final bool isSynthetic;

  final String createdAt;
  final String? completedAt;

  factory NarrationJobModel.fromJson(Map<String, dynamic> json) {
    return NarrationJobModel(
      id: json['id'] as int? ?? 0,
      storyId: json['story'] as int?,
      artifactId: json['artifact_id'] as int?,
      title: json['story_title'] as String? ?? '',
      narrationText: json['narration_text'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
      voiceId: json['voice_id'] as String? ?? 'default',
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      status: NarrationStatus.fromString(json['status'] as String? ?? ''),
      audioUrl: json['audio_url'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      fileSize: json['file_size'] as int? ?? 0,
      errorMessage: json['error_message'] as String?,
      originKind: json['origin_kind'] as String? ?? 'synthetic',
      engine: json['engine'] as String? ?? '',
      reviewedBySource: json['reviewed_by_source'] as bool? ?? false,
      attribution: json['attribution'] as String? ?? '',
      isSynthetic: json['is_synthetic'] as bool? ?? true,
      createdAt: json['created_at'] as String? ?? '',
      completedAt: json['completed_at'] as String?,
    );
  }

  /// Whether the audio is ready to play.
  bool get isCompleted => status == NarrationStatus.completed;

  /// Whether the narration is still being generated.
  bool get isProcessing =>
      status == NarrationStatus.pending ||
      status == NarrationStatus.processing;

  /// Whether the narration failed.
  bool get hasFailed => status == NarrationStatus.failed;

  /// Map a language code to one the backend gTTS service supports.
  ///
  /// Unknown codes (e.g., regional story languages) fall back to English.
  static String supportedLanguage(String language) {
    const supported = {'en', 'fr', 'es', 'pt', 'de', 'sw', 'ig', 'yo', 'ha', 'am'};
    return supported.contains(language) ? language : 'en';
  }

  /// Convert into an [AudioModel] ready for the audio player.
  AudioModel toAudioModel() {
    return AudioModel(
      id: id,
      storyId: storyId ?? artifactId ?? 0,
      storyTitle: title,
      url: audioUrl,
      duration: duration,
      // The credit the server composed, e.g. "AI-generated narration (gtts)".
      // Never a bare "Griot AI": that reads as a person who told the story.
      narrator: attribution.isNotEmpty ? attribution : _fallbackAttribution,
      language: language,
      createdAt: createdAt,
    );
  }

  /// Used when the server sent no credit line — an older backend, or a job
  /// mirrored into the cache before this field existed. Says only what is
  /// true: that the audio is computer-generated, and by what is known.
  String get _fallbackAttribution {
    if (!isSynthetic) return 'Recorded by a human narrator';
    return engine.isNotEmpty
        ? 'AI-generated narration ($engine)'
        : 'AI-generated narration';
  }
}

/// Narration job status.
enum NarrationStatus {
  pending('pending'),
  processing('processing'),
  completed('completed'),
  failed('failed');

  const NarrationStatus(this.value);

  final String value;

  factory NarrationStatus.fromString(String value) {
    return NarrationStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => NarrationStatus.processing,
    );
  }
}
