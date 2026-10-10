import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_skeleton.dart';
import '../models/subscription_status.dart';
import '../providers/subscription_provider.dart';
import '../widgets/paywall_sheet.dart';

/// The subscription surface: status, free-vs-premium, plans, benefits.
///
/// The backend is the authority — this screen renders `status/` and `plans/`
/// and never decides entitlement itself. Every purchase CTA goes through
/// [PaywallSheet], which drives the store seam and refreshes the status.
class PremiumScreen extends ConsumerWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(subscriptionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Griot Premium')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(subscriptionProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
          switch (statusAsync) {
            AsyncError() => _StatusError(
              onRetry: () =>
                  ref.read(subscriptionProvider.notifier).refresh(),
            ),
            AsyncValue(hasValue: false) =>
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: GriotSkeletonList(itemCount: 3),
              ),
            AsyncValue(value: final status?) => _StatusCard(status: status),
            _ => const SizedBox.shrink(),
          },
            const SizedBox(height: AppSpacing.section),
            const _ComparisonSection(),
            const SizedBox(height: AppSpacing.section),
            const _PlansSection(),
            const SizedBox(height: AppSpacing.section),
            if (statusAsync.valueOrNull != null)
              _SubscriptionDetails(status: statusAsync.valueOrNull!),
            const SizedBox(height: AppSpacing.section),
          ],
        ),
      ),
    );
  }
}

/// The reader's current standing: free or premium, and what that means.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entitled = status.entitled;

    return AppCard(
      elevated: true,
      color: entitled
          ? AppColors.bronzeTint.withValues(alpha: 0.35)
          : theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: entitled
                      ? AppColors.bronze.withValues(alpha: 0.18)
                      : theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  entitled ? AppIcons.medal : AppIcons.lock_outline,
                  color: entitled ? AppColors.bronzeDark : theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entitled ? 'Premium' : 'Free',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      entitled
                          ? (status.planName ?? 'Your premium access is active.')
                          : 'Core stories, discovery and quizzes — on the house.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (entitled && status.currentPeriodEnd != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Active until ${_formatDate(status.currentPeriodEnd!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.bronzeDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (!entitled) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => PaywallSheet.show(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.bronze,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(AppIcons.medal, size: 20),
                label: const Text(
                  'Go Premium',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Free vs Premium, side by side. The premium column is the server's own
/// feature list, so the comparison cannot drift from what is actually gated.
class _ComparisonSection extends ConsumerWidget {
  const _ComparisonSection();

  static const _freePerks = [
    'Basic stories',
    'Cultural discovery',
    'Selected quizzes',
    'Limited AI assistant',
    'Offline reading',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final features =
        ref.watch(subscriptionProvider).valueOrNull?.features ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Compare', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _PerkCard(
                title: 'Free',
                icon: AppIcons.lock_outline,
                iconColor: theme.colorScheme.primary,
                perks: _freePerks,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _PerkCard(
                title: 'Premium',
                icon: AppIcons.medal,
                iconColor: AppColors.bronzeDark,
                perks: [
                  for (final feature in features)
                    if (feature.enabled) feature.label,
                ],
                emptyHint: 'Loading premium benefits…',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PerkCard extends StatelessWidget {
  const _PerkCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.perks,
    this.emptyHint,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<String> perks;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: iconColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (perks.isEmpty && emptyHint != null)
            Text(
              emptyHint!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final perk in perks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(AppIcons.check, size: 15, color: iconColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        perk,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// The plan shelf from `GET /api/subscriptions/plans/`.
class _PlansSection extends ConsumerWidget {
  const _PlansSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plansAsync = ref.watch(plansProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Plans', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        switch (plansAsync) {
          AsyncError() => AppCard(
            child: Text(
              'Plans could not be loaded right now.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          AsyncValue(hasValue: false) =>
            const GriotSkeletonList(itemCount: 2),
          AsyncValue(value: final plans?) when plans.isEmpty => AppCard(
            child: Text(
              'No plans are on sale yet. Premium is granted by your '
              'institution or administrator.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          AsyncValue(value: final plans?) => Column(
            children: [for (final plan in plans) _PlanCard(plan: plan)],
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final SubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (plan.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      plan.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  plan.priceLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: () => PaywallSheet.show(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.bronze,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('Choose'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The raw subscription record: status, plan, provider, dates.
///
/// Shown for every signed-in reader, free included — "what does my account
/// actually say" is the question this answers, straight from the payload.
class _SubscriptionDetails extends StatelessWidget {
  const _SubscriptionDetails({required this.status});

  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      ('Status', status.status ?? 'None'),
      if (status.planName != null) ('Plan', status.planName!),
      if (status.provider != null)
        ('Provider', status.provider == 'dev' ? 'Development' : status.provider!),
      if (status.currentPeriodStart != null)
        ('Started', _formatDate(status.currentPeriodStart!)),
      if (status.currentPeriodEnd != null)
        ('Expires', _formatDate(status.currentPeriodEnd!)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your subscription', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            children: [
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(
                          label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusError extends StatelessWidget {
  const _StatusError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        children: [
          Text(
            'We couldn\'t load your premium status.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// `07 Oct 2026` — local, dependency-free, matching the app's other dates.
String _formatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final day = date.day.toString().padLeft(2, '0');
  return '$day ${months[date.month - 1]} ${date.year}';
}
