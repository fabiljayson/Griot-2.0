import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/auth/providers/auth_provider.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';
import 'package:griot_ai/features/stories/widgets/story_video_section.dart';
import 'package:griot_ai/features/video/providers/video_provider.dart';
import 'package:griot_ai/features/video/widgets/video_player_widget.dart';

class _SignedOutAuthNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async =>
      const AuthState(status: AuthStatus.unauthenticated);
}

class _EmptyVideoGenerationNotifier extends VideoGenerationNotifier {
  @override
  Future<void> loadJobs() async {}
}

const _story = StoryModel(
  id: 1,
  title: 'The Legend of Mount Mbapit',
  author: UserModel(id: 1, username: 'demo'),
  videoUrl: 'https://cdn.example.com/mount-mbapit.mp4',
);

void main() {
  testWidgets('shows an existing story video without a generation job', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(() => _SignedOutAuthNotifier()),
          videoGenerationProvider.overrideWith(
            (ref) => _EmptyVideoGenerationNotifier(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: StoryVideoSection(story: _story)),
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(StoryVideoPlayer), findsOneWidget);
  });
}
