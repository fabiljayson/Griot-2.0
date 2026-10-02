import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/features/audio/models/narration_job_model.dart';

/// A text-to-speech voice reciting someone's tradition is not that person.
///
/// These pin the credit line the player shows, including the case where the
/// backend told us nothing — the app must then say less, not invent a name.
void main() {
  NarrationJobModel jobWith(Map<String, dynamic> overrides) {
    return NarrationJobModel.fromJson({
      'id': 7,
      'story': 3,
      'story_title': 'The Song of the Frog',
      'status': 'completed',
      'audio_url': '/media/frog.mp3',
      ...overrides,
    });
  }

  group('NarrationJobModel provenance', () {
    test('reads the engine and credit the server sent', () {
      final job = jobWith({
        'origin_kind': 'synthetic',
        'engine': 'gtts',
        'attribution': 'AI-generated narration (gtts)',
        'is_synthetic': true,
      });

      expect(job.engine, 'gtts');
      expect(job.isSynthetic, isTrue);
      expect(job.attribution, 'AI-generated narration (gtts)');
    });

    test('a human recording is not presented as synthetic', () {
      final job = jobWith({
        'origin_kind': 'human_recording',
        'engine': '',
        'attribution': 'Recorded narration by a human narrator',
        'is_synthetic': false,
      });

      expect(job.isSynthetic, isFalse);
      expect(job.toAudioModel().narrator, 'Recorded narration by a human narrator');
    });

    test('a job from an older payload is treated as synthetic', () {
      final job = jobWith({});

      expect(job.isSynthetic, isTrue,
          reason: 'gTTS output is synthetic; defaulting to false would claim otherwise');
      expect(job.originKind, 'synthetic');
    });
  });

  group('NarrationJobModel.toAudioModel', () {
    test('uses the server credit rather than naming the app as narrator', () {
      final job = jobWith({
        'engine': 'gtts',
        'attribution': 'AI-generated narration (gtts)',
      });

      final audio = job.toAudioModel();

      expect(audio.narrator, 'AI-generated narration (gtts)');
      expect(
        audio.narrator,
        isNot('Griot AI'),
        reason: 'an app name reads as a person who told the story',
      );
    });

    test('falls back to the engine when the server sent no credit line', () {
      final job = jobWith({'engine': 'gtts', 'attribution': ''});

      expect(job.toAudioModel().narrator, 'AI-generated narration (gtts)');
    });

    test('falls back to a bare disclosure when even the engine is unknown', () {
      final job = jobWith({'engine': '', 'attribution': ''});

      expect(job.toAudioModel().narrator, 'AI-generated narration');
    });

    test('keeps the story title and url intact', () {
      final job = jobWith({
        'attribution': 'AI-generated narration (gtts)',
        'duration': 42,
      });

      final audio = job.toAudioModel();

      expect(audio.storyTitle, 'The Song of the Frog');
      expect(audio.url, '/media/frog.mp3');
      expect(audio.duration, 42);
    });
  });
}
