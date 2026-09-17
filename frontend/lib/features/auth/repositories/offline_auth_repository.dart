import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/models/offline_user.dart';
import '../../../core/database/repositories/offline_user_repository.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/providers/database_providers.dart';
import '../models/user_model.dart';

/// Repository for handling offline user registration and syncing.
///
/// When the device is offline, registrations are stored locally and
/// synced to the server when connectivity is restored.
class OfflineAuthRepository {
  OfflineAuthRepository({
    required OfflineUserRepository offlineUserRepository,
    required ApiClient apiClient,
    required ConnectivityService connectivityService,
  })  : _offlineUserRepository = offlineUserRepository,
        _apiClient = apiClient,
        _connectivityService = connectivityService;

  final OfflineUserRepository _offlineUserRepository;
  final ApiClient _apiClient;
  final ConnectivityService _connectivityService;

  /// Register a new user, either online or offline.
  ///
  /// If online, the registration is sent to the server immediately.
  /// If offline, the registration is stored locally and synced later.
  Future<OfflineUser> register({
    required String username,
    required String email,
    required String password,
    String firstName = '',
    String lastName = '',
    String role = 'visitor',
    String institution = '',
  }) async {
    // Check if username or email is already registered offline
    if (await _offlineUserRepository.isUsernameRegistered(username)) {
      throw Exception('Username is already registered offline');
    }
    if (await _offlineUserRepository.isEmailRegistered(email)) {
      throw Exception('Email is already registered offline');
    }

    // Save the user locally first
    final offlineUser = await _offlineUserRepository.saveUser(
      username: username,
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      role: role,
      institution: institution,
    );

    debugPrint('[OfflineAuth] User saved locally: ${offlineUser.username}');

    // Try to sync immediately if online
    if (_connectivityService.isOnline) {
      try {
        await _syncUser(offlineUser);
        debugPrint('[OfflineAuth] User synced immediately: ${offlineUser.username}');
      } catch (e) {
        debugPrint('[OfflineAuth] Failed to sync immediately, will retry later: $e');
      }
    }

    return offlineUser;
  }

  /// Sync a single user to the server.
  Future<void> _syncUser(OfflineUser offlineUser) async {
    await _offlineUserRepository.markSyncing(offlineUser.id!);

    try {
      final response = await _apiClient.dio.post(
        '/api/auth/register/',
        data: {
          'username': offlineUser.username,
          'email': offlineUser.email,
          'password': offlineUser.password,
          'first_name': offlineUser.firstName,
          'last_name': offlineUser.lastName,
          'role': offlineUser.role,
        },
      );

      final userData = response.data as Map<String, dynamic>;
      final serverUserId = userData['user']?['id'] as int? ?? 0;

      await _offlineUserRepository.markSynced(offlineUser.id!, serverUserId);
      debugPrint('[OfflineAuth] User synced to server: ${offlineUser.username} (ID: $serverUserId)');
    } on DioException catch (e) {
      final errorMessage = e.response?.data?['detail'] as String? ?? e.message ?? 'Sync failed';
      await _offlineUserRepository.markFailed(offlineUser.id!, errorMessage);
      debugPrint('[OfflineAuth] Failed to sync user: $errorMessage');
      rethrow;
    }
  }

  /// Sync all pending user registrations.
  Future<void> syncPendingUsers() async {
    if (!_connectivityService.isOnline) return;

    final pendingUsers = await _offlineUserRepository.getPendingUsers();
    debugPrint('[OfflineAuth] Syncing ${pendingUsers.length} pending users...');

    for (final user in pendingUsers) {
      try {
        await _syncUser(user);
      } catch (e) {
        debugPrint('[OfflineAuth] Failed to sync user ${user.username}: $e');
      }
    }
  }

  /// Get all offline users.
  Future<List<OfflineUser>> getAllOfflineUsers() async {
    return _offlineUserRepository.getPendingUsers();
  }

  /// Get a user by username.
  Future<OfflineUser?> getOfflineUser(String username) async {
    return _offlineUserRepository.getUserByUsername(username);
  }
}

/// Provider for the offline auth repository.
final offlineAuthProvider = Provider<OfflineAuthRepository>((ref) {
  return OfflineAuthRepository(
    offlineUserRepository: ref.watch(offlineUserRepositoryProvider),
    apiClient: ref.watch(apiClientProvider),
    connectivityService: ref.watch(connectivityServiceProvider),
  );
});
