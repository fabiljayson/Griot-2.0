import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/connectivity_service.dart';
import '../network/offline_sync_manager.dart';
import '../providers/database_providers.dart';

/// Widget that wraps the app to provide offline functionality.
///
/// Initializes connectivity monitoring and offline sync manager.
class OfflineProvider extends ConsumerStatefulWidget {
  const OfflineProvider({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OfflineProvider> createState() => _OfflineProviderState();
}

class _OfflineProviderState extends ConsumerState<OfflineProvider> {
  @override
  void initState() {
    super.initState();

    // Initialize connectivity service
    final connectivityService = ref.read(connectivityServiceProvider);
    connectivityService.initialize();

    // Initialize offline sync manager
    final syncManager = ref.read(offlineSyncManagerProvider);
    syncManager.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Extension to easily add offline support to any provider.
extension OfflineSupport on Ref {
  /// Get the current connectivity status.
  bool get isOnline => read(isCurrentlyOnlineProvider);

  /// Queue a request for offline execution.
  Future<void> queueOfflineRequest({
    required String method,
    required String path,
    dynamic body,
    Map<String, dynamic>? headers,
  }) async {
    final apiClient = read(apiClientProvider);
    await apiClient.queueOfflineRequest(
      method: method,
      path: path,
      body: body,
      headers: headers,
    );
  }

  /// Trigger manual sync of pending offline requests.
  Future<void> triggerOfflineSync() async {
    final syncManager = read(offlineSyncManagerProvider);
    await syncManager.triggerSync();
  }
}
