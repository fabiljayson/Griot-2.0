import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/features/audio/models/narration_job_model.dart';
import 'package:griot_ai/features/audio/providers/audio_provider.dart';
import 'package:griot_ai/features/audio/services/audio_api_service.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/auth/providers/auth_provider.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';
import 'package:griot_ai/features/stories/providers/story_provider.dart';
import 'package:griot_ai/features/stories/repositories/story_repository.dart';
import 'package:griot_ai/features/stories/screens/story_detail_screen.dart';

class _MockAudioApiService extends Mock implements AudioApiService {}

class _MockStoryRepository extends Mock implements StoryRepository {}

class _FakeAuthNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      const AuthState(status: AuthStatus.authenticated);
}

const _story = StoryModel(
  id: 1,
  title: 'The Legend of Mount Mbapit',
  slug: 'the-legend-of-mount-mbapit',
  summary: 'A crater lake born from grief.',
  language: 'en',
  author: UserModel(id: 1, username: 'demo'),
);

/// Verifies the story screen's "Listen" button generates the story narration
/// and hands the completed job (with its playable, absolute audio URL) to the
/// audio player — i.e. it renders the *respective* audio for that story.
void main() {
  testWidgets('Listen button plays the generated narration for the story', (
    tester,
  ) async {
    const audioUrl = 'https://griot-backend-7ie7.onrender.com'
        '/media/audio/story_1_en.mp3';

    final api = _MockAudioApiService();
    when(
      () => api.generateNarration(
        storyId: 1,
        artifactId: any(named: 'artifactId'),
        language: 'en',
        speed: any(named: 'speed'),
      ),
    ).thenAnswer((_) async => const NarrationJobModel(
      id: 42,
      storyId: 1,
      title: 'The Legend of Mount Mbapit',
      status: NarrationStatus.completed,
      audioUrl: audioUrl,
      narrationText: 'Long ago…',
    ));

    final repo = _MockStoryRepository();
    when(() => repo.getStory('the-legend-of-mount-mbapit'))
        .thenAnswer((_) async => _story);

    final playedUrls = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storyRepositoryProvider.overrideWithValue(repo),
          authProvider.overrideWith(() => _FakeAuthNotifier()),
          audioNarrationProvider.overrideWith(
            (ref) => AudioNarrationNotifier(
              apiService: api,
              onReady: (job) async => playedUrls.add(job.audioUrl),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const StoryDetailScreen(
            slug: 'the-legend-of-mount-mbapit',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byTooltip('Listen'), findsOneWidget);
    await tester.tap(find.byTooltip('Listen'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(playedUrls, [audioUrl]);
    expect(tester.takeException(), isNull);
  });
}