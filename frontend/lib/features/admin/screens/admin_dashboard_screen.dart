import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../providers/admin_provider.dart';
import '../widgets/count_pills.dart';
import '../widgets/dashboard_error.dart';
import '../widgets/dashboard_section.dart';
import '../widgets/engagement_totals.dart';
import '../widgets/growth_card.dart';
import '../widgets/growth_chart.dart';
import '../widgets/moderation_section.dart';
import '../widgets/quiz_stat_bar.dart';
import '../widgets/ranked_tile.dart';
import '../widgets/role_breakdown.dart';
import '../widgets/section_label.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_helpers.dart';
import '../widgets/users_section.dart';
import '../widgets/value_formatters.dart';

/// Admin dashboard — Phase 9.
///
/// Aggregated platform analytics for admins and institution managers:
/// users, stories, gamification, QR scans, and engagement.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(dashboardSummaryProvider);
              ref.invalidate(moderationQueueProvider);
              ref.invalidate(adminUsersProvider);
            },
            icon: const Icon(AppIcons.refresh),
          ),
        ],
      ),
      body: summaryAsync.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => DashboardError(
          message: friendlyError(error),
          onRetry: () {
            ref.invalidate(dashboardSummaryProvider);
            ref.invalidate(moderationQueueProvider);
            ref.invalidate(adminUsersProvider);
          },
        ),
        data: (summary) => RefreshIndicator(
          // Keep the previous data visible while re-fetching.
          // Errors surface through the provider's error state instead.
onRefresh: () => Future.wait([
              ref.refresh(dashboardSummaryProvider.future),
              ref.refresh(moderationQueueProvider.future),
              ref.refresh(adminUsersProvider.future),
            ]).then((_) {}, onError: (_) {}),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              // --- Overview -------------------------------------------------
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = isWide
                      ? (constraints.maxWidth - 36) / 4
                      : (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: StatCard(
                          label: 'Total Users',
                          value: formatCount(summary.users.totalUsers),
                          icon: AppIcons.people_outline,
                          color: AppColors.terracotta,
                          subtitle:
                              '${summary.users.activeUsers30d} active (30d)',
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: StatCard(
                          label: 'Stories',
                          value: formatCount(summary.stories.totalStories),
                          icon: AppIcons.auto_stories_outlined,
                          color: AppColors.ochre,
                          subtitle:
                              '${summary.stories.pendingReview} pending review',
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: StatCard(
                          label: 'Quiz Attempts',
                          value: formatCount(
                            summary.gamification.totalQuizzesTaken,
                          ),
                          icon: AppIcons.quiz_outlined,
                          color: AppColors.savannahGreen,
                          subtitle:
                              '${summary.gamification.passRate}% pass rate',
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: StatCard(
                          label: 'QR Scans',
                          value: formatCount(summary.qrCodes.totalScans),
                          icon: AppIcons.qr_code_scanner,
                          color: AppColors.terracottaDark,
                          subtitle:
                              '${summary.qrCodes.uniqueScanners} unique scanners',
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),

              // --- Growth charts -------------------------------------------
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GrowthCard(
                        title: 'User growth',
                        subtitle: 'New registrations, last 14 days',
                        icon: AppIcons.people_outline,
                        color: AppColors.terracotta,
                        data: summary.users.userGrowth,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GrowthCard(
                        title: 'Story growth',
                        subtitle: 'Stories published, last 14 days',
                        icon: AppIcons.auto_stories_outlined,
                        color: AppColors.savannahGreen,
                        data: summary.stories.storyGrowth,
                      ),
                    ),
                  ],
                )
              else ...[
                GrowthCard(
                  title: 'User growth',
                  subtitle: 'New registrations, last 14 days',
                  icon: AppIcons.people_outline,
                  color: AppColors.terracotta,
                  data: summary.users.userGrowth,
                ),
                const SizedBox(height: 16),
                GrowthCard(
                  title: 'Story growth',
                  subtitle: 'Stories published, last 14 days',
                  icon: AppIcons.auto_stories_outlined,
                  color: AppColors.savannahGreen,
                  data: summary.stories.storyGrowth,
                ),
              ],
              const SizedBox(height: 20),

              // --- Audience -------------------------------------------------
              DashboardSection(
                title: 'Audience',
                subtitle: 'Users by role',
                child: RoleBreakdown(usersByRole: summary.users.usersByRole),
              ),
              const SizedBox(height: 20),

              // --- Content library -----------------------------------------
              DashboardSection(
                title: 'Content library',
                subtitle: 'Story repository health',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel(text: 'By status'),
                    const SizedBox(height: 6),
                    CountPills(
                      items: summary.stories.storiesByStatus,
                      labelFor: statusLabel,
                      colorFor: statusColorFor,
                    ),
                    const SizedBox(height: 14),
                    const SectionLabel(text: 'By language'),
                    const SizedBox(height: 6),
                    CountPills(
                      items: summary.stories.storiesByLanguage,
                      labelFor: _languageLabel,
                      colorFor: _languageColorFor,
                    ),
                    const SizedBox(height: 16),
                    EngagementTotals(stories: summary.stories),
                    if (summary.stories.topStories.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Top stories by views',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final (index, story)
                          in summary.stories.topStories.take(5).indexed)
                        RankedTile(
                          rank: index + 1,
                          title: story.title,
                          subtitle:
                              '${formatCount(story.viewCount)} views · '
                              '${formatCount(story.likeCount)} likes',
                          trailing: formatCount(story.viewCount),
                          color: AppColors.terracotta,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Gamification --------------------------------------------
              DashboardSection(
                title: 'Gamification',
                subtitle: 'Quizzes, badges & XP',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: AppIcons.emoji_events_outlined,
                            label: 'Pass rate',
                            value: '${summary.gamification.passRate}%',
                            color: AppColors.savannahGreen,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: AppIcons.analytics_outlined,
                            label: 'Avg score',
                            value: '${summary.gamification.avgScore}%',
                            color: AppColors.terracotta,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: AppIcons.military_tech_outlined,
                            label: 'Badges earned',
                            value: '${summary.gamification.badgesEarned}',
                            color: AppColors.ochre,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: AppIcons.bolt_outlined,
                            label: 'XP earned',
                            value: formatCount(
                              summary.gamification.totalXpEarned,
                            ),
                            color: AppColors.terracottaDark,
                          ),
                        ),
                      ],
                    ),
                    if (summary.gamification.topUsers.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Top readers',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final (index, user)
                          in summary.gamification.topUsers.take(5).indexed)
                        RankedTile(
                          rank: index + 1,
                          title: user.username,
                          subtitle:
                              'Level ${user.level} · ${user.storiesRead} stories · '
                              '${user.currentStreak} day streak',
                          trailing: '${formatCount(user.totalXp)} XP',
                          color: AppColors.ochre,
                        ),
                    ],
                    if (summary.gamification.quizStats.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Quiz performance',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final quiz in summary.gamification.quizStats.take(5))
                        QuizStatBar(quiz: quiz),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- QR & artifacts ------------------------------------------
              DashboardSection(
                title: 'QR & museum artifacts',
                subtitle: 'Museum scan engine',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: AppIcons.qr_code_scanner,
                            label: 'Total scans',
                            value: formatCount(summary.qrCodes.totalScans),
                            color: AppColors.terracotta,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: AppIcons.person_pin_outlined,
                            label: 'Unique scanners',
                            value: formatCount(summary.qrCodes.uniqueScanners),
                            color: AppColors.savannahGreen,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: AppIcons.museum_outlined,
                            label: 'Published',
                            value:
                                '${summary.qrCodes.publishedArtifacts}/${summary.qrCodes.totalArtifacts}',
                            color: AppColors.ochre,
                          ),
                        ),
                      ],
                    ),
                    if (summary.qrCodes.scanGrowth.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      GrowthChart(
                        data: summary.qrCodes.scanGrowth,
                        color: AppColors.terracottaDark,
                        maxBars: 14,
                      ),
                    ],
                    if (summary.qrCodes.topArtifacts.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Most scanned artifacts',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final (index, artifact)
                          in summary.qrCodes.topArtifacts.take(5).indexed)
                        RankedTile(
                          rank: index + 1,
                          title: artifact.title,
                          subtitle: artifact.museumName,
                          trailing: '${artifact.scanCount} scans',
                          color: AppColors.savannahGreen,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Engagement ----------------------------------------------
              DashboardSection(
                title: 'Engagement',
                subtitle: 'Community activity, last 7 days',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth >= 500
                            ? 150.0
                            : (constraints.maxWidth - 10) / 2;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: width,
                              child: MiniStat(
                                icon: AppIcons.person_add_alt,
                                label: 'New users',
                                value:
                                    '${summary.engagement.recentActivity.newUsers}',
                                color: AppColors.terracotta,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MiniStat(
                                icon: AppIcons.auto_stories_outlined,
                                label: 'New stories',
                                value:
                                    '${summary.engagement.recentActivity.newStories}',
                                color: AppColors.ochre,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MiniStat(
                                icon: AppIcons.quiz_outlined,
                                label: 'Quiz attempts',
                                value:
                                    '${summary.engagement.recentActivity.quizAttempts}',
                                color: AppColors.savannahGreen,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MiniStat(
                                icon: AppIcons.qr_code_scanner,
                                label: 'QR scans',
                                value:
                                    '${summary.engagement.recentActivity.qrScans}',
                                color: AppColors.terracottaDark,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MiniStat(
                                icon: AppIcons.share_outlined,
                                label: 'Shares',
                                value:
                                    '${summary.engagement.recentActivity.shares}',
                                color: AppColors.charcoalMuted,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: MiniStat(
                            icon: AppIcons.favorite_outline,
                            label: 'Total likes',
                            value: formatCount(summary.engagement.totalLikes),
                            color: AppColors.terracotta,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MiniStat(
                            icon: AppIcons.bookmark_border,
                            label: 'Bookmarks',
                            value: formatCount(
                              summary.engagement.totalBookmarks,
                            ),
                            color: AppColors.ochre,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: MiniStat(
                            icon: AppIcons.share_outlined,
                            label: 'Shares',
                            value: formatCount(summary.engagement.totalShares),
                            color: AppColors.savannahGreen,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MiniStat(
                            icon: AppIcons.task_alt,
                            label: 'Completed reads',
                            value: formatCount(
                              summary.engagement.completedReadings,
                            ),
                            color: AppColors.terracottaDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // total_reading_time sums character positions, not minutes.
                    MiniStat(
                      icon: AppIcons.menu_book_outlined,
                      label: 'Characters read',
                      value: formatCount(summary.engagement.totalReadingTime),
                      color: AppColors.charcoalMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Platform users -----------------------------------------
              const PlatformUsersSection(),
              const SizedBox(height: 20),

              // --- Moderation ----------------------------------------------
              ModerationSection(
                unresolvedCount: summary.engagement.unresolvedFlags,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Story language labels (mirrors backend Story.Language choices).
const _languageLabels = {
  'en': 'English',
  'fr': 'French',
  'ful': 'Fula',
  'dua': 'Duala',
  'ewo': 'Ewondo',
};

String _languageLabel(String key) => _languageLabels[key] ?? key;

Color _languageColorFor(String key) {
  switch (key) {
    case 'en':
      return AppColors.terracotta;
    case 'fr':
      return AppColors.ochre;
    case 'ful':
      return AppColors.savannahGreen;
    case 'dua':
      return AppColors.terracottaDark;
    case 'ewo':
      return AppColors.savannahGreenTint;
    default:
      return AppColors.charcoalMuted;
  }
}
