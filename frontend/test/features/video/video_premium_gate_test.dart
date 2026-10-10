import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/features/subscriptions/models/subscription_status.dart';
import 'package:griot_ai/features/subscriptions/providers/subscription_provider.dart';
import 'package:griot_ai/features/video/providers/video_provider.dart';
import 'package:griot_ai/features/video/services/video_api_service.dart';
import 'package:griot_ai/features/video/widgets/video_generation_sheet.dart';

class MockVideoApiService extends Mock implements VideoApiService {}

/// Fails every create call the way Dio reports the backend's 402: a
/// `premium_required` refusal with the server's detail line.
DioException _premiumRefusal() {
  final request = RequestOptions(path: '/api/media/videos/');
  return DioException(
    requestOptions: request,
    response: Response(
      requestOptions: request,
      statusCode: 402,
      data: const {
        'detail': 'AI video generation requires a premium plan.',
        'code': 'premium_required',
      },
    ),
    type: DioExceptionType.badResponse,
  );
}

DioException _serverError() {
  final request = RequestOptions(path: '/api/media/videos/');
  return DioException(
    requestOptions: request,
    response: Response(
      requestOptions: request,
      statusCode: 500,
      data: {'detail': 'boom'},
    ),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('createVideo paywall handling', () {
    test('a 402 flips the state to paywalled with the server detail',
        () async {
      final api = MockVideoApiService();
      when(
        () => api.createVideoJob(
          storyId: any(named: 'storyId'),
          prompt: any(named: 'prompt'),
          duration: any(named: 'duration'),
          aspectRatio: any(named: 'aspectRatio'),
        ),
      ).thenThrow(_premiumRefusal());

      final container = ProviderContainer(
        overrides: [
          videoGenerationProvider.overrideWith(
            (ref) => VideoGenerationNotifier(apiService: api),
          ),
        ],
      );
      addTearDown(container.dispose);

      final job = await container
          .read(videoGenerationProvider.notifier)
          .createVideo(storyId: 7, prompt: 'savanna at golden hour');

      expect(job, isNull);
      final state = container.read(videoGenerationProvider);
      expect(state.premiumRequired, isTrue);
      expect(
        state.errorMessage,
        'AI video generation requires a premium plan.',
      );
      expect(state.isCreating, isFalse);
    });

    test('an ordinary failure is not mistaken for a paywall', () async {
      final api = MockVideoApiService();
      when(
        () => api.createVideoJob(
          storyId: any(named: 'storyId'),
          prompt: any(named: 'prompt'),
          duration: any(named: 'duration'),
          aspectRatio: any(named: 'aspectRatio'),
        ),
      ).thenThrow(_serverError());

      final container = ProviderContainer(
        overrides: [
          videoGenerationProvider.overrideWith(
            (ref) => VideoGenerationNotifier(apiService: api),
          ),
        ],
      );
      addTearDown(container.dispose);

      final job = await container
          .read(videoGenerationProvider.notifier)
          .createVideo(storyId: 7, prompt: 'savanna at golden hour');

      expect(job, isNull);
      final state = container.read(videoGenerationProvider);
      expect(state.premiumRequired, isFalse);
      expect(state.errorMessage, contains('Failed to create video'));
    });

    test('a retry after a refusal starts from a clean slate', () async {
      final api = MockVideoApiService();
      var calls = 0;
      when(
        () => api.createVideoJob(
          storyId: any(named: 'storyId'),
          prompt: any(named: 'prompt'),
          duration: any(named: 'duration'),
          aspectRatio: any(named: 'aspectRatio'),
        ),
      ).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) throw _premiumRefusal();
        throw _serverError();
      });

      final container = ProviderContainer(
        overrides: [
          videoGenerationProvider.overrideWith(
            (ref) => VideoGenerationNotifier(apiService: api),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(videoGenerationProvider.notifier);
      await notifier.createVideo(storyId: 7, prompt: 'first');
      expect(
        container.read(videoGenerationProvider).premiumRequired,
        isTrue,
      );

      await notifier.createVideo(storyId: 7, prompt: 'second');
      final state = container.read(videoGenerationProvider);
      // The second attempt failed on its merits, so the flag must not
      // survive from the first refusal.
      expect(state.premiumRequired, isFalse);
    });
  });

  group('VideoGenerationSheet gating', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required SubscriptionStatus status,
    }) async {
      final api = MockVideoApiService();
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            subscriptionProvider.overrideWith(
              () => _FixedStatusNotifier(status),
            ),
            videoGenerationProvider.overrideWith(
            (ref) => VideoGenerationNotifier(apiService: api),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SizedBox(
                height: 760,
                child: VideoGenerationSheet(
                  storyId: 1,
                  storyTitle: 'The Anansi tale',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a free reader never reaches the form', (tester) async {
      await pumpSheet(
        tester,
        status: SubscriptionStatus(
          subscribed: false,
          entitled: false,
          features: const [
            FeatureAccess(
              key: 'ai_video_generation',
              label: 'AI video generation',
              enabled: true,
              hasAccess: false,
            ),
          ],
        ),
      );

      expect(find.text('Unlock AI video generation'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Generate Video'), findsNothing);
    });

    testWidgets('an entitled reader gets the prompt form', (tester) async {
      await pumpSheet(
        tester,
        status: SubscriptionStatus(
          subscribed: true,
          entitled: true,
          status: 'active',
          features: const [
            FeatureAccess(
              key: 'ai_video_generation',
              label: 'AI video generation',
              enabled: true,
              hasAccess: true,
            ),
          ],
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Unlock AI video generation'), findsNothing);
      // The submit button sits below the fold — scroll the sheet's list
      // until it comes into view before asserting on it.
      await tester.scrollUntilVisible(
        find.text('Generate Video'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Generate Video'), findsOneWidget);
    });
  });
}

/// Mirrors the pattern used by the premium screen tests: the gate reads a
/// frozen payload, so the test pins the server's answer.
class _FixedStatusNotifier extends SubscriptionNotifier {
  _FixedStatusNotifier(this._status);

  final SubscriptionStatus _status;

  @override
  Future<SubscriptionStatus> build() async => _status;
}
