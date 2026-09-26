import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/notification_model.dart';

/// API client for the reader's notification inbox.
///
/// Construct this with the authenticated Dio: the inbox is per-user, so every
/// route here requires a signed-in reader and returns 401 without a token.
class NotificationApiService {
  NotificationApiService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static const _path = '/api/notifications';

  /// The inbox, newest first, with the unread count the bell badge shows.
  ///
  /// Both come back from one call on purpose: the badge is rendered on the home
  /// header and the list underneath it, and splitting them would mean two
  /// round trips to render one screen.
  Future<NotificationInbox> fetchInbox({int? page}) async {
    final response = await _dio.get(
      '$_path/',
      queryParameters: page == null ? null : {'page': page},
    );
    final data = response.data as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>?) ?? const [];
    return NotificationInbox(
      notifications: results
          .map((json) => NotificationModel.fromJson(json as Map<String, dynamic>))
          .toList(),
      unreadCount: data['unread_count'] as int? ?? 0,
      hasMore: data['next'] != null,
    );
  }

  /// Just the badge count, for a cheap poll.
  Future<int> fetchUnreadCount() async {
    final response = await _dio.get('$_path/unread-count/');
    final data = response.data as Map<String, dynamic>;
    return data['unread_count'] as int? ?? 0;
  }

  /// Mark one message read. Idempotent server-side.
  Future<void> markRead(int id) async {
    await _dio.post('$_path/$id/mark-read/');
  }

  /// Clear the whole badge. Returns the new unread count.
  Future<int> markAllRead() async {
    final response = await _dio.post('$_path/mark-all-read/');
    final data = response.data as Map<String, dynamic>;
    return data['unread_count'] as int? ?? 0;
  }
}

/// One page of the inbox plus the badge state.
class NotificationInbox {
  const NotificationInbox({
    required this.notifications,
    required this.unreadCount,
    this.hasMore = false,
  });

  const NotificationInbox.empty()
    : notifications = const [],
      unreadCount = 0,
      hasMore = false;

  final List<NotificationModel> notifications;
  final int unreadCount;
  final bool hasMore;
}
