import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../auth/models/user_model.dart';

/// User-role breakdown chips.
class RoleBreakdown extends StatelessWidget {
  const RoleBreakdown({super.key, required this.usersByRole});

  final Map<String, int> usersByRole;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (usersByRole.isEmpty) {
      return Text(
        'No users yet',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in usersByRole.entries)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.terracotta.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.terracotta.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Real icon for the role instead of the model's emoji glyph.
                Icon(
                  AppIcons.role(entry.key),
                  size: 13,
                  color: AppColors.bronzeDark,
                ),
                const SizedBox(width: 6),
                Text(
                  UserRole.fromString(entry.key).label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.value}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.terracotta,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
