import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_loader.dart';
import '../../../core/widgets/griot_splash_screen.dart';
import '../providers/gamification_provider.dart';
import '../services/gamification_api_service.dart';
import '../widgets/badge_card.dart';
import '../widgets/progress_bar.dart';
import 'quiz_screen.dart';

/// Achievements hub: level progress, stats, badges and quizzes.
///
/// Everything here used to be painted with hardcoded `Colors.white` surfaces and
/// `AppColors.parchment`/`charcoal` text, which rendered as bright light-mode
/// panels inside the dark theme. All surfaces now come from the active
/// [ColorScheme].
class GamificationScreen extends ConsumerWidget {
  const GamificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(gamificationProfileProvider);
    final badgesAsync = ref.watch(badgesProvider);
    final quizzesAsync = ref.watch(quizzesProvider);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(gamificationProfileProvider);
          ref.invalidate(badgesProvider);
          ref.invalidate(quizzesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Rewards', style: theme.textTheme.displaySmall),
            const SizedBox(height: AppSpacing.lg),

            profileAsync.when(
              data: (profile) => LevelProgressBar(
                level: profile.level,
                totalXp: profile.totalXp,
                xpProgress: profile.xpProgress,
                xpForNextLevel: profile.xpForNextLevel,
                currentStreak: profile.currentStreak,
              ),
              loading: () => const SizedBox(
                height: 120,
                child: GriotLoadingState(),
              ),
              error: (error, _) => ErrorState(
                message: '$error',
                title: 'Could not load your progress',
                onRetry: () => ref.invalidate(gamificationProfileProvider),
              ),
            ),
            const SizedBox(height: AppSpacing.section),

            profileAsync.when(
              data: (profile) => _StatsRow(profile: profile),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: GriotSplashLoader(
                  compact: true,
                  caption: 'Loading stats',
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.section),

            const SectionHeader(title: 'Badges', icon: AppIcons.medal_outlined),
            const SizedBox(height: AppSpacing.md),
            badgesAsync.when(
              data: (badges) => badges.isEmpty
                  ? const EmptyState(
                      title: 'No badges yet',
                      subtitle: 'Keep reading to start earning heritage badges.',
                      icon: AppIcons.medal_outlined,
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 120,
                            mainAxisSpacing: AppSpacing.sm,
                            crossAxisSpacing: AppSpacing.sm,
                            // Taller-than-wide cells: icon + 2-line name +
                            // XP line with the card padding needs ~1.28× the
                            // width; 0.78 leaves headroom on small phones so
                            // the tile never overflows (BadgeCard flexes the
                            // icon to whatever height remains).
                            childAspectRatio: 0.78,
                          ),
                      itemCount: badges.length,
                      itemBuilder: (context, index) =>
                          BadgeCard(badge: badges[index]),
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: GriotLoader(),
              ),
              error: (error, _) => ErrorState(
                message: '$error',
                title: 'Could not load badges',
                onRetry: () => ref.invalidate(badgesProvider),
              ),
            ),
            const SizedBox(height: AppSpacing.section),

            const SectionHeader(title: 'Quizzes', icon: AppIcons.quiz_outlined),
            const SizedBox(height: AppSpacing.md),
            quizzesAsync.when(
              data: (quizzes) => _QuizList(quizzes: quizzes),
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: GriotLoader(),
              ),
              error: (error, _) => ErrorState(
                message: '$error',
                title: 'Could not load quizzes',
                onRetry: () => ref.invalidate(quizzesProvider),
              ),
            ),
            const SizedBox(height: AppSpacing.sectionLarge),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.profile});

  final GamificationProfileModel profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(
          icon: AppIcons.menu_book_outlined,
          value: '${profile.storiesRead}',
          label: 'Stories',
        ),
        const SizedBox(width: AppSpacing.sm),
        _StatCard(
          icon: AppIcons.quiz_outlined,
          value: '${profile.quizzesPassed}',
          label: 'Quizzes',
        ),
        const SizedBox(width: AppSpacing.sm),
        _StatCard(
          icon: AppIcons.emoji_events_outlined,
          value: '${profile.badgesCount}',
          label: 'Badges',
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          children: [
            Icon(icon, color: AppColors.bronze, size: 20),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Quizzes list. Routed through the shared [QuizScreen] rather than an inline
/// `Scaffold`, so the reader and the Rewards tab open the same experience.
class _QuizList extends StatelessWidget {
  const _QuizList({required this.quizzes});

  final List<QuizModel> quizzes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (quizzes.isEmpty) {
      return const EmptyState(
        title: 'No quizzes available yet',
        subtitle: 'Read more stories to unlock quizzes.',
        icon: AppIcons.quiz_outlined,
      );
    }

    return Column(
      children: quizzes.map((quiz) {
        final passed = quiz.bestScore != null &&
            quiz.bestScore! >= quiz.passingScore;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            onTap: () => QuizScreen.open(context, quiz),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.bronze.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: const Center(
                    child: Icon(
                      AppIcons.quiz_outlined,
                      size: 20,
                      color: AppColors.bronzeDark,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quiz.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        '${quiz.questionCount} questions • ${quiz.xpReward} XP',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (quiz.bestScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: passed
                          ? scheme.tertiaryContainer
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      'Best ${quiz.bestScore}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: passed
                            ? scheme.onTertiaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Icon(
                    AppIcons.chevron_right,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
