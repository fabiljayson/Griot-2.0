import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../providers/subscription_provider.dart';
import 'paywall_sheet.dart';

/// Wraps a premium surface: shows [child] when the account may use
/// [featureKey], and a locked prompt with a paywall CTA otherwise.
///
/// The gate fails closed. While the status has not loaded (or failed to) the
/// control stays locked rather than flashing an unusable unlock — the backend
/// is the authority and this is a UX guard, not the enforcement point.
class PremiumGate extends ConsumerWidget {
  const PremiumGate({
    super.key,
    required this.featureKey,
    required this.child,
    this.featureLabel,
    this.compact = false,
  });

  /// Premium feature key, matching `settings.PREMIUM_FEATURES` on the backend.
  final String featureKey;

  /// The content an entitled account sees.
  final Widget child;

  /// Reader-facing name for the locked prompt (e.g. "AI video generation").
  final String? featureLabel;

  /// Tighter layout for inline rows (e.g. inside a story action bar).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(subscriptionProvider);
    final status = statusAsync.valueOrNull;
    if (status != null && status.hasAccess(featureKey)) {
      return child;
    }

    if (statusAsync.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return PremiumLockedContent(
      featureKey: featureKey,
      featureLabel: featureLabel ?? featureKey,
      compact: compact,
      onRetry: status == null
          ? () => ref.read(subscriptionProvider.notifier).refresh()
          : null,
    );
  }
}

/// The "this is premium" prompt shown in place of a locked control.
class PremiumLockedContent extends ConsumerWidget {
  const PremiumLockedContent({
    super.key,
    required this.featureKey,
    required this.featureLabel,
    this.compact = false,
    this.onRetry,
  });

  final String featureKey;
  final String featureLabel;
  final bool compact;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 20),
      decoration: BoxDecoration(
        color: AppColors.bronzeTint.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.bronze.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            onRetry == null ? AppIcons.medal : AppIcons.lock_outline,
            color: AppColors.bronzeDark,
            size: compact ? 20 : 26,
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            onRetry == null ? featureLabel : 'Premium status unavailable',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.charcoal,
            ),
          ),
          SizedBox(height: 4),
          Text(
            onRetry == null
                ? 'This is a premium feature. Unlock it to keep exploring '
                      'heritage with fuller tooling.'
                : 'We couldn\'t confirm your premium status. '
                      'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.charcoalMuted,
            ),
          ),
          SizedBox(height: compact ? 10 : 16),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: () => PaywallSheet.show(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: AppColors.charcoal,
                ),
                icon: const Icon(AppIcons.medal, size: 18),
                label: Text('Unlock $featureLabel'),
              ),
            ),
        ],
      ),
    );
  }
}