import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/features/audio/models/narration_job_model.dart';
import 'package:griot_ai/features/audio/providers/audio_provider.dart';
import 'package:griot_ai/features/audio/services/audio_api_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockAudioApiService extends Mock implements AudioApiService {}

/// A failed synthesis comes back as a normal 201 with `status: "failed"` and
/// the reason on the job — it is not an exception. The notifier used to store
/// that job and say nothing, so the spinner stopped and no feedback ever
/// appeared. These tests pin the reporting.
void main() {
  late _MockAudioApiService apiService;
  late List<NarrationJobModel> played;

  setUpAll(() {
    registerFallbackValue(1);
  });

  setUp(() {
    apiService = _MockAudioApiService();
    played = [];
  });

  AudioNarrationNotifier build() => AudioNarrationNotifier(
    apiService: apiService,
    onReady: (job) async => played.add(job),
  );

  void stubGenerate(NarrationJobModel job) {
    when(
      () => apiService.generateNarration(
        storyId: any(named: 'storyId'),
        artifactId: any(named: 'artifactId'),
        language: any(named: 'language'),
      ),
    ).thenAnswer((_) async => job);
  }

  const failedJob = NarrationJobModel(
    id: 1,
    status: NarrationStatus.failed,
    errorMessage: 'Speech generation failed: 503 from Google',
  );

  const completedJob = NarrationJobModel(
    id: 2,
    status: NarrationStatus.completed,
    audioUrl: 'https://cdn.example.com/narration.mp3',
  );

  group('AudioNarrationNotifier.generateNarration', () {
    test('should report a failed job instead of returning silently', () async {
      stubGenerate(failedJob);
      final notifier = build();

      final result = await notifier.generateNarration(storyId: 1);

      expect(result, isNull);
      expect(notifier.state.isGenerating, isFalse);
      expect(
        notifier.state.errorMessage,
        'Speech generation failed: 503 from Google',
      );
      expect(played, isEmpty);
    });

    test('should fall back to a generic message when the job has no reason', () async {
      stubGenerate(
        const NarrationJobModel(id: 3, status: NarrationStatus.failed),
      );
      final notifier = build();

      await notifier.generateNarration(storyId: 1);

      expect(
        notifier.state.errorMessage,
        'Speech generation failed. Please try again.',
      );
    });

    test('should play a completed job and keep no error', () async {
      stubGenerate(completedJob);
      final notifier = build();

      final result = await notifier.generateNarration(storyId: 1);

      expect(result, completedJob);
      expect(played, [completedJob]);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.isGenerating, isFalse);
    });

    test('should clear a previous error when a later attempt succeeds', () async {
      stubGenerate(failedJob);
      final notifier = build();
      await notifier.generateNarration(storyId: 1);
      expect(notifier.state.errorMessage, isNotNull);

      stubGenerate(completedJob);
      await notifier.generateNarration(storyId: 1);

      expect(notifier.state.errorMessage, isNull);
    });

    test('should blame the server, not the network, on a receive timeout', () async {
      when(
        () => apiService.generateNarration(
          storyId: any(named: 'storyId'),
          artifactId: any(named: 'artifactId'),
          language: any(named: 'language'),
        ),
      ).thenThrow(
        DioException.receiveTimeout(
          timeout: const Duration(seconds: 90),
          requestOptions: RequestOptions(path: '/api/media/audio/'),
        ),
      );
      final notifier = build();

      await notifier.generateNarration(storyId: 1);

      // The shared mapper says "check your network", which sends users to
      // debug the wrong thing when the server was simply still synthesising.
      expect(notifier.state.errorMessage, isNot(contains('check your network')));
      expect(notifier.state.errorMessage, contains('taking too long'));
    });

    test('should ask the user to sign in on a 401', () async {
      when(
        () => apiService.generateNarration(
          storyId: any(named: 'storyId'),
          artifactId: any(named: 'artifactId'),
          language: any(named: 'language'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/media/audio/'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/api/media/audio/'),
            statusCode: 401,
          ),
        ),
      );
      final notifier = build();

      await notifier.generateNarration(storyId: 1);

      expect(notifier.state.errorMessage, 'Please sign in to generate narrations.');
    });
  });
}
