import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers/settings_providers.dart';
import '../../../core/theme/app_colors.dart';

/// Branded landing header: wordmark, tagline, and theme toggle.
class LandingHeader extends ConsumerWidget {
  const LandingHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            AppColors.terracottaDark,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.parchment.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.ochre.withValues(alpha: 0.7),
                width: 1.2,
              ),
            ),
            child: Text(
              '🪘',
              style: TextStyle(
                fontSize: 22,
                color: AppColors.ochre,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AFRICAN TELLER',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.parchment,
                    letterSpacing: 1.4,
                  ),
                ),
                Text(
                  AppConstants.appTagline,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.ochreTint,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Toggle theme',
            onPressed: () => ref
                .read(settingsProvider.notifier)
                .toggleDarkMode(
                  systemBrightness: MediaQuery.of(context).platformBrightness,
                ),
            icon: const Icon(Icons.dark_mode_outlined),
            color: AppColors.parchment,
          ),
        ],
      ),
    );
  }

}
