import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../services/gamification_api_service.dart';

/// Card widget displaying a badge with unlock state.
///
/// Shows earned badges with full color, and locked badges as greyed out.
///
/// The cell is sized by the rewards grid (`childAspectRatio: 0.85`, so the
/// height depends on screen width), which previously overflowed on small
/// phones: the icon circle was a fixed 64px and the fixed paddings left less
/// room than the name + XP rows need. The layout is now adaptive — the icon
/// circle takes whatever height is left after the fixed text lines, and the
/// paddings come from the design tokens — so the cell renders without
/// overflow at any grid width or text scale.
class BadgeCard extends StatelessWidget {
  const BadgeCard({super.key, required this.badge, this.compact = false});

  final BadgeModel badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact(context);
    return _buildFull(context);
  }

  Widget _buildCompact(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: badge.name,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: badge.earned
              ? _parseColor(badge.color).withValues(alpha: 0.1)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: badge.earned
                ? _parseColor(badge.color).withValues(alpha: 0.3)
                : scheme.outline,
          ),
        ),
        child: Center(
          child: Icon(
            badge.earned ? AppIcons.star : AppIcons.lock_outline,
            size: 22,
            color: badge.earned
                ? _parseColor(badge.color)
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildFull(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _parseColor(badge.color);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: badge.earned ? scheme.surface : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: badge.earned ? accent.withValues(alpha: 0.3) : scheme.outline,
        ),
        boxShadow: badge.earned
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Badge icon — takes the remaining height so the fixed text below
          // can never be pushed out of the cell (the old fixed 64px circle
          // overflowed narrow grid tiles).
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final diameter = constraints.biggest.shortestSide;
                return Center(
                  child: Container(
                    width: diameter,
                    height: diameter,
                    decoration: BoxDecoration(
                      color: badge.earned
                          ? accent.withValues(alpha: 0.1)
                          : scheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        badge.earned ? AppIcons.star : AppIcons.lock_outline,
                        size: (diameter * 0.47).clamp(16.0, 30.0),
                        color: badge.earned ? accent : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Badge name — fixed two lines so every cell has the same rhythm.
          Text(
            badge.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 13,
              height: 1.15,
              color: badge.earned ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),

          // XP requirement — fixed single line, ellipsised.
          if (!badge.earned && badge.xpRequired > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${badge.xpRequired} XP needed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.terracotta;
    }
  }
}
