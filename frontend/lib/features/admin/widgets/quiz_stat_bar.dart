import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/analytics_models.dart';

/// Per-quiz attempt/pass bar.
class QuizStatBar extends StatelessWidget {
  const QuizStatBar({super.key, required this.quiz});

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
