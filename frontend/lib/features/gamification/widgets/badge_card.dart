import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
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
    return Tooltip(
      message: badge.earned ? badge.name : '🔒 ${badge.name}',
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: badge.earned
              ? _parseColor(badge.color).withValues(alpha: 0.1)
              : AppColors.parchmentDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: badge.earned
                ? _parseColor(badge.color).withValues(alpha: 0.3)
                : AppColors.charcoalMuted.withValues(alpha: 0.1),
          ),
        ),
        child: Center(
          child: Text(
            badge.earned ? badge.emoji : '🔒',
            style: TextStyle(
              fontSize: 24,
              color: badge.earned ? null : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFull(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: badge.earned
            ? Colors.white
            : Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: badge.earned
              ? _parseColor(badge.color).withValues(alpha: 0.3)
              : AppColors.charcoalMuted.withValues(alpha: 0.1),
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
          // Badge emoji
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: badge.earned
                  ? _parseColor(badge.color).withValues(alpha: 0.1)
                  : AppColors.parchmentDark,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                badge.earned ? badge.emoji : '🔒',
                style: TextStyle(
                  fontSize: 32,
                  color: badge.earned ? null : Colors.grey,
                ),
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
                  ? AppColors.charcoal
                  : AppColors.charcoalMuted,
            ),
          ),

          if (!badge.earned && badge.xpRequired > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${badge.xpRequired} XP needed',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.charcoalMuted),
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
