import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../models/subscription_status.dart';
import '../providers/subscription_provider.dart';
import '../services/purchase_outcome.dart';

/// Bottom-sheet paywall for premium access.
///
/// Renders the account's current entitlement plus the list of premium
/// features, and drives the store flow through [purchaseServiceProvider].
/// After a successful purchase it refreshes [subscriptionProvider], so every
/// [PremiumGate] on screen flips to unlocked in place.
class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PaywallSheet(),
    );
  }

  @override
  ConsumerState<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<PaywallSheet> {
  bool _busy = false;

  Future<void> _identifyForStore() async {
    final service = ref.read(purchaseServiceProvider);
    if (!service.isConfigured) return;
    final appUserId = ref.read(revenueCatAppUserIdProvider);
    if (appUserId != null) {
      await service.identify(appUserId);
    }
  }

  Future<void> _run(Future<PurchaseOutcome> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _identifyForStore();
      final outcome = await action();
      if (!mounted) return;

      if (outcome.success) {
        await ref.read(subscriptionProvider.notifier).refresh();
        if (!mounted) return;
        final entitled = ref.read(subscriptionProvider).valueOrNull?.entitled;
        final message = outcome.entitledNow || entitled == true
            ? 'Premium activated. Enjoy the full storyteller\'s toolkit.'
            : 'Purchase received — entitlement is syncing and will appear '
                  'imminently.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.savannahGreen,
          ),
        );
        Navigator.of(context).pop();
      } else if (outcome.cancelled) {
        // Store sheet closed by the reader: nothing to say.
      } else if (outcome.notConfigured) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome.message ??
                  'In-app purchases aren\'t available in this build.',
            ),
            backgroundColor: AppColors.charcoalMuted,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(outcome.message ?? 'The purchase could not be '
                'completed. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _purchase() => _run(
    () => ref.read(purchaseServiceProvider).purchase(),
  );

  Future<void> _restore() => _run(
    () => ref.read(purchaseServiceProvider).restore(),
  );

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(subscriptionProvider);
    final status = statusAsync.valueOrNull;
    final service = ref.watch(purchaseServiceProvider);
    final entitled = status?.entitled ?? false;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            children: [
              _buildHandle(),
              const SizedBox(height: 8),
              _buildHeader(entitled),
              const SizedBox(height: 16),
              _buildFeatureList(status),
              const SizedBox(height: 24),
              if (entitled)
                _buildAlreadyEntitled()
              else
                _buildStoreActions(service.isConfigured),
              const SizedBox(height: 16),
              _buildLegalLine(service.isConfigured),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.charcoalMuted.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(bool entitled) {
    return Column(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: AppColors.terracotta.withValues(alpha: 0.12),
          child: const Icon(
            AppIcons.medal,
            color: AppColors.terracotta,
            size: 30,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Griot Premium',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: AppColors.charcoal),
        ),
        const SizedBox(height: 4),
        Text(
          entitled
              ? 'Your premium access is active.'
              : 'Unlock the full storyteller\'s toolkit.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.charcoalMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureList(SubscriptionStatus? status) {
    final features = status?.features.where((f) => f.enabled).take(4) ?? [];
    if (features.isEmpty) {
      return _InfoTile(
        icon: AppIcons.lock_outline,
        text: 'Loading premium features…',
      );
    }
    return Column(
      children: features.map((f) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const Icon(
                AppIcons.auto_awesome,
                color: AppColors.bronzeDark,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  f.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.charcoal,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAlreadyEntitled() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: _busy
            ? null
            : () => ref.read(subscriptionProvider.notifier).refresh(),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.savannahGreen,
          foregroundColor: Colors.white,
        ),
        icon: const Icon(AppIcons.check_circle, size: 20),
        label: const Text(
          'You\'re all set — refresh status',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildStoreActions(bool storeConfigured) {
    if (!storeConfigured) {
      return _InfoTile(
        icon: AppIcons.star,
        text:
            'In-app purchases aren\'t enabled in this build. Premium access '
            'is granted by your institution or administrator.',
        emphasized: true,
      );
    }
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: _busy ? null : _purchase,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.terracotta,
              foregroundColor: AppColors.charcoal,
              disabledBackgroundColor: AppColors.terracotta.withValues(
                alpha: 0.5,
              ),
            ),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.charcoal,
                    ),
                  )
                : const Icon(AppIcons.medal, size: 20),
            label: Text(
              _busy ? 'Contacting the store…' : 'Subscribe to Premium',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _restore,
          child: const Text('Restore purchase'),
        ),
      ],
    );
  }

  Widget _buildLegalLine(bool storeConfigured) {
    if (!storeConfigured) return const SizedBox.shrink();
    return Text(
      'Subscription renews monthly until cancelled. Manage or cancel '
      'anytime from your store account.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppColors.charcoalMuted,
        fontSize: 11,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.text,
    this.emphasized = false,
  });

  final IconData icon;
  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final base = emphasized ? AppColors.bronzeDark : AppColors.charcoalMuted;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bronzeTint.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.bronze.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: base, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: base,
              ),
            ),
          ),
        ],
      ),
    );
  }
}