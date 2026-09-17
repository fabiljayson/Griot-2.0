import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/repositories/offline_request_repository.dart';

/// Service that monitors network connectivity and manages offline/online transitions.
///
/// When the device goes offline, pending requests are queued.
/// When connectivity is restored, queued requests are replayed.
class ConnectivityService {
  ConnectivityService._({
    required Connectivity connectivity,
    required OfflineRequestRepository offlineRepository,
  })  : _connectivity = connectivity,
        _offlineRepository = offlineRepository;

  final Connectivity _connectivity;
  final OfflineRequestRepository _offlineRepository;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _connectivityController = StreamController<bool>.broadcast();

  /// Stream of connectivity status changes (true = online, false = offline).
  Stream<bool> get connectivityStream => _connectivityController.stream;

  /// Current connectivity status.
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// Initialize the connectivity monitoring.
  void initialize() {
    // Check initial status
    _checkConnectivity();

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);

      debugPrint('[Connectivity] Status changed: ${_isOnline ? "online" : "offline"}');

      // If we just came back online, sync pending requests
      if (_isOnline && !wasOnline) {
        _syncPendingRequests();
      }

      _connectivityController.add(_isOnline);
    });
  }

  /// Check current connectivity status.
  Future<void> _checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);
    _connectivityController.add(_isOnline);
  }

  /// Sync pending requests when coming back online.
  Future<void> _syncPendingRequests() async {
    debugPrint('[Connectivity] Syncing pending requests...');
    // The sync will be handled by the OfflineSyncManager
  }

  /// Dispose resources.
  void dispose() {
    _subscription?.cancel();
    _connectivityController.close();
  }
}

/// Provider for the connectivity service.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService._(
    connectivity: Connectivity(),
    offlineRepository: OfflineRequestRepository(),
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for current online status.
final isOnlineProvider = StreamProvider<bool>((ref) {
  final connectivityService = ref.watch(connectivityServiceProvider);
  return connectivityService.connectivityStream;
});

/// Provider for checking if currently online.
final isCurrentlyOnlineProvider = Provider<bool>((ref) {
  final connectivityService = ref.watch(connectivityServiceProvider);
  return connectivityService.isOnline;
});
