import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_reachability.dart';
import '../network/connectivity_service.dart';
import '../providers/database_providers.dart';
import '../theme/app_icons.dart';
import 'offline_sync_controller.dart';

/// How many writes are waiting to sync.
///
/// `database_providers` already owns both halves of that count, so this sums
/// them rather than introducing a third definition: a queued registration is
/// just as unsent as a queued like, and a reader who has done both offline
/// should see one honest number.
///
/// It re-reads whenever connectivity or reachability changes, which is the only
/// moment the queue can drain — the sync itself is invisible to the reader.
final pendingSyncCountProvider = Provider<int>((ref) {
  // Watch both so the count refreshes on a transition.
  ref.watch(isOnlineProvider);
  ref.watch(isApiReachableProvider);

  final requests = ref.watch(pendingOfflineRequestsProvider).valueOrNull ?? 0;
  final registrations =
      ref.watch(pendingOfflineUsersProvider).valueOrNull ?? 0;
  return requests + registrations;
});

/// The reader-facing state of the connection, and the only honest answer to
/// "why is nothing loading?".
///
/// Three states, because they need different words:
///
///   * **No network** — the device is offline. Saved stories still work.
///   * **Backend unreachable** — the device has a network but the server is not
///     answering. This is the normal state of a Render free-tier deployment
///     most of the day, and it is the case connectivity alone would report as
///     "online" while every request timed out.
///   * **Connected, with a queue** — everything works, but some writes are
///     waiting. Worth showing so a reader knows a like or a progress update
///     has not been lost.
sealed class ConnectionState {
  const ConnectionState();
}

class ConnectionOffline extends ConnectionState {
  const ConnectionOffline();
}

class ConnectionBackendAsleep extends ConnectionState {
  const ConnectionBackendAsleep();
}

class ConnectionOnline extends ConnectionState {
  const ConnectionOnline(this.pending);
  final int pending;
}

/// Combine both signals into one state.
final connectionStateProvider = Provider<ConnectionState>((ref) {
  final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;
  final reachable = ref.watch(isApiReachableProvider).valueOrNull ?? true;
  final pending = ref.watch(pendingSyncCountProvider);

  if (!isOnline) return const ConnectionOffline();
  if (!reachable) return const ConnectionBackendAsleep();
  return ConnectionOnline(pending);
});

/// A quiet, persistent banner for the states a reader should know about.
///
/// Deliberately not a red error. The backend being asleep is the deployment's
/// normal condition, not a fault the reader caused or can fix, and an
/// alarming treatment would make the app feel broken most of the day. This
/// reads as information: here is what is happening, here is what still works.
class OfflineStatusBanner extends ConsumerWidget {
  const OfflineStatusBanner({super.key});

  /// Whether to render anything at all. Exposed for tests.
  static bool isVisible(ConnectionState state) =>
      state is ConnectionOffline ||
      state is ConnectionBackendAsleep ||
      (state is ConnectionOnline && state.pending > 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionStateProvider);
    if (!isVisible(state)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, message) = _describe(state);

    return Semantics(
      // Announced when it appears, and it is genuinely worth announcing: it
      // explains why content is stale.
      liveRegion: true,
      label: message,
      child: Container(
        width: double.infinity,
        color: scheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
            if (state is ConnectionOnline) _SyncAction(state: state),
          ],
        ),
      ),
    );
  }

  static (IconData, String) _describe(ConnectionState state) {
    return switch (state) {
      ConnectionOffline() => (
        AppIcons.wifi_off,
        'You are offline. Saved stories still work.',
      ),
      ConnectionBackendAsleep() => (
        AppIcons.schedule,
        'Cannot reach Griot right now. We will sync when it is back.',
      ),
      ConnectionOnline(:final pending) => (
        AppIcons.cloud_sync_rounded,
        pending == 1
            ? '1 update waiting to sync.'
            : '$pending updates waiting to sync.',
      ),
    };
  }
}

/// "Sync now" for the queued-writes state.
///
/// Only offered when the queue is draining in earnest — a button that always
/// says "Sync now" and mostly cannot sync is worse than none, because it
/// teaches the reader that the app's controls are decorative.
class _SyncAction extends ConsumerWidget {
  const _SyncAction({required this.state});

  final ConnectionOnline state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sync = ref.watch(offlineSyncControllerProvider);
    final busy = sync.isLoading;

    return TextButton(
      onPressed: busy
          ? null
          : () async {
              await ref
                  .read(offlineSyncControllerProvider.notifier)
                  .syncNow(
                    deviceOnline:
                        ref.read(isCurrentlyOnlineProvider),
                    backendReachable:
                        ref.read(apiReachabilityProvider).isReachable,
                    pendingBefore: state.pending,
                  );
            },
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              'Sync now',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
