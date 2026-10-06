import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:griot_ai/core/database/app_database.dart';
import 'package:griot_ai/core/database/repositories/offline_request_repository.dart';
import 'package:griot_ai/core/database/repositories/offline_user_repository.dart';
import 'package:griot_ai/core/network/api_client.dart';
import 'package:griot_ai/core/network/auth_interceptor.dart';
import 'package:griot_ai/core/network/offline_sync_manager.dart';
import 'package:griot_ai/core/providers/database_providers.dart';
import 'package:griot_ai/features/admin/providers/admin_provider.dart';
import 'package:griot_ai/features/auth/providers/auth_provider.dart';
import 'package:griot_ai/features/auth/repositories/auth_repository.dart';
import 'package:griot_ai/features/stories/providers/story_provider.dart';

import '../../support/admin_fixtures.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

/// Fake [HttpClientAdapter] recording every attempt and serving canned JSON.
class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter() : statusFor = null;

  /// Optional per-path status override (e.g. force a 200 for a path whose
  /// real payload shape is not the subject of the test).
  final int Function(String path)? statusFor;

  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final status = statusFor?.call(options.uri.path) ?? 200;
    final Object payload;
    if (options.uri.path == '/api/stories/moderation_queue/') {
      payload = adminModerationQueueJson();
    } else if (options.uri.path == '/api/stories/consent_queue/') {
      payload = adminConsentQueueJson();
    } else {
      payload = <String, dynamic>{
        'consent_status': 'pending',
        'bookmarked': true,
        'count': 0,
        'results': <Object>[],
        'users': adminUserStatsJson(),
        'stories': adminStoryStatsJson(),
        'gamification': adminGamificationJson(),
        'qr_codes': adminQrJson(),
        'engagement': adminEngagementJson(),
      };
    }
    return ResponseBody.fromString(
      jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// An [ApiClient] wired with the real [AuthInterceptor] and a fake token
/// store, so these tests exercise the production wiring rather than a mock.
({ApiClient client, _FakeHttpAdapter adapter}) _authenticatedClient({
  _FakeHttpAdapter? adapter,
}) {
  final authRepository = _MockAuthRepository();
  when(() => authRepository.accessToken).thenAnswer((_) async => 'test-token');
  when(
    () => authRepository.refreshTokens(),
  ).thenAnswer((_) async => throw Exception('no refresh available'));

  final fake = adapter ?? _FakeHttpAdapter();
  final client = ApiClient.withAuth(
    authInterceptor: AuthInterceptor(authRepository: authRepository),
    baseUrl: 'https://api.example.com',
  );
  client.dio.httpClientAdapter = fake;
  return (client: client, adapter: fake);
}

void main() {
  setUpAll(() {
    // Repositories write through sqflite; the ffi factory keeps the local
    // side of each repository call working without a device.
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('stories mutations present a Bearer token', () {
    late ProviderContainer container;
    late _FakeHttpAdapter adapter;

    setUp(() {
      final wired = _authenticatedClient();
      adapter = wired.adapter;
      container = ProviderContainer(
        overrides: [
          authenticatedApiClientProvider.overrideWithValue(wired.client),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('requestConsent posts to the underscored route with auth', () async {
      final repository = container.read(storyRepositoryProvider);

      await repository.requestConsent('the-baobab-and-the-drum');

      final request = adapter.requests.single;
      expect(
        request.uri.path,
        '/api/stories/the-baobab-and-the-drum/request_consent/',
      );
      expect(
        request.headers['Authorization'],
        'Bearer test-token',
        reason: 'consent requests require IsAuthenticated on the backend',
      );
    });

    test('bookmark toggle presents a Bearer token', () async {
      final repository = container.read(storyRepositoryProvider);

      await repository.toggleBookmark('the-baobab-and-the-drum');

      final request = adapter.requests.single;
      expect(
        request.uri.path,
        '/api/stories/the-baobab-and-the-drum/bookmark/',
      );
      expect(request.headers['Authorization'], 'Bearer test-token');
    });
  });

  group('admin service presents a Bearer token', () {
    late ProviderContainer container;
    late _FakeHttpAdapter adapter;

    setUp(() {
      final wired = _authenticatedClient();
      adapter = wired.adapter;
      container = ProviderContainer(
        overrides: [
          authenticatedApiClientProvider.overrideWithValue(wired.client),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('dashboard summary request is authenticated', () async {
      await container.read(dashboardSummaryProvider.future);

      final request = adapter.requests.single;
      expect(request.uri.path, '/api/analytics/dashboard/');
      expect(
        request.headers['Authorization'],
        'Bearer test-token',
        reason:
            'admin analytics requires IsAdminOrManager; an anonymous call '
            'is either a permanent 401 or an unauthenticated data leak',
      );
    });

    test('moderation queue request is authenticated', () async {
      await container.read(moderationQueueProvider.future);

      final request = adapter.requests.single;
      expect(request.uri.path, '/api/stories/moderation_queue/');
      expect(request.headers['Authorization'], 'Bearer test-token');
    });
  });

  group('offline replay', () {
    late AppDatabase appDb;
    late String dbPath;
    late ProviderContainer container;
    late _FakeHttpAdapter adapter;

    setUp(() async {
      dbPath = p.join(await getDatabasesPath(), 'griot_auth_wiring_test.db');
      final previous = File(dbPath);
      if (previous.existsSync()) previous.deleteSync();
      appDb = AppDatabase.forTesting(name: 'griot_auth_wiring_test.db');

      final wired = _authenticatedClient();
      adapter = wired.adapter;
      container = ProviderContainer(
        overrides: [
          authenticatedApiClientProvider.overrideWithValue(wired.client),
          offlineRequestRepositoryProvider.overrideWithValue(
            OfflineRequestRepository(database: appDb),
          ),
          offlineUserRepositoryProvider.overrideWithValue(
            OfflineUserRepository(database: appDb),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await appDb.close();
      final file = File(dbPath);
      if (file.existsSync()) file.deleteSync();
    });

    test('a queued mutation replays with a live Bearer token', () async {
      final repo = container.read(offlineRequestRepositoryProvider);
      // Credential headers are stripped at queue time by design; the replay
      // must re-attach the current token via AuthInterceptor.
      await repo.saveRequest(
        method: 'POST',
        path: '/api/stories/the-baobab-and-the-drum/progress/',
        body: <String, dynamic>{'scroll_fraction': 0.5},
        headers: {'Authorization': 'Bearer stale-token'},
      );

      final manager = container.read(offlineSyncManagerProvider);
      await manager.triggerSync();

      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri.path,
        '/api/stories/the-baobab-and-the-drum/progress/',
      );
      expect(
        request.headers['Authorization'],
        'Bearer test-token',
        reason:
            'queued rows never store credentials; replay must re-attach '
            'the live token or every queued mutation fails forever',
      );
      expect(
        request.uri.host,
        'api.example.com',
        reason:
            'replay must keep the client baseUrl or the relative URI '
            'never reaches the server',
      );
    });
  });
}
