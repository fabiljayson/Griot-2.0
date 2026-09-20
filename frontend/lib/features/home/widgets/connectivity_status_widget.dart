import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';

/// Widget that displays the current connectivity status and pending sync count.
class ConnectivityStatusWidget extends ConsumerWidget {
  const ConnectivityStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connectivityAsync = ref.watch(isOnlineProvider);
    final pendingCountAsync = ref.watch(pendingOfflineRequestsProvider);

    return connectivityAsync.when(
      data: (isOnline) {
        return pendingCountAsync.when(
          data: (pendingCount) {
            return _buildStatusCard(
              context,
              theme,
              isOnline: isOnline,
              pendingCount: pendingCount,
            );
          },
          loading: () => _buildStatusCard(
            context,
            theme,
            isOnline: isOnline,
            pendingCount: 0,
          ),
          error: (_, _) => _buildStatusCard(
            context,
            theme,
            isOnline: isOnline,
            pendingCount: 0,
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    ThemeData theme, {
    required bool isOnline,
    required int pendingCount,
  }) {
    // Don't show anything if online with no pending requests
    if (isOnline && pendingCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isOnline
            ? AppColors.savannahGreen.withValues(alpha: 0.1)
            : AppColors.terracotta.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOnline
              ? AppColors.savannahGreen.withValues(alpha: 0.3)
              : AppColors.terracotta.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          FaIcon(
            isOnline ? AppIcons.wifi : AppIcons.wifi_off,
            size: 16,
            color: isOnline ? AppColors.savannahGreen : AppColors.terracotta,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isOnline
                  ? (pendingCount > 0
                        ? 'Syncing $pendingCount ${pendingCount == 1 ? "change" : "changes"}...'
                        : 'Online')
                  : 'Offline — Changes will sync later',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isOnline
                    ? AppColors.savannahGreen
                    : AppColors.terracotta,
              ),
              softWrap: true,
            ),
          ),
          if (pendingCount > 0) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isOnline ? AppColors.savannahGreen : AppColors.terracotta,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
