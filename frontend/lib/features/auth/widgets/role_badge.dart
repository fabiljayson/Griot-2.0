import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../models/user_model.dart';

/// Visual badge displaying the user's role with an icon and label.
///
/// Used in headers, profile screens, and navigation elements.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role, this.compact = false});

  final UserRole role;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _getRoleColor(role).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(
          spacing: 4,
          children: [
            FaIcon(
              AppIcons.role(role.value),
              size: 12,
              color: _getRoleColor(role),
            ),
            Text(
              role.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: _getRoleColor(role),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _getRoleColor(role).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _getRoleColor(role).withValues(alpha: 0.3)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 2,
        children: [
          FaIcon(
            AppIcons.role(role.value),
            size: 18,
            color: _getRoleColor(role),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                role.modeName,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: _getRoleColor(role),
                ),
              ),
              Text(
                role.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _getRoleColor(role).withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.visitor:
        return AppColors.savannahGreen;
      case UserRole.contributor:
        return AppColors.terracotta;
      case UserRole.institutionManager:
        return AppColors.ochre;
      case UserRole.admin:
        return AppColors.charcoal;
    }
  }
}
