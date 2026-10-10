/// One voice the backend gTTS service can narrate with.
///
/// Shape mirrors the `VoiceSerializer` on
/// `GET /api/media/audio/available_voices/`.
class TtsVoiceModel {
  const TtsVoiceModel({
    required this.id,
    required this.name,
    required this.language,
    this.gender = 'neutral',
  });

  /// Stable id sent back as `voice_id` when generating a narration
  /// (`en`, `en.co.uk`, `fr`, …).
  final String id;

  /// Human label shown in the picker, e.g. `English (UK)`.
  final String name;

  /// Language code the voice actually speaks (`en`, `fr`, …).
  final String language;

  /// gTTS offers no distinct speaker models; the backend reports `neutral`.
  final String gender;

  factory TtsVoiceModel.fromJson(Map<String, dynamic> json) {
    return TtsVoiceModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
      gender: json['gender'] as String? ?? 'neutral',
    );
  }
}
