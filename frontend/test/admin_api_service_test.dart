import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:african_teller/features/admin/services/admin_api_service.dart';

import 'support/admin_fixtures.dart';

/// Fake [HttpClientAdapter] that serves canned JSON per request path so the
/// service can be tested without a real network stack.
class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this._responses);

  /// Maps request path (e.g. `/api/analytics/users/`) to a JSON body.
  final Map<String, Object> _responses;

  final List<String> requestedPaths = [];

  /// Captured requests, for asserting method and body.
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.uri.path);
    requests.add(options);

    final body = _responses[options.uri.path];
    if (body == null) {
      return ResponseBody.fromString(
        '{"detail": "Not found."}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

({AdminApiService service, _FakeHttpAdapter adapter}) _serviceWith(
  Map<String, Object> responses,
) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  final adapter = _FakeHttpAdapter(responses);
  dio.httpClientAdapter = adapter;
  return (service: AdminApiService(dio: dio), adapter: adapter);
}

void main() {
  group('AdminApiService', () {
    test('getDashboardSummary hits /dashboard/ and parses', () async {
      final setup = _serviceWith({
        '/api/analytics/dashboard/': adminDashboardJson(),
      });

      final summary = await setup.service.getDashboardSummary();

      expect(setup.adapter.requestedPaths, ['/api/analytics/dashboard/']);
      expect(summary.users.totalUsers, 142);
      expect(summary.stories.totalStories, 87);
      expect(summary.gamification.avgScore, 81.0);
      expect(summary.qrCodes.uniqueScanners, 312);
      expect(summary.engagement.unresolvedFlags, 1);
    });

    test('getUserStats hits /users/ and parses', () async {
      final setup = _serviceWith({
        '/api/analytics/users/': adminUserStatsJson(),
      });

      final stats = await setup.service.getUserStats();

      expect(setup.adapter.requestedPaths, ['/api/analytics/users/']);
      expect(stats.totalUsers, 142);
      expect(stats.activeUsers30d, 58);
      expect(stats.usersByRole['contributor'], 40);
    });

    test('getStoryStats hits /stories/ and parses', () async {
      final setup = _serviceWith({
        '/api/analytics/stories/': adminStoryStatsJson(),
      });

      final stats = await setup.service.getStoryStats();

      expect(setup.adapter.requestedPaths, ['/api/analytics/stories/']);
      expect(stats.totalStories, 87);
      expect(stats.totalViews, 12500);
      expect(stats.topStories.first.title, 'The Wise Spider');
    });

    test('getGamificationStats hits /gamification/ and parses', () async {
      final setup = _serviceWith({
        '/api/analytics/gamification/': adminGamificationJson(),
      });

      final stats = await setup.service.getGamificationStats();

      expect(setup.adapter.requestedPaths, ['/api/analytics/gamification/']);
      expect(stats.totalQuizzesTaken, 214);
      expect(stats.passRate, 78.5);
      expect(stats.topUsers.first.username, 'kemi');
    });

    test('getQRStats hits /qr-codes/ and parses', () async {
      final setup = _serviceWith({'/api/analytics/qr-codes/': adminQrJson()});

      final stats = await setup.service.getQRStats();

      expect(setup.adapter.requestedPaths, ['/api/analytics/qr-codes/']);
      expect(stats.totalScans, 987);
      expect(stats.topArtifacts.first.museumName, 'Musée du Cameroun');
    });

    test('getEngagementSummary hits /engagement/ and parses', () async {
      final setup = _serviceWith({
        '/api/analytics/engagement/': adminEngagementJson(),
      });

      final summary = await setup.service.getEngagementSummary();

      expect(setup.adapter.requestedPaths, ['/api/analytics/engagement/']);
      expect(summary.totalReadingTime, 148200);
      expect(summary.recentActivity.qrScans, 58);
    });
    test(
      'getModerationQueue hits /stories/moderation-queue/ and parses',
      () async {
        final setup = _serviceWith({
          '/api/stories/moderation-queue/': adminModerationQueueJson(),
        });

        final queue = await setup.service.getModerationQueue();

        expect(setup.adapter.requestedPaths, [
          '/api/stories/moderation-queue/',
        ]);
        expect(queue, hasLength(1));
        expect(queue.first.title, 'The Wrong Spider');
        expect(queue.first.authorUsername, 'author1');
        expect(queue.first.flags, hasLength(2));
        expect(queue.first.flags.first.reasonDisplay, 'Cultural Inaccuracy');
      },
    );

    test('moderateStory posts the action and notes', () async {
      final setup = _serviceWith({
        '/api/stories/the-wrong-spider/moderate/': {
          'story_id': 11,
          'slug': 'the-wrong-spider',
          'status': 'archived',
          'action': 'remove',
          'resolved_flags': 2,
        },
      });

      final result = await setup.service.moderateStory(
        slug: 'the-wrong-spider',
        action: 'remove',
        notes: 'Removed for inaccuracy.',
      );

      expect(setup.adapter.requestedPaths, [
        '/api/stories/the-wrong-spider/moderate/',
      ]);
      final request = setup.adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.data, {
        'action': 'remove',
        'notes': 'Removed for inaccuracy.',
      });
      expect(result['status'], 'archived');
      expect(result['resolved_flags'], 2);
    });

    test(
      'surfaces a DioException when the endpoint returns an error',
      () async {
        final setup = _serviceWith(const {});

        expect(
          () => setup.service.getDashboardSummary(),
          throwsA(isA<DioException>()),
        );
      },
    );
  });
}
