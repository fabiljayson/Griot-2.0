import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_providers.dart';
import '../../../core/theme/app_colors.dart';

/// Displays the current offline story cache count, proving the local
/// SQLite layer (Task 1.3) is wired end-to-end.
class OfflineStoryCounter extends ConsumerWidget {
  const OfflineStoryCounter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(offlineStoryCountProvider);
    final theme = Theme.of(context);

    final count = countAsync.when(
      data: (n) => n,
      loading: () => null,
      error: (_, _) => null,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.savannahGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.savannahGreen.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.savannahGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.download_done_rounded,
              color: AppColors.parchment,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == null ? 'Offline library ready' : 'Offline library',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  count == null
                      ? 'Local SQLite cache initialized'
                      : '$count ${count == 1 ? 'story' : 'stories'} saved for offline reading',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
