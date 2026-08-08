import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Ranked list tile: rank badge, title/subtitle, and a trailing metric.
class RankedTile extends StatelessWidget {
  const RankedTile({
    super.key,
    required this.rank,
    required this.title,
    this.subtitle,
    this.trailing,
    this.color = AppColors.terracotta,
    this.divider = true,
  });

  final int rank;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Color color;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPodium = rank <= 3;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isPodium ? 0.2 : 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.withValues(alpha: isPodium ? 0.55 : 0.2),
                  ),
                ),
                child: Text(
                  '$rank',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
            ],
          ),
        ),
        if (divider)
          Divider(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.08),
          ),
      ],
    );
  }
}
