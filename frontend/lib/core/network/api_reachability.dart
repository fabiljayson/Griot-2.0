import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether the *backend* is answering — which is not the same question
/// as whether the device has a network.
///
/// That distinction is the whole point of this class. The backend runs on
/// Render's free tier and sleeps after ~15 minutes of inactivity; a wake-up
/// costs 44.8s (see `.github/workflows/keep-render-awake.yml`, which exists
/// only to stop clients hitting a cold instance). A phone on a healthy Wi-Fi
/// network therefore reports "online" from `connectivity_plus` while every
/// single API call is timing out. Building the offline UI on connectivity
/// alone would show a green "online" banner through exactly the failure it is
/// supposed to be reporting.
///
/// So reachability is observed from responses themselves: any HTTP reply at all
/// means the server is up (a 500 still proves the round trip), and only
/// transport-level failures — timeouts, connection refused, DNS — count
/// against it.
///
/// ## Hysteresis
///
/// One failed request is not an outage. Without a threshold, every dropped
/// packet on a train flips the banner and then flips it back, which reads as a
/// glitchy app and trains the user to ignore it. Reachability only goes false
/// after [_failureThreshold] *consecutive* transport failures, and any single
/// successful response restores it immediately — recovery should be
/// unnoticeable, degradation should be certain.
class ApiReachability extends ChangeNotifier {
  ApiReachability({this.failureThreshold = 2});

  /// Consecutive transport failures required before reporting unreachable.
  final int failureThreshold;

  final ValueNotifier<bool> _reachable = ValueNotifier<bool>(true);
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  int _consecutiveFailures = 0;

  /// Whether the backend answered recently. Starts `true` so a cold start is
  /// not announced as an outage before the first request has been made.
  ///
  /// A [ValueListenable] rather than a plain bool so widgets can `select` on it
  /// and rebuild only when the answer actually changes.
  ValueListenable<bool> get reachable => _reachable;

  /// Reachability transitions, for `StreamProvider` consumers.
  ///
  /// Emits the current value immediately on subscribe so a listener joining
  /// late (navigating to a screen after a failure) is not left with no state
  /// until the next transition.
  Stream<bool> get changes async* {
    yield _reachable.value;
    yield* _changes.stream;
  }

  bool get isReachable => _reachable.value;

  /// Consecutive transport failures seen since the last success.
  int get consecutiveFailures => _consecutiveFailures;

  /// Record a response that reached the server.
  ///
  /// Any status code counts, including 4xx and 5xx: getting a 503 back means
  /// DNS resolved, the socket connected and the server replied, which is
  /// precisely the fact being tracked. Treating a 503 as "unreachable" would
  /// hide the difference between "the server is asleep" and "the server is
  /// awake and unhappy", and those need different user-facing messages.
  void markReachable() {
    final wasUnreachable = !_reachable.value;
    _consecutiveFailures = 0;
    if (wasUnreachable) {
      _reachable.value = true;
      notifyListeners();
      _emit();
    }
  }

  /// Record a transport-level failure.
  void markUnreachable() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= failureThreshold && _reachable.value) {
      _reachable.value = false;
      notifyListeners();
      _emit();
    }
  }

  /// Reset to the initial state. For tests and for logout, where the next
  /// session should not inherit the previous one's reachability verdict.
  void reset() {
    _consecutiveFailures = 0;
    if (!_reachable.value) {
      _reachable.value = true;
      notifyListeners();
      _changes.add(true);
    }
  }

  @override
  void dispose() {
    _reachable.dispose();
    _changes.close();
    super.dispose();
  }

  /// Publish a transition to [changes]. Called only where the value flips.
  void _emit() {
    _changes.add(_reachable.value);
  }
}

/// Shared tracker instance. A single source of truth for the whole app, like
/// `ApiClient.instance`.
final apiReachabilityProvider = Provider<ApiReachability>((ref) {
  final tracker = ApiReachability();
  ref.onDispose(tracker.dispose);
  return tracker;
});

/// Reactive view of backend reachability.
final isApiReachableProvider = StreamProvider<bool>((ref) {
  final tracker = ref.watch(apiReachabilityProvider);
  return tracker.changes;
});

/// Dio interceptor that feeds [ApiReachability] from real traffic.
///
/// Registered on the app's client rather than wired by hand at each call site:
/// reachability is a property of the transport, and the only trustworthy
/// signal is one observed by the transport itself.
class ApiReachabilityInterceptor extends Interceptor {
  ApiReachabilityInterceptor(this.tracker);

  final ApiReachability tracker;

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    tracker.markReachable();
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Only transport failures count. A 4xx/5xx is a completed round trip and
    // is handled by `onResponse`; `badResponse` reaching `onError` means the
    // server did reply, just unkindly.
    if (err.type != DioExceptionType.badResponse) {
      tracker.markUnreachable();
    } else {
      tracker.markReachable();
    }
    handler.next(err);
  }
}