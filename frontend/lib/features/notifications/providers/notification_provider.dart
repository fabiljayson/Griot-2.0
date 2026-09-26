import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/notification_model.dart';
import '../services/notification_api_service.dart';

/// Inbox service bound to the authenticated client.
///
/// The inbox is per-reader, so this must never fall back to the unauthenticated
/// client: every route would answer 401 and the bell would read as permanently
/// empty.
final notificationApiServiceProvider = Provider<NotificationApiService>((ref) {
  final apiClient = ref.watch(authenticatedApiClientProvider);
  return NotificationApiService(dio: apiClient.dio);
});

/// The reader's inbox, shared by the bell badge and the inbox screen.
///
/// One notifier rather than a screen-local list plus a separate count provider:
/// the badge has to fall the instant a message is opened, and two sources of
/// truth for "how many unread" is how a badge drifts out of sync with the list.
final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, NotificationInbox>(
      NotificationsNotifier.new,
    );

/// Badge count for the bell, readable without loading the whole inbox.
final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).value?.unreadCount ?? 0;
});

class NotificationsNotifier extends AsyncNotifier<NotificationInbox> {
  NotificationApiService get _service => ref.read(notificationApiServiceProvider);

  @override
  Future<NotificationInbox> build() => _service.fetchInbox();

  /// Re-read the inbox. Safe to call on pull-to-refresh.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_service.fetchInbox);
  }

  /// Open one message.
  ///
  /// Applied locally first and rolled back if the server refuses, so the badge
  /// responds to the tap instead of waiting on the network. The inbox is a log
  /// the server owns, so a failure has to leave the row unread rather than
  /// pretend it was read.
  Future<void> markRead(int id) async {
    final current = state.value;
    if (current == null) return;

    final target = current.notifications.where((n) => n.id == id).firstOrNull;
    if (target == null || target.isRead) return;

    state = AsyncData(_withRead(current, id, isRead: true));
    try {
      await _service.markRead(id);
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }

  /// Clear the badge. Same optimistic-then-rollback shape as [markRead].
  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;

    state = AsyncData(
      NotificationInbox(
        notifications: current.notifications
            .map((n) => n.copyWith(isRead: true))
            .toList(),
        unreadCount: 0,
        hasMore: current.hasMore,
      ),
    );
    try {
      final remaining = await _service.markAllRead();
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(
          NotificationInbox(
            notifications: latest.notifications,
            unreadCount: remaining,
            hasMore: latest.hasMore,
          ),
        );
      }
    } catch (_) {
      state = AsyncData(current);
      rethrow;
    }
  }

  /// Recompute the badge from the rows, so it cannot drift from the list.
  NotificationInbox _withRead(
    NotificationInbox inbox,
    int id, {
    required bool isRead,
  }) {
    var changed = false;
    final rows = inbox.notifications.map((n) {
      if (n.id != id || n.isRead == isRead) return n;
      changed = true;
      return n.copyWith(isRead: isRead);
    }).toList();
    if (!changed) return inbox;
    return NotificationInbox(
      notifications: rows,
      unreadCount: inbox.unreadCount > 0 ? inbox.unreadCount - 1 : 0,
      hasMore: inbox.hasMore,
    );
  }
}

/// Convenience view for tests and for widgets that only need the rows.
extension NotificationInboxX on NotificationInbox {
  List<NotificationModel> get unread =>
      notifications.where((n) => !n.isRead).toList();
}
