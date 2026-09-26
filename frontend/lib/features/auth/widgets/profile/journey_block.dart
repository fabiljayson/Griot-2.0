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
/// Every value comes from the server's gamification profile; nothing is mocked.
/// The weekly strip is drawn from the reader's real last active day, so it can
/// only mark days they were actually here.
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
                WeekStrip(
                  streak: profile.currentStreak,
                  lastActiveDate: profile.lastActiveDate,
                  activeToday: profile.activeToday,
                ),
                if (profile.currentStreak > 0 && !profile.activeToday) ...[
                  const SizedBox(height: AppSpacing.md),
                  StreakAtRiskPrompt(streak: profile.currentStreak),
                ],
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

/// The seven calendar days ending today, marked only where the reader was
/// actually active.
///
/// The previous version lit the last N weekday slots up to today, which was
/// wrong twice over: it ignored the reader's last active day, so a three-day run
/// that ended three weeks ago still showed Monday-to-Wednesday ticked, and it
/// mixed a weekday index with a count of days, so on a Monday a three-day streak
/// lit Tuesday and Wednesday — days that had not happened yet.
///
/// A day counts as active when it falls inside the run ending on
/// [lastActiveDate]: within [streak] days of it, and not after it.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.streak,
    required this.lastActiveDate,
    required this.activeToday,
  });

  /// Length of the current run, or 0 once a day has been missed.
  final int streak;

  /// The reader's most recent active day, or null if never active.
  final DateTime? lastActiveDate;

  /// Whether today already counts. False with a non-zero [streak] means the run
  /// is still alive but expires at the reader's midnight.
  final bool activeToday;

  static const _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// The days to render, oldest first, ending today.
  static List<DateTime> _window([DateTime? now]) {
    final today = _dateOnly(now ?? DateTime.now());
    return [
      for (var offset = 6; offset >= 0; offset--)
        today.subtract(Duration(days: offset)),
    ];
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @visibleForTesting
  static List<bool> litDays({
    required int streak,
    required DateTime? lastActiveDate,
    DateTime? now,
  }) {
    if (streak <= 0 || lastActiveDate == null) {
      return List.filled(7, false);
    }
    final window = _window(now);
    final today = window.last;
    final last = _dateOnly(lastActiveDate);
    // A last active day in the future means the device and the server disagree
    // about the date, so nothing here can be trusted. Marking nothing is the
    // only claim that cannot turn out to be false.
    if (last.isAfter(today)) return List.filled(7, false);

    return [
      for (final day in window)
        !day.isAfter(last) && last.difference(day).inDays < streak,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final days = _window();
    final lit = litDays(
      streak: streak,
      lastActiveDate: lastActiveDate,
      now: days.last,
    );
    final today = days.last;

    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: DayDot(
              label: _weekdayInitials[days[i].weekday - 1],
              isToday: days[i] == today,
              isLit: lit[i],
            ),
          ),
        ],
      ],
    );
  }
}

/// Shown when a run is still alive but today has not been logged yet.
///
/// The streak dies at the reader's own midnight, not at a fixed hour, so the
/// copy points at an activity they can take right now rather than a deadline.
class StreakAtRiskPrompt extends StatelessWidget {
  const StreakAtRiskPrompt({super.key, required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bronzeTint.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.bronze.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(AppIcons.fire, size: 20, color: AppColors.bronzeDark),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keep your $streak-day streak alive',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Read a few lines or take a quiz today to keep it going.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
