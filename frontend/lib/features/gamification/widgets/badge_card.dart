import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../services/gamification_api_service.dart';

/// Card widget displaying a badge with unlock state.
///
/// Shows earned badges with full color, and locked badges as greyed out.
/// Includes hover animation and unlock celebration.
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: badge.earned
                ? _parseColor(badge.color).withValues(alpha: 0.3)
                : scheme.outline,
          ),
        ),
        child: Center(
          child: FaIcon(
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
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: badge.earned
            ? scheme.surface
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: badge.earned
              ? _parseColor(badge.color).withValues(alpha: 0.3)
              : scheme.outline,
        ),
        boxShadow: badge.earned
            ? [
                BoxShadow(
                  color: _parseColor(badge.color).withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Badge icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: badge.earned
                  ? _parseColor(badge.color).withValues(alpha: 0.1)
                  : scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: FaIcon(
                badge.earned ? AppIcons.star : AppIcons.lock_outline,
                size: 30,
                color: badge.earned
                    ? _parseColor(badge.color)
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Badge name
          Text(
            badge.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: badge.earned
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant,
            ),
          ),

          if (!badge.earned && badge.xpRequired > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${badge.xpRequired} XP needed',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
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
