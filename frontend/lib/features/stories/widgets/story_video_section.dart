import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../auth/providers/auth_provider.dart';
import '../../video/models/video_model.dart';
import '../../video/providers/video_provider.dart';
import '../../video/widgets/video_generation_sheet.dart';
import '../../video/widgets/video_player_widget.dart';
import '../../video/widgets/video_status_badge.dart';
import '../models/story_model.dart';

/// AI video panel on the story screen.
///
/// Shows whatever exists for this story: the finished video, a live
/// generation status, or a failure with a way to try again. Renders nothing
/// at all when the signed-in user has no job for the story and cannot start
/// one, so a read-only visitor is not shown an empty box.
///
/// Generation itself is started from the story's actions menu; this section
/// is the place that reports on it.
class StoryVideoSection extends ConsumerStatefulWidget {
  const StoryVideoSection({super.key, required this.story});

  final StoryModel story;

  @override
  ConsumerState<StoryVideoSection> createState() => _StoryVideoSectionState();
}

class _StoryVideoSectionState extends ConsumerState<StoryVideoSection> {
  @override
  void initState() {
    super.initState();
    // Fetch the existing job so a story the user already rendered shows its
    // video on arrival instead of an empty panel.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(videoGenerationProvider.notifier).loadJobs();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = widget.story;

    final isAuthenticated = ref.watch(authProvider).maybeWhen(
      data: (s) => s.isAuthenticated,
      orElse: () => false,
    );

    final job = ref.watch(videoForStoryProvider(story.id));
    final canStart = isAuthenticated && _canStartGeneration(story);

    // Nothing to show and nothing to offer.
    if (job == null && !canStart) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Story Video',
          icon: AppIcons.movie_creation_outlined,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (job == null)
          _buildStartPrompt(context, theme)
        else if (job.isReady)
          _buildPlayer(context, theme, job)
        else if (job.hasFailed)
          _buildFailure(context, theme, job, canStart)
        else
          _buildInProgress(context, theme, job),
        const SizedBox(height: AppSpacing.section),
      ],
    );
  }

  /// Mirror the media API: published stories are open to any signed-in user,
  /// drafts to their author and the managing roles.
  bool _canStartGeneration(StoryModel story) {
    final user = ref.read(authProvider).maybeWhen(
      data: (s) => s.user,
      orElse: () => null,
    );
    if (user == null) return false;
    return user.canGenerateMediaFor(
      authorId: story.author.id,
      isPublished: story.isPublished,
    );
  }

  Widget _buildStartPrompt(BuildContext context, ThemeData theme) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bring this story to life',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Generate an AI video that visualises this story.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () => _openGenerator(context),
            icon: const Icon(AppIcons.auto_awesome, size: 18),
            label: const Text('Generate Video'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.terracotta,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer(BuildContext context, ThemeData theme, VideoModel job) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StoryVideoPlayer(video: job),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            VideoStatusBadge(status: job.status),
            const SizedBox(width: AppSpacing.sm),
            if (job.duration > 0)
              Text(
                job.formattedDuration,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildInProgress(
    BuildContext context,
    ThemeData theme,
    VideoModel job,
  ) {
    // The backend reports a percentage; fall back to an indeterminate bar
    // when it has nothing meaningful to say yet.
    final percent = job.progressPercent.clamp(0, 100);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VideoStatusBadge(status: job.status),
              const Spacer(),
              TextButton.icon(
                onPressed: () => ref
                    .read(videoGenerationProvider.notifier)
                    .cancelJob(job.id),
                icon: const Icon(AppIcons.close, size: 16),
                label: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent > 0 ? percent / 100 : null,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            percent > 0
                ? 'Rendering your video — $percent% complete.'
                : 'Your video is rendering. This can take a few minutes.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailure(
    BuildContext context,
    ThemeData theme,
    VideoModel job,
    bool canStart,
  ) {
    return AppCard(
      color: theme.colorScheme.errorContainer,
      borderColor: theme.colorScheme.error.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                AppIcons.error_outline,
                size: 20,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Video generation failed',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
          if (job.errorMessage != null && job.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              job.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ],
          if (canStart) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () => _openGenerator(context),
              icon: const Icon(AppIcons.refresh, size: 18),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.terracotta,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openGenerator(BuildContext context) {
    return VideoGenerationSheet.show(
      context,
      storyId: widget.story.id,
      storyTitle: widget.story.title,
    );
  }
}
