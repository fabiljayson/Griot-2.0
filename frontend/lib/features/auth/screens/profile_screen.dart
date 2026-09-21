import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/griot_loader.dart';
import '../../admin/admin_feature.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';

/// Profile/Account screen showing user info and settings.
///
/// Features:
/// - Display user profile with role badge
/// - Edit profile (name)
/// - Role switcher (Explorer Mode vs Contributor Studio)
/// - Delete account workflow with confirmation
/// - Logout
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).maybeWhen(
          data: (s) => s.user,
          orElse: () => null,
        );
    _firstNameController = TextEditingController(text: user?.firstName ?? '');
    _lastNameController = TextEditingController(text: user?.lastName ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final user = authState.maybeWhen(
      data: (s) => s.user,
      orElse: () => null,
    );

    if (user == null) {
      return const Scaffold(body: GriotLoadingState());
    }

    return Column(
      children: [
        // --- Header ---
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Profile',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: FaIcon(_isEditing ? AppIcons.close : AppIcons.edit_outlined),
                onPressed: () {
                  setState(() {
                    _isEditing = !_isEditing;
                    if (!_isEditing) {
                      _firstNameController.text = user.firstName;
                      _lastNameController.text = user.lastName;
                    }
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // --- Profile header ---
            Center(
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.terracotta.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.terracotta.withValues(alpha: 0.3),
                        width: 3,
                      ),
                    ),
                    child: Center(
                      child: FaIcon(AppIcons.role(user.role.value), size: 42),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(user.displayName, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.terracotta.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FaIcon(AppIcons.role(user.role.value), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          user.role.modeName,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.terracotta,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // --- Edit profile section ---
            if (_isEditing) ...[
              _SectionTitle(title: 'Edit Profile'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(labelText: 'Last Name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await ref
                        .read(authProvider.notifier)
                        .updateProfile(
                          firstName: _firstNameController.text.trim(),
                          lastName: _lastNameController.text.trim(),
                        );
                    if (mounted) {
                      setState(() => _isEditing = false);
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // --- Account info ---
            _SectionTitle(title: 'Account Information'),
            const SizedBox(height: 12),
            _InfoTile(
              icon: AppIcons.person_outline,
              label: 'Username',
              value: user.username,
            ),
            _InfoTile(
              icon: AppIcons.email_outlined,
              label: 'Email',
              value: user.email,
            ),
            if (user.institution.isNotEmpty)
              _InfoTile(
                icon: AppIcons.business_outlined,
                label: 'Institution',
                value: user.institution,
              ),
            _InfoTile(
              icon: AppIcons.calendar_today,
              label: 'Member Since',
              value: _formatDate(user.dateJoined),
            ),
            const SizedBox(height: 32),

            // --- Role switcher ---
            _SectionTitle(title: 'Current Mode'),
            const SizedBox(height: 12),
            _RoleSwitcher(user: user),
            const SizedBox(height: 32),

            // --- Admin dashboard (admins & institution managers) ---
            if (user.role == UserRole.admin ||
                user.role == UserRole.institutionManager) ...[
              _SectionTitle(title: 'Administration'),
              const SizedBox(height: 12),
              _ActionTile(
                icon: AppIcons.insights_outlined,
                label: 'Admin Dashboard',
                color: AppColors.savannahGreen,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminDashboardScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
            ],

            // --- Danger zone ---
            _SectionTitle(title: 'Danger Zone'),
            const SizedBox(height: 12),
            _ActionTile(
              icon: AppIcons.logout,
              label: 'Sign Out',
              // Neutral, not destructive: signing out loses no data. Only
              // "Delete Account" uses the error tone.
              color: theme.colorScheme.onSurface,
              onTap: () async {
                final confirmed = await _showConfirmDialog(
                  context,
                  title: 'Sign Out',
                  message: 'Are you sure you want to sign out?',
                  confirmLabel: 'Sign Out',
                );
                if (confirmed && context.mounted) {
                  await ref.read(authProvider.notifier).logout();
                }
              },
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: AppIcons.delete_forever,
              label: 'Delete Account & Data',
              color: AppColors.error,
              onTap: () => _showDeleteAccountDialog(context, user),
            ),            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
      ],
    );
  }


  void _showDeleteAccountDialog(BuildContext context, UserModel user) {
    final theme = Theme.of(context);
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const FaIcon(
          AppIcons.warning_amber_rounded,
          color: AppColors.error,
          size: 48,
        ),
        title: const Text('Delete Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This action is permanent and cannot be undone.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'All your data including saved stories, reading progress, '
              'and contributions will be permanently deleted.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Type "${user.username}" to confirm:',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              decoration: InputDecoration(
                hintText: user.username,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              confirmController.dispose();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              if (confirmController.text == user.username) {
                confirmController.dispose();
                Navigator.of(context).pop();
                await ref.read(authProvider.notifier).deleteAccount();
              }
            },
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return 'Unknown';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final FaIconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          FaIcon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleSwitcher extends StatelessWidget {
  const _RoleSwitcher({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentRole = user.role;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FaIcon(AppIcons.role(currentRole.value), size: 26),
              const SizedBox(width: 12),
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
            const SizedBox(height: 12),
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final FaIconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.error;

    return Material(
      color: effectiveColor.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: effectiveColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              FaIcon(icon, color: effectiveColor, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: effectiveColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              FaIcon(
                AppIcons.chevron_right,
                color: effectiveColor.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
