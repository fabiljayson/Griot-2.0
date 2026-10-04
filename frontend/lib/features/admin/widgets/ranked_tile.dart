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
    this.textColor = AppColors.accentTextStrong,
    this.divider = true,
  });

  final int rank;
  final String title;
  final String? subtitle;
  final String? trailing;

  /// Accent used for the chip fill and border. Decorative, so the bright
  /// brand bronze is correct here.
  final Color color;

  /// Accent used for the two pieces of *text* this tile paints — the rank
  /// numeral and the trailing metric.
  ///
  /// Deliberately not [color]. The brand accent measures 2.95:1 on white and
  /// 2.80:1 on ivory, which is fine for a fill but well short of the 4.5:1 that
  /// WCAG 1.4.3 requires of small bold text. Both call sites pass the same
  /// bronze under different names, so one strong token covers them all.
  final Color textColor;
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
                    color: textColor,
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
                    color: textColor,
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
