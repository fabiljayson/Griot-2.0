import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/models/user_model.dart';
import '../models/analytics_models.dart';
import '../models/moderation_models.dart';
import '../providers/admin_provider.dart';
import '../widgets/dashboard_section.dart';
import '../widgets/growth_chart.dart';
import '../widgets/moderation_widgets.dart';
import '../widgets/ranked_tile.dart';
import '../widgets/stat_card.dart';

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
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: summaryAsync.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _DashboardError(
          message: _friendlyError(error),
          onRetry: () {
            ref.invalidate(dashboardSummaryProvider);
            ref.invalidate(moderationQueueProvider);
          },
        ),
        data: (summary) => RefreshIndicator(
          // Keep the previous data visible while re-fetching.
          // Errors surface through the provider's error state instead.
          onRefresh: () => Future.wait([
            ref.refresh(dashboardSummaryProvider.future),
            ref.refresh(moderationQueueProvider.future),
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
                          value: _formatCount(summary.users.totalUsers),
                          icon: Icons.people_outline,
                          color: AppColors.terracotta,
                          subtitle:
                              '${summary.users.activeUsers30d} active (30d)',
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: StatCard(
                          label: 'Stories',
                          value: _formatCount(summary.stories.totalStories),
                          icon: Icons.auto_stories_outlined,
                          color: AppColors.ochre,
                          subtitle:
                              '${summary.stories.pendingReview} pending review',
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: StatCard(
                          label: 'Quiz Attempts',
                          value: _formatCount(
                            summary.gamification.totalQuizzesTaken,
                          ),
                          icon: Icons.quiz_outlined,
                          color: AppColors.savannahGreen,
                          subtitle:
                              '${summary.gamification.passRate}% pass rate',
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: StatCard(
                          label: 'QR Scans',
                          value: _formatCount(summary.qrCodes.totalScans),
                          icon: Icons.qr_code_scanner,
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
                      child: _GrowthCard(
                        title: 'User growth',
                        subtitle: 'New registrations, last 14 days',
                        icon: Icons.people_outline,
                        color: AppColors.terracotta,
                        data: summary.users.userGrowth,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _GrowthCard(
                        title: 'Story growth',
                        subtitle: 'Stories published, last 14 days',
                        icon: Icons.auto_stories_outlined,
                        color: AppColors.savannahGreen,
                        data: summary.stories.storyGrowth,
                      ),
                    ),
                  ],
                )
              else ...[
                _GrowthCard(
                  title: 'User growth',
                  subtitle: 'New registrations, last 14 days',
                  icon: Icons.people_outline,
                  color: AppColors.terracotta,
                  data: summary.users.userGrowth,
                ),
                const SizedBox(height: 16),
                _GrowthCard(
                  title: 'Story growth',
                  subtitle: 'Stories published, last 14 days',
                  icon: Icons.auto_stories_outlined,
                  color: AppColors.savannahGreen,
                  data: summary.stories.storyGrowth,
                ),
              ],
              const SizedBox(height: 20),

              // --- Audience -------------------------------------------------
              DashboardSection(
                title: 'Audience',
                subtitle: 'Users by role',
                child: _RoleBreakdown(usersByRole: summary.users.usersByRole),
              ),
              const SizedBox(height: 20),

              // --- Content library -----------------------------------------
              DashboardSection(
                title: 'Content library',
                subtitle: 'Story repository health',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionLabel(text: 'By status'),
                    const SizedBox(height: 6),
                    _CountPills(
                      items: summary.stories.storiesByStatus,
                      labelFor: _statusLabel,
                      colorFor: _statusColorFor,
                    ),
                    const SizedBox(height: 14),
                    const _SectionLabel(text: 'By language'),
                    const SizedBox(height: 6),
                    _CountPills(
                      items: summary.stories.storiesByLanguage,
                      labelFor: _languageLabel,
                      colorFor: _languageColorFor,
                    ),
                    const SizedBox(height: 16),
                    _EngagementTotals(stories: summary.stories),
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
                              '${_formatCount(story.viewCount)} views · '
                              '${_formatCount(story.likeCount)} likes',
                          trailing: _formatCount(story.viewCount),
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
                            icon: Icons.emoji_events_outlined,
                            label: 'Pass rate',
                            value: '${summary.gamification.passRate}%',
                            color: AppColors.savannahGreen,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: Icons.analytics_outlined,
                            label: 'Avg score',
                            value: '${summary.gamification.avgScore}%',
                            color: AppColors.terracotta,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: Icons.military_tech_outlined,
                            label: 'Badges earned',
                            value: '${summary.gamification.badgesEarned}',
                            color: AppColors.ochre,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: Icons.bolt_outlined,
                            label: 'XP earned',
                            value: _formatCount(
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
                              '🔥 ${user.currentStreak} day streak',
                          trailing: '${_formatCount(user.totalXp)} XP',
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
                        _QuizStatBar(quiz: quiz),
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
                            icon: Icons.qr_code_scanner,
                            label: 'Total scans',
                            value: _formatCount(summary.qrCodes.totalScans),
                            color: AppColors.terracotta,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: Icons.person_pin_outlined,
                            label: 'Unique scanners',
                            value: _formatCount(summary.qrCodes.uniqueScanners),
                            color: AppColors.savannahGreen,
                          ),
                        ),
                        SizedBox(
                          width: isWide ? 120 : 140,
                          child: MiniStat(
                            icon: Icons.museum_outlined,
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
                                icon: Icons.person_add_alt,
                                label: 'New users',
                                value:
                                    '${summary.engagement.recentActivity.newUsers}',
                                color: AppColors.terracotta,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MiniStat(
                                icon: Icons.auto_stories_outlined,
                                label: 'New stories',
                                value:
                                    '${summary.engagement.recentActivity.newStories}',
                                color: AppColors.ochre,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MiniStat(
                                icon: Icons.quiz_outlined,
                                label: 'Quiz attempts',
                                value:
                                    '${summary.engagement.recentActivity.quizAttempts}',
                                color: AppColors.savannahGreen,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MiniStat(
                                icon: Icons.qr_code_scanner,
                                label: 'QR scans',
                                value:
                                    '${summary.engagement.recentActivity.qrScans}',
                                color: AppColors.terracottaDark,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MiniStat(
                                icon: Icons.share_outlined,
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
                            icon: Icons.favorite_outline,
                            label: 'Total likes',
                            value: _formatCount(summary.engagement.totalLikes),
                            color: AppColors.terracotta,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MiniStat(
                            icon: Icons.bookmark_border,
                            label: 'Bookmarks',
                            value: _formatCount(
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
                            icon: Icons.share_outlined,
                            label: 'Shares',
                            value: _formatCount(summary.engagement.totalShares),
                            color: AppColors.savannahGreen,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: MiniStat(
                            icon: Icons.task_alt,
                            label: 'Completed reads',
                            value: _formatCount(
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
                      icon: Icons.menu_book_outlined,
                      label: 'Characters read',
                      value: _formatCount(summary.engagement.totalReadingTime),
                      color: AppColors.charcoalMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Moderation ----------------------------------------------
              _ModerationSection(
                unresolvedCount: summary.engagement.unresolvedFlags,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A flagged story with its reports and moderation actions.
class _FlaggedStoryCard extends StatelessWidget {
  const _FlaggedStoryCard({
    required this.story,
    required this.busyAction,
    required this.onRemove,
    required this.onDismiss,
  });

  final FlaggedStory story;

  /// The in-flight action for this story (`remove` / `dismiss`), if any.
  final String? busyAction;
  final VoidCallback onRemove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  story.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(status: story.status),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'by ${story.authorUsername} · ${story.flags.length} '
            '${story.flags.length == 1 ? 'flag' : 'flags'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          for (final flag in story.flags) FlagRow(flag: flag),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busyAction != null ? null : onDismiss,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.savannahGreen,
                    side: BorderSide(
                      color: AppColors.savannahGreen.withValues(alpha: 0.5),
                    ),
                    minimumSize: const Size(0, 40),
                  ),
                  child: busyAction == 'dismiss'
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.savannahGreen,
                          ),
                        )
                      : const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busyAction != null ? null : onRemove,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    minimumSize: const Size(0, 40),
                  ),
                  child: busyAction == 'remove'
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Remove story'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small status pill for a flagged story.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColorFor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _statusLabel(status),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Moderation queue section: flagged stories with remove/dismiss actions.
class _ModerationSection extends ConsumerStatefulWidget {
  const _ModerationSection({required this.unresolvedCount});

  final int unresolvedCount;

  @override
  ConsumerState<_ModerationSection> createState() => _ModerationSectionState();
}

class _ModerationSectionState extends ConsumerState<_ModerationSection> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final queueAsync = ref.watch(moderationQueueProvider);
    final moderation = ref.watch(moderationProvider);

    return DashboardSection(
      title: 'Moderation',
      subtitle: 'Flagged stories awaiting review',
      trailing: widget.unresolvedCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                '${widget.unresolvedCount} open',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : null,
      child: queueAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => ModerationError(
          message: 'Could not load the moderation queue.',
          onRetry: () => ref.invalidate(moderationQueueProvider),
        ),
        data: (flagged) => _buildQueue(context, theme, flagged, moderation),
      ),
    );
  }

  Widget _buildQueue(
    BuildContext context,
    ThemeData theme,
    List<FlaggedStory> flagged,
    ModerationState moderation,
  ) {
    if (flagged.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.savannahGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.savannahGreen.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            const Text('🎉', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No flagged stories — the library is all clear.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.savannahGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final story in flagged)
          _FlaggedStoryCard(
            story: story,
            busyAction: moderation.busyStoryId == story.storyId
                ? moderation.busyAction
                : null,
            onRemove: () => _moderate(context, story, 'remove'),
            onDismiss: () => _moderate(context, story, 'dismiss'),
          ),
      ],
    );
  }

  Future<void> _moderate(
    BuildContext context,
    FlaggedStory story,
    String action,
  ) async {
    if (action == 'remove') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.error,
            size: 40,
          ),
          title: const Text('Remove story?'),
          content: Text(
            '“${story.title}” will be archived and hidden from readers. '
            'All ${story.flags.length} flag(s) will be resolved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    final ok = await ref
        .read(moderationProvider.notifier)
        .moderate(story: story, action: action);

    if (!context.mounted) return;

    if (ok) {
      ref.invalidate(moderationQueueProvider);
      ref.invalidate(dashboardSummaryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'remove'
                ? 'Story removed and flags resolved'
                : 'Flags dismissed — story kept',
          ),
        ),
      );
    } else {
      final message =
          ref.read(moderationProvider).errorMessage ??
          'Moderation action failed. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// Growth chart wrapped in a titled card.
class _GrowthCard extends StatelessWidget {
  const _GrowthCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.data,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<GrowthPoint> data;

  @override
  Widget build(BuildContext context) {
    return DashboardSection(
      title: title,
      subtitle: subtitle,
      trailing: Icon(icon, color: color),
      child: GrowthChart(data: data, color: color),
    );
  }
}

/// User-role breakdown chips.
class _RoleBreakdown extends StatelessWidget {
  const _RoleBreakdown({required this.usersByRole});

  final Map<String, int> usersByRole;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (usersByRole.isEmpty) {
      return Text(
        'No users yet',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in usersByRole.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.terracotta.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.terracotta.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  UserRole.fromString(entry.key).emoji,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(width: 6),
                Text(
                  UserRole.fromString(entry.key).label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.value}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.terracotta,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Small subheading used inside dashboard sections.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Generic count pills row (used for story status & language breakdowns).
class _CountPills extends StatelessWidget {
  const _CountPills({
    required this.items,
    required this.labelFor,
    required this.colorFor,
  });

  final Map<String, int> items;
  final String Function(String key) labelFor;
  final Color Function(String key) colorFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Text(
        'No data yet',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in items.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorFor(entry.key).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorFor(entry.key).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  labelFor(entry.key),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.value}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorFor(entry.key),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Story status labels (mirrors backend Story.Status choices).
const _statusLabels = {
  'draft': 'Draft',
  'pending': 'Pending review',
  'published': 'Published',
  'rejected': 'Rejected',
  'archived': 'Archived',
};

String _statusLabel(String key) => _statusLabels[key] ?? key;

Color _statusColorFor(String key) {
  switch (key) {
    case 'published':
      return AppColors.savannahGreen;
    case 'pending':
      return AppColors.ochre;
    case 'rejected':
      return AppColors.error;
    default:
      return AppColors.charcoalMuted;
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

/// Total engagement counters (views / likes / bookmarks / shares).
class _EngagementTotals extends StatelessWidget {
  const _EngagementTotals({required this.stories});

  final StoryStats stories;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MiniStat(
            icon: Icons.visibility_outlined,
            label: 'Views',
            value: _formatCount(stories.totalViews),
            color: AppColors.terracotta,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MiniStat(
            icon: Icons.favorite_outline,
            label: 'Likes',
            value: _formatCount(stories.totalLikes),
            color: AppColors.ochre,
          ),
        ),
      ],
    );
  }
}

/// Per-quiz attempt/pass bar.
class _QuizStatBar extends StatelessWidget {
  const _QuizStatBar({required this.quiz});

  final QuizStat quiz;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = quiz.attemptCount == 0
        ? 0.0
        : ((quiz.passCount / quiz.attemptCount).clamp(0.0, 1.0)).toDouble();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  quiz.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${quiz.passCount}/${quiz.attemptCount} passed',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: AppColors.savannahGreen,
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state with a retry action.
class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📊', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'Dashboard unavailable',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatCount(int n) {
  if (n >= 1000000) {
    final v = n / 1000000;
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}M';
  }
  if (n >= 1000) {
    final v = n / 1000;
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}K';
  }
  return '$n';
}

String _friendlyError(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 403) {
      return 'You need administrator access to view analytics.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Could not reach the server. Check your connection.';
    }
  }
  return 'Something went wrong while loading analytics.';
}
