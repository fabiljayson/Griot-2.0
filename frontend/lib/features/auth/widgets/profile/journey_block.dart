import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../../core/widgets/griot_loader.dart';
import '../../../gamification/providers/gamification_provider.dart';
import 'mini_stat.dart';

/// Level, XP progress and reading streak — the reference screen's hero block.
///
/// Every value comes from the local gamification store; nothing is mocked. The
/// weekly strip is derived from the stored streak (the last N days were read),
/// so it cannot show activity the reader did not have.
class JourneyBlock extends ConsumerWidget {
  const JourneyBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(gamificationProfileProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Your Journey', icon: AppIcons.medal),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: profileAsync.when(
            loading: () => const SizedBox(
              height: 96,
              child: Center(child: GriotLoader(size: 28)),
            ),
            error: (_, _) => JourneyUnavailable(
              onRetry: () => ref.invalidate(gamificationProfileProvider),
            ),
            data: (profile) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${profile.currentStreak}',
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          profile.currentStreak == 1
                              ? 'Day streak'
                              : 'Days streak',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    Icon(AppIcons.fire, size: 22, color: AppColors.bronze),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Text(
                      'Level ${profile.level}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const Spacer(),
                    Text(
                      '${profile.totalXp}/${profile.xpForNextLevel} XP',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // Bar only: the level and XP label live in the row above, so
                // the value never overlaps or truncates.
                ProgressRow(fraction: profile.xpProgress, showValue: false),
                const SizedBox(height: AppSpacing.lg),
                WeekStrip(streak: profile.currentStreak),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    MiniStat(
                      icon: AppIcons.auto_stories_outlined,
                      value: '${profile.storiesRead}',
                      label: 'Read',
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    MiniStat(
                      icon: AppIcons.quiz_outlined,
                      value: '${profile.quizzesPassed}',
                      label: 'Quizzes',
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    MiniStat(
                      icon: AppIcons.emoji_events_outlined,
                      value: '${profile.badgesCount}',
                      label: 'Badges',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fallback when the local gamification profile cannot be read.
class JourneyUnavailable extends StatelessWidget {
  const JourneyUnavailable({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          AppIcons.error_outline,
          size: 22,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            'Your journey is unavailable right now.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

/// Seven-day strip: the days the stored streak covers, up to today.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.streak});

  final int streak;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final todayIndex = DateTime.now().weekday - 1; // 0 = Monday
    final lit = streak.clamp(0, 7);
    final firstLit = todayIndex + 1 - lit;

    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: DayDot(
              label: _labels[i],
              isToday: i == todayIndex,
              isLit: i >= firstLit && i <= todayIndex,
            ),
          ),
        ],
      ],
    );
  }
}

class DayDot extends StatelessWidget {
  const DayDot({
    super.key,
    required this.label,
    required this.isToday,
    required this.isLit,
  });

  final String label;
  final bool isToday;
  final bool isLit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Color fill = isLit
        ? (isToday ? AppColors.bronze : AppColors.bronzeTint)
        : Colors.transparent;
    final Color border = isLit
        ? AppColors.bronze
        : scheme.outline.withValues(alpha: 0.6);

    return Column(
      children: [
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: border),
          ),
          // A day the streak did not cover stays an empty slot rather than
          // borrowing a tick it did not earn.
          child: isLit
              ? const Center(
                  child: Icon(
                    AppIcons.check,
                    size: 13,
                    color: AppColors.charcoal,
                  ),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isToday ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
