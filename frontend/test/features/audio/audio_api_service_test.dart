import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/audio/services/audio_api_service.dart';

/// Fake [HttpClientAdapter] that serves one canned JSON body and records every
/// attempt, so retry behaviour is observable.
class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this.body);

  final Map<String, dynamic> body;

  /// One entry per network attempt — a retried request appears repeatedly.
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
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

/// The narration endpoint synthesises synchronously server-side, so the client
/// asks for a long receive timeout. The shared `ApiClient` also installs a
/// 3x backoff `RetryInterceptor`, which against that timeout meant a single
/// slow response could stall the UI for four attempts — up to twelve minutes —
/// while re-running the whole synthesis each time. The call opts out.
void main() {
  late _FakeHttpAdapter adapter;
  late Dio dio;

  AudioApiService buildService() => AudioApiService(dio: dio);

  setUp(() {
    adapter = _FakeHttpAdapter(const {
      'id': 1,
      'status': 'completed',
      'audio_url': 'https://cdn.example.com/n.mp3',
    });
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
    dio.httpClientAdapter = adapter;
  });

  group('AudioApiService.generateNarration', () {
    test('should mark the request as non-retryable', () async {
      await buildService().generateNarration(storyId: 5);

      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.extra['disableRetry'], isTrue);
    });

    test('should not be retried even when a retry interceptor is installed', () async {
      // Mirrors the real client, which always has the backoff interceptor.
      dio.interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) {
            // Simulate the retry interceptor kicking in on a timeout.
            if (error.requestOptions.extra['disableRetry'] == true) {
              return handler.next(error);
            }
            handler.resolve(
              Response(
                requestOptions: error.requestOptions,
                data: const {'id': 99, 'status': 'retried'},
              ),
            );
          },
        ),
      );

      final job = await buildService().generateNarration(storyId: 5);

      // Without the opt-out the interceptor would have substituted its own
      // response and the caller would never learn the request was retried.
      expect(adapter.requests, hasLength(1));
      expect(job.id, 1);
      expect(job.isCompleted, isTrue);
    });

    test('should use a long but finite receive timeout', () async {
      await buildService().generateNarration(storyId: 5);

      final timeout = adapter.requests.single.receiveTimeout;
      expect(timeout, isNotNull);
      expect(timeout!.inSeconds, greaterThanOrEqualTo(60));
      expect(timeout.inSeconds, lessThanOrEqualTo(120));
    });

    test('should post to the audio endpoint with the story id', () async {
      await buildService().generateNarration(storyId: 5, language: 'fr');

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/api/media/audio/');
      expect(request.data, containsPair('story_id', 5));
      expect(request.data, containsPair('language', 'fr'));
    });
  });
}
