import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/network/api_reachability.dart';

/// Reachability is the signal the whole offline UI rests on, and it has two
/// easy-to-get-wrong properties.
///
/// **It is not connectivity.** A phone on healthy Wi-Fi with an asleep Render
/// instance must report unreachable, because that is the deployment's normal
/// state and the exact case the banner exists for.
///
/// **It needs hysteresis.** One dropped packet is not an outage. A threshold of
/// zero would make the banner strobe through every tunnel or lift, which reads
/// as a broken app and teaches the reader to ignore the one signal that
/// matters.
///
/// The interceptor cases construct [DioException]s directly rather than making
/// requests: the property under test is *how a failure is classified*, and
/// hitting a real host to produce one would test the network as much as the
/// code.
void main() {
  ApiReachability newTracker({int threshold = 2}) {
    final tracker = ApiReachability(failureThreshold: threshold);
    addTearDown(tracker.dispose);
    return tracker;
  }

  group('ApiReachability hysteresis', () {
    test('starts reachable so a cold start is not an outage', () {
      expect(newTracker().isReachable, isTrue);
    });

    test('one failure does not flip it', () {
      final tracker = newTracker(threshold: 2)..markUnreachable();

      expect(tracker.isReachable, isTrue,
          reason: 'a single failure is not an outage');
      expect(tracker.consecutiveFailures, 1);
    });

    test('consecutive failures at the threshold flip it', () {
      final tracker = newTracker(threshold: 2)
        ..markUnreachable()
        ..markUnreachable();

      expect(tracker.isReachable, isFalse);
    });

    test('an intervening success resets the streak', () {
      final tracker = newTracker(threshold: 2)
        ..markUnreachable()
        ..markReachable()
        ..markUnreachable();

      expect(tracker.isReachable, isTrue,
          reason: 'failures must be *consecutive* to count');
    });

    test('any success restores reachability immediately', () {
      final tracker = newTracker(threshold: 2)
        ..markUnreachable()
        ..markUnreachable();
      expect(tracker.isReachable, isFalse);

      tracker.markReachable();

      expect(tracker.isReachable, isTrue,
          reason: 'recovery should be unnoticeable');
      expect(tracker.consecutiveFailures, 0);
    });

    test('reset returns to the initial state', () {
      final tracker = newTracker(threshold: 1)..markUnreachable();
      expect(tracker.isReachable, isFalse);

      tracker.reset();

      expect(tracker.isReachable, isTrue);
    });
  });

  group('ApiReachability stream', () {
    test('emits the current value to a late subscriber', () async {
      final tracker = newTracker(threshold: 1)..markUnreachable();
      expect(tracker.isReachable, isFalse);

      // A reader who navigates to a screen after the backend died must not
      // wait for the next transition to learn about it.
      expect(await tracker.changes.first, isFalse);
    });

    test('emits on each transition', () async {
      final tracker = newTracker(threshold: 1);
      final seen = <bool>[];
      final sub = tracker.changes.listen(seen.add);
      await pumpEventQueue();

      tracker
        ..markUnreachable()
        ..markReachable();
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, [true, false, true]);
    });
  });

  group('ApiReachabilityInterceptor classifies failures', () {
    DioException failure(DioExceptionType type, {int? status}) =>
        DioException(
          requestOptions: RequestOptions(path: '/probe'),
          type: type,
          response: status == null
              ? null
              : Response<void>(
                  requestOptions: RequestOptions(path: '/probe'),
                  statusCode: status,
                ),
        );

    /// Drive the interceptor and let the pass-through settle.
    ///
    /// `ErrorInterceptorHandler.next` hands the failure to whoever is
    /// listening, which is the right behaviour for a real chain. Awaiting
    /// `handler.future` is what consumes it — without that, the rethrow
    /// surfaces as an unhandled async error and fails the test for a reason
    /// that has nothing to do with reachability.
    Future<void> reportError(ApiReachability tracker, DioException error) async {
      final interceptor = ApiReachabilityInterceptor(tracker);
      final handler = ErrorInterceptorHandler();

      // The listener has to be attached *before* onError runs. next(err)
      // completes the handler with an error synchronously inside the call, so
      // awaiting handler.future afterwards is already too late — Dart has
      // already reported an unhandled error. Swallowing it here means the test
      // fails on the reachability verdict rather than on dio's plumbing.
      // dio marks `future` protected, but it is the only handle on a
      // handler's outcome — there is no public alternative for driving an
      // interceptor outside a live Dio chain.
      // ignore: invalid_use_of_protected_member
      final settled = handler.future.then<void>((_) {}, onError: (_, _) {});

      interceptor.onError(error, handler);
      await settled;
    }

    test('a 5xx counts as reachable — the server answered', () async {
      final tracker = newTracker(threshold: 1);

      await reportError(
        tracker,
        failure(DioExceptionType.badResponse, status: 500),
      );

      expect(
        tracker.isReachable,
        isTrue,
        reason:
            'DNS resolved, the socket connected and a reply came back. '
            'Calling that unreachable would hide the difference between '
            '"asleep" and "awake but erroring".',
      );
    });

    test('a 4xx also counts as reachable', () async {
      final tracker = newTracker(threshold: 1);

      await reportError(
        tracker,
        failure(DioExceptionType.badResponse, status: 404),
      );

      expect(tracker.isReachable, isTrue);
    });

    test('a connection error counts against it', () async {
      final tracker = newTracker(threshold: 1);

      await reportError(
        tracker,
        failure(DioExceptionType.connectionError),
      );

      expect(tracker.isReachable, isFalse);
    });

    test('timeouts count against it', () async {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      ]) {
        final tracker = newTracker(threshold: 1);

        await reportError(tracker, failure(type));

        expect(tracker.isReachable, isFalse, reason: '$type should count');
      }
    });

    test('an unknown error counts against it', () async {
      final tracker = newTracker(threshold: 1);

      await reportError(tracker, failure(DioExceptionType.unknown));

      expect(tracker.isReachable, isFalse);
    });

    test('the threshold holds across mixed traffic', () async {
      final tracker = newTracker(threshold: 2);

      await reportError(
        tracker,
        failure(DioExceptionType.connectionError),
      );
      expect(tracker.isReachable, isTrue, reason: 'one failure is not enough');

      await reportError(
        tracker,
        failure(DioExceptionType.connectionError),
      );
      expect(tracker.isReachable, isFalse);
    });
  });
}
