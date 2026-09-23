import 'package:flutter/material.dart';

import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../models/user_model.dart';

/// The reader's current role/mode summary. Modes are managed on the server,
/// so this is informational only.
class RoleSwitcher extends StatelessWidget {
  const RoleSwitcher({super.key, required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentRole = user.role;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.role(currentRole.value), size: 26),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentRole.modeName,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      _getRoleDescription(currentRole),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (currentRole == UserRole.visitor) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Want to share your own stories? Upgrade to Contributor.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getRoleDescription(UserRole role) {
    switch (role) {
      case UserRole.visitor:
        return 'Browse and read stories from the collection';
      case UserRole.contributor:
        return 'Submit and share your own cultural stories';
      case UserRole.institutionManager:
        return 'Manage museum artifacts and QR code engines';
      case UserRole.admin:
        return 'Full platform administration access';
    }
  }
}
