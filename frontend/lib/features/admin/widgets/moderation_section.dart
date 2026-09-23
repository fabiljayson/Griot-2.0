import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../models/moderation_models.dart';
import '../providers/admin_provider.dart';
import 'dashboard_section.dart';
import 'flagged_story_card.dart';
import 'moderation_widgets.dart';

/// Moderation queue section: flagged stories with remove/dismiss actions.
class ModerationSection extends ConsumerStatefulWidget {
  const ModerationSection({super.key, required this.unresolvedCount});

  final int unresolvedCount;

  @override
  ConsumerState<ModerationSection> createState() => _ModerationSectionState();
}

class _ModerationSectionState extends ConsumerState<ModerationSection> {
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
            const Icon(AppIcons.check_circle, size: 22),
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
          FlaggedStoryCard(
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
            AppIcons.warning_amber_rounded,
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
