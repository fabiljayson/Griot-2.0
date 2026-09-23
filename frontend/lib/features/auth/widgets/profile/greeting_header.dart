import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/griot_logo.dart';
import '../../models/user_model.dart';
import '../role_badge.dart';

/// Brand + greeting band, mirroring the reference screen's header row
/// (avatar and a single trailing action beside a greeting and the date).
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    super.key,
    required this.user,
    required this.isEditing,
    required this.onEditToggle,
  });

  final UserModel user;
  final bool isEditing;
  final VoidCallback onEditToggle;

  /// Time-aware greeting, matching the reference's "Good evening, …".
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _today {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, '
        '${months[now.month - 1]} ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: AppColors.indigo,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: GriotLogo(size: 40, light: true)),
              IconButton(
                tooltip: isEditing ? 'Cancel editing' : 'Edit profile',
                onPressed: onEditToggle,
                icon: Icon(isEditing ? AppIcons.close : AppIcons.edit_outlined),
                color: AppColors.ivory,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bronze.withValues(alpha: 0.16),
                  border: Border.all(
                    color: AppColors.bronzeLight.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Icon(
                    AppIcons.role(user.role.value),
                    size: 26,
                    color: AppColors.bronzeLight,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_greeting, ${user.displayName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.ivory,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _today,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.ivory.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RoleBadge(role: user.role),
        ],
      ),
    );
  }
}
