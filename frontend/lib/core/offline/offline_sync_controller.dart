import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/offline_sync_manager.dart';

/// What happened when the reader asked to sync.
///
/// The outcome is reported rather than swallowed. A reader who taps "Sync
/// now" and sees nothing happen cannot tell a working sync from a failed one,
/// and this app's backend is asleep most of the day — so "nothing happened" is
/// usually an infrastructure fact, not a bug, and it has to be sayable.
enum SyncOutcome {
  /// Nothing was waiting.
  idle,

  /// Queue drained.
  synced,

  /// The device has no network at all.
  noNetwork,

  /// The network is there but the backend is not answering.
  backendUnreachable,

  /// Sync ran and some requests failed permanently.
  failed,
}

/// Result of one sync attempt, including how many writes are still queued.
class SyncResult {
  const SyncResult({required this.outcome, required this.remaining});

  final SyncOutcome outcome;
  final int remaining;
}

/// Drives the offline queue and exposes its progress.
///
/// [OfflineSyncManager.triggerSync] had no caller anywhere in the app: queued
/// writes were enqueued by [OfflineQueueInterceptor] and then drained only by
/// whatever happened to call it, which was nothing. In practice the queue
/// emptied when the app was next launched and the sync manager initialised, so
/// a reader who finished offline saw their progress and likes silently sit
/// unsent for as long as they did not restart the app.
///
/// This makes it callable and observable.
class OfflineSyncController extends StateNotifier<AsyncValue<SyncResult>> {
  OfflineSyncController(this._manager)
    : super(const AsyncValue.data(SyncResult(outcome: SyncOutcome.idle, remaining: 0)));

  final OfflineSyncManager _manager;

  /// Run a sync, guarding against re-entry.
  ///
  /// Re-entrancy matters more than it looks: tapping "Sync now" twice, or a
  /// banner action racing a pull-to-refresh, would otherwise replay the same
  /// queued requests twice. The queue's own retry counts make that survivable
  /// but not free.
  Future<void> syncNow({
    required bool deviceOnline,
    required bool backendReachable,
    required int pendingBefore,
  }) async {
    if (state.isLoading) return;
    if (pendingBefore == 0) {
      state = AsyncValue.data(
        const SyncResult(outcome: SyncOutcome.idle, remaining: 0),
      );
      return;
    }

    state = const AsyncValue.loading();

    // Report the reason up front rather than attempting a doomed request.
    // The manager's own guard is on device connectivity only, so without this
    // the tap would look like it worked while silently doing nothing.
    if (!deviceOnline) {
      state = AsyncValue.data(
        SyncResult(outcome: SyncOutcome.noNetwork, remaining: pendingBefore),
      );
      return;
    }
    if (!backendReachable) {
      state = AsyncValue.data(
        SyncResult(
          outcome: SyncOutcome.backendUnreachable,
          remaining: pendingBefore,
        ),
      );
      return;
    }

    try {
      await _manager.triggerSync();
      state = const AsyncValue.data(
        SyncResult(outcome: SyncOutcome.synced, remaining: 0),
      );
    } catch (_) {
      state = AsyncValue.data(
        SyncResult(outcome: SyncOutcome.failed, remaining: pendingBefore),
      );
    }
  }

  void clear() {
    state = const AsyncValue.data(
      SyncResult(outcome: SyncOutcome.idle, remaining: 0),
    );
  }
}

final offlineSyncControllerProvider =
    StateNotifierProvider<OfflineSyncController, AsyncValue<SyncResult>>((ref) {
      return OfflineSyncController(ref.watch(offlineSyncManagerProvider));
    });