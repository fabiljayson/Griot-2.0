import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/video_model.dart';

/// Compact badge showing video generation status.
///
/// Displays the current status with a color-coded icon and label.
/// Useful for inline display in story cards or lists.
class VideoStatusBadge extends StatelessWidget {
  const VideoStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final VideoStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      VideoStatus.pending => (AppColors.ochre, Icons.schedule),
      VideoStatus.processing => (AppColors.terracotta, Icons.autorenew),
      VideoStatus.completed => (AppColors.savannahGreen, Icons.check_circle),
      VideoStatus.failed => (AppColors.error, Icons.error_outline),
    };

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: color),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == VideoStatus.processing)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (status.emoji.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(status.emoji, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
