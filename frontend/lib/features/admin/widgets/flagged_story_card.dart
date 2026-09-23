import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/moderation_models.dart';
import 'moderation_widgets.dart';
import 'status_helpers.dart';

/// A flagged story with its reports and moderation actions.
class FlaggedStoryCard extends StatelessWidget {
  const FlaggedStoryCard({
    super.key,
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
              StatusPill(status: story.status),
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
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusColorFor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        statusLabel(status),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
