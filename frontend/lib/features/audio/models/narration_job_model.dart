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
      narrator: 'Griot AI',
      language: language,
      createdAt: createdAt,
    );
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
