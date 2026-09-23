import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/models/user_model.dart';
import '../models/analytics_models.dart';
import '../providers/admin_provider.dart';
import 'dashboard_section.dart';

/// All platform accounts (local + deployed) on the admin dashboard.
///
/// Consumes `adminUsersProvider`, which lists every user in the backend after
/// `sync_local_users` has combined the local SQLite database with the
/// deployed PostgreSQL database.
class PlatformUsersSection extends ConsumerWidget {
  const PlatformUsersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usersAsync = ref.watch(adminUsersProvider);

    return DashboardSection(
      title: 'Platform users',
      subtitle: 'All accounts, local & deployed',
      child: usersAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Text(
          'Users unavailable right now.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        data: (users) {
          if (users.isEmpty) {
            return Text(
              'No accounts registered yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            );
          }
          return Column(
            children: [
              for (final user in users) _UserRow(user: user),
            ],
          );
        },
      ),
    );
  }
}

/// One account row: initials avatar, name, email and role badge.
class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = user.isActive
        ? AppColors.savannahGreen
        : AppColors.charcoalMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _avatarColor(user.role).withValues(alpha: 0.18),
            child: Text(
              _initials(user),
              style: theme.textTheme.labelSmall?.copyWith(
                color: _avatarColor(user.role),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!user.isActive) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Inactive',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  user.email.isNotEmpty
                      ? '${user.username} · ${user.email}'
                      : user.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: activeColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              UserRole.fromString(user.role).label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: activeColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(AdminUser user) {
    final parts = user.displayName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _avatarColor(String role) {
    switch (role) {
      case 'admin':
        return AppColors.terracottaDark;
      case 'institution_manager':
        return AppColors.ochre;
      case 'contributor':
        return AppColors.savannahGreen;
      default:
        return AppColors.charcoalMuted;
    }
  }
}