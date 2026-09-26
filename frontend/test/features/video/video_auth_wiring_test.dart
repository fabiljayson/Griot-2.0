import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/network/api_client.dart';
import 'package:griot_ai/core/network/auth_interceptor.dart';
import 'package:griot_ai/features/auth/providers/auth_provider.dart';
import 'package:griot_ai/features/auth/repositories/auth_repository.dart';
import 'package:griot_ai/features/video/providers/video_provider.dart';
import 'package:griot_ai/features/video/services/video_api_service.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

/// Fake [HttpClientAdapter] recording the headers of every attempt.
class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter({this.statusCode = 200});

  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        statusCode == 200
            ? const {'count': 0, 'results': <Object>[]}
            : const {'detail': 'Authentication credentials were not provided.'},
      ),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The media endpoints require a signed-in user. `VideoApiService` used to be
/// a singleton built on the bare `ApiClient.instance`, which carries no
/// `AuthInterceptor`, so every request went out unauthenticated and came back
/// 401 — video generation could not work for anyone. These tests pin that the
/// provider presents the real token.
void main() {
  late _FakeHttpAdapter adapter;
  late ProviderContainer container;

  setUp(() async {
    adapter = _FakeHttpAdapter();

    final authRepository = _MockAuthRepository();
    when(() => authRepository.accessToken).thenAnswer((_) async => 'test-token');

    // The real ApiClient + real AuthInterceptor, only the token store faked.
    final apiClient = ApiClient.withAuth(
      authInterceptor: AuthInterceptor(authRepository: authRepository),
      baseUrl: 'https://api.example.com',
    );
    apiClient.dio.httpClientAdapter = adapter;

    container = ProviderContainer(
      overrides: [
        authenticatedApiClientProvider.overrideWithValue(apiClient),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('videoGenerationProvider', () {
    test('should send a Bearer token on every request', () async {
      await container.read(videoGenerationProvider.notifier).loadJobs();

      expect(adapter.requests, isNotEmpty);
      for (final request in adapter.requests) {
        expect(
          request.headers['Authorization'],
          'Bearer test-token',
          reason: '${request.method} ${request.path} must be authenticated',
        );
      }
    });

    test('should call the authenticated media endpoint', () async {
      await container.read(videoGenerationProvider.notifier).loadJobs();

      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.path, '/api/media/videos/');
    });

    test('should surface a 401 as a readable message, not a raw exception', () async {
      final failing = _FakeHttpAdapter(statusCode: 401);
      final authRepository = _MockAuthRepository();
      when(() => authRepository.accessToken).thenAnswer((_) async => 'test-token');
      when(() => authRepository.refreshTokens())
          .thenAnswer((_) async => throw Exception('no refresh available'));

      final apiClient = ApiClient.withAuth(
        authInterceptor: AuthInterceptor(authRepository: authRepository),
        baseUrl: 'https://api.example.com',
      );
      apiClient.dio.httpClientAdapter = failing;

      final scoped = ProviderContainer(
        overrides: [
          authenticatedApiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(scoped.dispose);

      await scoped.read(videoGenerationProvider.notifier).loadJobs();

      final error = scoped.read(videoGenerationProvider).errorMessage;
      expect(error, isNotNull);
      // A raw DioException.toString() dumps request options and internals.
      expect(error, isNot(contains('DioException')));
      expect(error, isNot(contains('RequestOptions')));
    });
  });

  group('VideoApiService', () {
    test('uses the injected Dio rather than the unauthenticated singleton', () async {
      final localAdapter = _FakeHttpAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
      dio.httpClientAdapter = localAdapter;

      await VideoApiService(dio: dio).listVideoJobs();

      expect(localAdapter.requests, hasLength(1));
      expect(
        localAdapter.requests.single.uri.toString(),
        contains('/api/media/videos/'),
      );
    });
  });
}
