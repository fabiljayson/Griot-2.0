import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/models/offline_request.dart';
import '../database/models/offline_user.dart';
import '../database/repositories/offline_request_repository.dart';
import '../database/repositories/offline_user_repository.dart';
import '../providers/database_providers.dart';
import '../../features/auth/providers/auth_provider.dart';
import 'api_client.dart';
import 'connectivity_service.dart';
import '../debug/debug_log.dart';

/// Manages syncing of queued offline requests when connectivity is restored.
///
/// When the device comes back online, this manager:
/// 1. Retrieves all pending requests from the offline queue
/// 2. Replays them in order
/// 3. Marks them as completed or failed based on the response
/// 4. Handles retry logic for failed requests
class OfflineSyncManager {
  OfflineSyncManager._({
    required OfflineRequestRepository offlineRepository,
    required OfflineUserRepository offlineUserRepository,
    required ApiClient apiClient,
    required ConnectivityService connectivityService,
  }) : _offlineRepository = offlineRepository,
       _offlineUserRepository = offlineUserRepository,
       _apiClient = apiClient,
       _connectivityService = connectivityService;

  final OfflineRequestRepository _offlineRepository;
  final OfflineUserRepository _offlineUserRepository;
  final ApiClient _apiClient;
  final ConnectivityService _connectivityService;

  StreamSubscription<bool>? _connectivitySubscription;
  bool _isSyncing = false;

  /// Initialize the sync manager and start listening for connectivity changes.
  void initialize() {
    _connectivitySubscription = _connectivityService.connectivityStream.listen((
      isOnline,
    ) {
      if (isOnline && !_isSyncing) {
        _syncPendingRequests();
      }
    });

    // Also try to sync on initialization if already online
    if (_connectivityService.isOnline) {
      _syncPendingRequests();
    }
  }

  /// Sync all pending requests and user registrations.
  Future<void> _syncPendingRequests() async {
    if (_isSyncing) return;

    _isSyncing = true;
    debugLog('[OfflineSync] Starting sync...');

    try {
      // Sync pending API requests
      final pendingRequests = await _offlineRepository.getPendingRequests();
      debugLog(
        '[OfflineSync] Found ${pendingRequests.length} pending requests',
      );

      for (final request in pendingRequests) {
        // Failed requests are re-queried by getPendingRequests() and retried
        // here until they hit maxRetries (see OfflineRequest.canRetry).
        if (!request.isCompleted && request.canRetry) {
          await _executeRequest(request);
        }
      }

      // Sync pending user registrations
      final pendingUsers = await _offlineUserRepository.getPendingUsers();
      debugLog(
        '[OfflineSync] Found ${pendingUsers.length} pending user registrations',
      );

      for (final user in pendingUsers) {
        await _syncUserRegistration(user);
      }
    } catch (e) {
      debugLog('[OfflineSync] Error during sync: $e');
    } finally {
      _isSyncing = false;
      debugLog('[OfflineSync] Sync completed');
    }
  }

  /// Sync a single user registration.
  Future<void> _syncUserRegistration(OfflineUser offlineUser) async {
    debugLog('[OfflineSync] Syncing user: ${offlineUser.username}');

    await _offlineUserRepository.markSyncing(offlineUser.id!);

    // The password is not on the row; it is read back from secure storage. A
    // null here means the secret is gone (pre-v8 registration, or cleared
    // secure storage), so the registration cannot be replayed — fail it with a
    // reason the reader can act on rather than POSTing an empty password.
    final pendingPassword = await _offlineUserRepository
        .readPendingPassword(offlineUser.id!);
    if (pendingPassword == null) {
      await _offlineUserRepository.markFailed(
        offlineUser.id!,
        'Queued registration is missing its password; please register again',
      );
      return;
    }

    try {
      final response = await _apiClient.dio.post(
        '/api/auth/register/',
        data: {
          'username': offlineUser.username,
          'email': offlineUser.email,
          'password': pendingPassword,
          'first_name': offlineUser.firstName,
          'last_name': offlineUser.lastName,
          'role': offlineUser.role,
        },
      );

      final userData = response.data as Map<String, dynamic>;
      final serverUserId = userData['user']?['id'] as int? ?? 0;

      await _offlineUserRepository.markSynced(offlineUser.id!, serverUserId);
      debugLog(
        '[OfflineSync] User synced: ${offlineUser.username} (ID: $serverUserId)',
      );
    } on DioException catch (e) {
      final errorMessage =
          e.response?.data?['detail'] as String? ?? e.message ?? 'Sync failed';
      await _offlineUserRepository.markFailed(offlineUser.id!, errorMessage);
      debugLog('[OfflineSync] Failed to sync user: $errorMessage');
    } catch (e) {
      await _offlineUserRepository.markFailed(offlineUser.id!, e.toString());
      debugLog('[OfflineSync] Error syncing user: $e');
    }
  }

  /// Execute a single queued request with retry backoff.
  Future<void> _executeRequest(OfflineRequest request) async {
    debugLog('[OfflineSync] Executing: ${request.method} ${request.path}');

    await _offlineRepository.markInProgress(request.id!);

    try {
      // Apply exponential backoff for retries
      if (request.retryCount > 0) {
        final delay = Duration(seconds: request.retryCount * 2);
        debugLog('[OfflineSync] Retry delay: ${delay.inSeconds}s');
        await Future.delayed(delay);
      }

      final options = RequestOptions(
        // Replay must keep the client's baseUrl: a RequestOptions built with
        // only a path resolves to a relative URI, which never leaves the
        // device — every queued mutation would "succeed" locally and vanish.
        baseUrl: _apiClient.dio.options.baseUrl,
        method: request.method,
        path: request.path,
        data: request.body != null ? jsonDecode(request.body!) : null,
        headers: request.headers != null
            ? Map<String, String>.from(jsonDecode(request.headers!))
            : null,
      );

      final response = await _apiClient.dio.fetch(options);

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        await _offlineRepository.markCompleted(request.id!);
        debugLog('[OfflineSync] Success: ${request.method} ${request.path}');
      } else {
        throw DioException(
          requestOptions: options,
          response: response,
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      debugLog(
        '[OfflineSync] Failed: ${request.method} ${request.path} - ${e.message}',
      );
      await _offlineRepository.markFailed(
        request.id!,
        e.message ?? 'Unknown error',
      );
    } catch (e) {
      debugLog('[OfflineSync] Error: ${request.method} ${request.path} - $e');
      await _offlineRepository.markFailed(request.id!, e.toString());
    }
  }

  /// Manually trigger a sync.
  Future<void> triggerSync() async {
    if (_connectivityService.isOnline) {
      await _syncPendingRequests();
    }
  }

  /// Dispose resources.
  void dispose() {
    _connectivitySubscription?.cancel();
  }
}

/// Provider for the offline sync manager.
final offlineSyncManagerProvider = Provider<OfflineSyncManager>((ref) {
  final manager = OfflineSyncManager._(
    offlineRepository: ref.watch(offlineRequestRepositoryProvider),
    offlineUserRepository: ref.watch(offlineUserRepositoryProvider),
    // Replay must go through the authenticated client: queued requests are
    // stored without their `Authorization` header (credentials are never
    // persisted), and the replay relies on `AuthInterceptor.onRequest` to
    // re-attach a live token. The bare `ApiClient.instance` has no
    // interceptor, so every replay used to ship anonymous and fail forever.
    apiClient: ref.watch(authenticatedApiClientProvider),
    connectivityService: ref.watch(connectivityServiceProvider),
  );
  ref.onDispose(() => manager.dispose());
  return manager;
});
