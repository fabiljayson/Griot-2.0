import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/network/offline_sync_manager.dart';
import 'package:griot_ai/core/offline/offline_sync_controller.dart';

/// `triggerSync()` had no caller anywhere in the app. Queued writes were
/// enqueued by the offline interceptor and drained only when the app was next
/// launched, so a reader who finished offline watched their progress and likes
/// sit unsent for as long as they did not restart.
///
/// These tests pin the four behaviours that make the affordance trustworthy —
/// and the fourth is the one a "just add a button" change would have missed:
/// the manager's own guard is on *device* connectivity, so a tap made while
/// the Render backend is asleep would silently do nothing while the UI implied
/// it had worked.
void main() {
  late FakeSyncManager manager;
  late OfflineSyncController controller;

  setUp(() {
    manager = FakeSyncManager();
    controller = OfflineSyncController(manager);
  });

  group('when there is nothing queued', () {
    test('reports idle and never touches the manager', () async {
      await controller.syncNow(
        deviceOnline: true,
        backendReachable: true,
        pendingBefore: 0,
      );

      expect(controller.state.value!.outcome, SyncOutcome.idle);
      expect(manager.calls, 0, reason: 'no work means no request');
    });

    test('does not run while offline either', () async {
      // Guards the cheap path against ordering mistakes in the UI.
      await controller.syncNow(
        deviceOnline: false,
        backendReachable: false,
        pendingBefore: 0,
      );

      expect(controller.state.value!.outcome, SyncOutcome.idle);
      expect(manager.calls, 0);
    });
  });

  group('when the sync cannot run', () {
    test('says so when the device has no network', () async {
      await controller.syncNow(
        deviceOnline: false,
        backendReachable: true,
        pendingBefore: 3,
      );

      expect(controller.state.value!.outcome, SyncOutcome.noNetwork);
      expect(controller.state.value!.remaining, 3);
      expect(manager.calls, 0);
    });

    test('says so when the backend is asleep', () async {
      // The deployment's normal state. A tap here must not look successful.
      await controller.syncNow(
        deviceOnline: true,
        backendReachable: false,
        pendingBefore: 2,
      );

      expect(
        controller.state.value!.outcome,
        SyncOutcome.backendUnreachable,
      );
      expect(controller.state.value!.remaining, 2);
      expect(manager.calls, 0);
    });
  });

  group('when the sync runs', () {
    test('drains the queue', () async {
      await controller.syncNow(
        deviceOnline: true,
        backendReachable: true,
        pendingBefore: 3,
      );

      expect(manager.calls, 1);
      expect(controller.state.value!.outcome, SyncOutcome.synced);
      expect(controller.state.value!.remaining, 0);
    });

    test('reports a failure rather than swallowing it', () async {
      manager.throwOnSync = true;

      await controller.syncNow(
        deviceOnline: true,
        backendReachable: true,
        pendingBefore: 1,
      );

      expect(
        controller.state.value!.outcome,
        SyncOutcome.failed,
        reason: 'a reader who tapped "Sync now" deserves to know',
      );
      expect(controller.state.value!.remaining, 1);
    });

    test('re-entrant calls do not replay the queue', () async {
      // The queue is replayed from disk, so a second concurrent sync would
      // re-send the same writes. Cheap to guard, expensive to debug.
      final first = controller.syncNow(
        deviceOnline: true,
        backendReachable: true,
        pendingBefore: 2,
      );
      final second = controller.syncNow(
        deviceOnline: true,
        backendReachable: true,
        pendingBefore: 2,
      );

      await Future.wait([first, second]);

      expect(manager.calls, 1, reason: 'the queue must not be replayed');
    });
  });

  group('clear', () {
    test('resets to idle', () async {
      await controller.syncNow(
        deviceOnline: false,
        backendReachable: false,
        pendingBefore: 4,
      );
      expect(controller.state.value!.outcome, SyncOutcome.noNetwork);

      controller.clear();

      expect(controller.state.value!.outcome, SyncOutcome.idle);
      expect(controller.state.value!.remaining, 0);
    });
  });
}

/// Stands in for the manager so the controller can be driven without a
/// database, a network, or dio.
class FakeSyncManager implements OfflineSyncManager {
  int calls = 0;
  bool throwOnSync = false;

  @override
  Future<void> triggerSync() async {
    calls++;
    if (throwOnSync) throw StateError('boom');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}