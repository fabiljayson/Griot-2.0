import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/database/models/offline_request.dart';
import 'package:griot_ai/core/database/repositories/offline_request_repository.dart';
import 'package:griot_ai/core/network/api_client.dart';
import 'package:griot_ai/core/network/connectivity_service.dart';

class _MockOfflineRepository extends Mock implements OfflineRequestRepository {}

class _MockConnectivity extends Mock implements ConnectivityService {}

class _MockHandler extends Mock implements RequestInterceptorHandler {}

// Mocktail cannot match `any()` on a type it has no fallback instance for.
class _FakeDioException extends Fake implements DioException {}

class _FakeResponse extends Fake implements Response<dynamic> {}

class _FakeRequestOptions extends Fake implements RequestOptions {}

/// The offline queue answers every non-GET request with a synthetic 202 when
/// the device is offline, and replays the request later. For an endpoint that
/// mints a credential that is wrong twice over: the caller is told it succeeded,
/// and the replayed request carries a secret that has since expired.
///
/// `/api/auth/` was the original case; `/api/vr/launch/` is the new one, where
/// the replayed body would hold a launch token that is good for 120 seconds and
/// one use. This test pins both, and pins the contrasting case so the rule is
/// not accidentally widened (or narrowed) to "never queue anything".
void main() {
  late _MockOfflineRepository repo;
  late _MockConnectivity connectivity;
  late _MockHandler handler;

  setUpAll(() {
    registerFallbackValue(_FakeDioException());
    registerFallbackValue(_FakeResponse());
    registerFallbackValue(_FakeRequestOptions());
  });

  setUp(() {
    repo = _MockOfflineRepository();
    connectivity = _MockConnectivity();
    handler = _MockHandler();
    when(() => connectivity.isOnline).thenReturn(false);
  });

  OfflineQueueInterceptor build() => OfflineQueueInterceptor(
    offlineRepository: repo,
    connectivityService: connectivity,
  );

  /// Drive one request through the interceptor.
  ///
  /// `Interceptor.onRequest` is declared `void` even though this override's
  /// body awaits the repository before deciding, so the pending microtasks are
  /// drained before the assertions look at the handler.
  Future<void> send(
    OfflineQueueInterceptor interceptor,
    String path,
    String method,
  ) async {
    interceptor.onRequest(RequestOptions(path: path, method: method), handler);
    await pumpEventQueue();
  }

  test('a VR launch is refused offline instead of being queued', () async {
    await send(build(), '/api/vr/launch/', 'POST');

    verifyNever(
      () => repo.saveRequest(
        method: any(named: 'method'),
        path: any(named: 'path'),
        body: any(named: 'body'),
        headers: any(named: 'headers'),
      ),
    );
    verify(() => handler.reject(any())).called(1);
    verifyNever(() => handler.resolve(any()));
  });

  test('an auth request is still refused offline', () async {
    await send(build(), '/api/auth/token/', 'POST');

    verify(() => handler.reject(any())).called(1);
    verifyNever(() => handler.resolve(any()));
  });

  test('an ordinary write is still queued offline', () async {
    when(
      () => repo.saveRequest(
        method: any(named: 'method'),
        path: any(named: 'path'),
        body: any(named: 'body'),
        headers: any(named: 'headers'),
      ),
    ).thenAnswer(
      (_) async => const OfflineRequest(method: 'POST', path: '/api/stories/'),
    );

    await send(build(), '/api/stories/', 'POST');

    verify(
      () => repo.saveRequest(
        method: 'POST',
        path: '/api/stories/',
        body: any(named: 'body'),
        headers: any(named: 'headers'),
      ),
    ).called(1);

    // The synthetic 202 is how the rest of the app keeps working offline; a
    // story draft is safe to replay, unlike a launch token.
    verify(() => handler.resolve(any())).called(1);
    verifyNever(() => handler.reject(any()));
  });

  test('a VR launch is allowed through when the device is online', () async {
    when(() => connectivity.isOnline).thenReturn(true);

    await send(build(), '/api/vr/launch/', 'POST');

    verify(() => handler.next(any())).called(1);
    verifyNever(() => handler.reject(any()));
  });
}
