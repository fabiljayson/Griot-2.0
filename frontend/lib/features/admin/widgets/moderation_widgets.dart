import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/moderation_models.dart';

/// A single flag report: reason, reporter, date, and optional details.
class FlagRow extends StatelessWidget {
  const FlagRow({super.key, required this.flag});

  final FlagDetail flag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = reasonColorFor(flag.reason);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      flex: 3,
                      child: Text(
                        flag.reasonDisplay.isEmpty
                            ? flag.reason
                            : flag.reasonDisplay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 2,
                      child: Text(
                        flag.createdAt.isEmpty
                            ? 'by ${flag.reporter}'
                            : 'by ${flag.reporter} · ${formatDate(flag.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (flag.details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(flag.details, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact error state with a retry action.
class ModerationError extends StatelessWidget {
  const ModerationError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

/// Accent color for a flag reason.
Color reasonColorFor(String reason) {
  switch (reason) {
    case 'cultural_inaccuracy':
      return AppColors.ochre;
    case 'inappropriate_content':
      return AppColors.error;
    case 'copyright_violation':
      return AppColors.terracottaDark;
    case 'wrong_category':
      return AppColors.savannahGreen;
    default:
      return AppColors.charcoalMuted;
  }
}

/// Format an ISO timestamp as `d MMM` (e.g. "5 Aug").
String formatDate(String iso) {
  if (iso.isEmpty) return '';
  try {
    final date = DateTime.parse(iso).toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  } catch (_) {
    return iso;
  }
}
