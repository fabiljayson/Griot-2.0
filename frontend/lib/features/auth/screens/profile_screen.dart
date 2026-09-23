import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/griot_loader.dart';
import '../../../core/widgets/griot_splash_screen.dart';
import '../../admin/admin_feature.dart';
import '../../settings/screens/settings_screen.dart';
import '../../gamification/providers/gamification_provider.dart';
import '../../stories/screens/story_form_screen.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../widgets/profile/action_tile.dart';
import '../widgets/profile/explore_rail.dart';
import '../widgets/profile/greeting_header.dart';
import '../widgets/profile/info_tile.dart';
import '../widgets/profile/journey_block.dart';
import '../widgets/profile/role_switcher.dart';
import '../widgets/profile/section_title.dart';

/// Profile / account screen.
///
/// Laid out after the supplied profile reference: a greeting header, a
/// "Your journey" block (level, XP and reading streak), and an Explore rail of
/// story categories — followed by the account, mode and administration
/// sections that were already here.
///
/// Reached as a pushed route from the Home header, so the screen owns its
/// [Scaffold] and [SafeArea]; a pushed instance previously rendered with no
/// background and ran under the status bar.
///
/// Features kept intact:
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
    final user = ref
        .read(authProvider)
        .maybeWhen(data: (s) => s.user, orElse: () => null);
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
    final user = authState.maybeWhen(data: (s) => s.user, orElse: () => null);

    if (user == null) {
      return const Scaffold(body: GriotLoadingState());
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(gamificationProfileProvider),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: GreetingHeader(
                  user: user,
                  isEditing: _isEditing,
                  onEditToggle: () {
                    setState(() {
                      _isEditing = !_isEditing;
                      if (!_isEditing) {
                        _firstNameController.text = user.firstName;
                        _lastNameController.text = user.lastName;
                      }
                    });
                  },
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // --- Your journey: level, XP and reading streak ---
                    const JourneyBlock(),
                    const SizedBox(height: AppSpacing.section),

                    // --- Explore rail ---
                    const ExploreRail(),
                    const SizedBox(height: AppSpacing.section),

                    // --- Edit profile section ---
                    if (_isEditing) ...[
                      SectionTitle(title: 'Edit Profile'),
                      const SizedBox(height: AppSpacing.md),
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
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: TextFormField(
                              controller: _lastNameController,
                              decoration: const InputDecoration(
                                labelText: 'Last Name',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
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
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // --- Account info ---
                    SectionTitle(title: 'Account Information'),
                    const SizedBox(height: AppSpacing.md),
                    InfoTile(
                      icon: AppIcons.person_outline,
                      label: 'Username',
                      value: user.username,
                    ),
                    InfoTile(
                      icon: AppIcons.email_outlined,
                      label: 'Email',
                      value: user.email,
                    ),
                    if (user.institution.isNotEmpty)
                      InfoTile(
                        icon: AppIcons.business_outlined,
                        label: 'Institution',
                        value: user.institution,
                      ),
                    InfoTile(
                      icon: AppIcons.calendar_today,
                      label: 'Member Since',
                      value: _formatDate(user.dateJoined),
                    ),
                    const SizedBox(height: AppSpacing.section),

                    // --- Role switcher ---
                    SectionTitle(title: 'Current Mode'),
                    const SizedBox(height: AppSpacing.md),
                    RoleSwitcher(user: user),
                    const SizedBox(height: AppSpacing.section),

                    // --- Settings ---
                    SectionTitle(title: 'Settings'),
                    const SizedBox(height: AppSpacing.md),
                    ActionTile(
                      icon: AppIcons.settings_outlined,
                      label: 'Settings',
                      color: theme.colorScheme.primary,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.section),

                    // --- Contributor studio ---
                    if (user.role != UserRole.visitor) ...[
                      SectionTitle(title: 'Contributor Studio'),
                      const SizedBox(height: AppSpacing.md),
                      ActionTile(
                        icon: AppIcons.edit_outlined,
                        label: 'Write a Story',
                        color: AppColors.accentTextStrong,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const StoryFormScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.section),
                    ],

                    // --- Admin dashboard (admins & institution managers) ---
                    if (user.role == UserRole.admin ||
                        user.role == UserRole.institutionManager) ...[
                      SectionTitle(title: 'Administration'),
                      const SizedBox(height: AppSpacing.md),
                      ActionTile(
                        icon: AppIcons.insights_outlined,
                        label: 'Admin Dashboard',
                        color: AppColors.accentTextStrongGreen,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AdminDashboardScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.section),
                    ],

                    // --- Danger zone ---
                    SectionTitle(title: 'Danger Zone'),
                    const SizedBox(height: AppSpacing.md),
                    ActionTile(
                      icon: AppIcons.logout,
                      label: 'Sign Out',
                      // Neutral, not destructive: signing out loses no data.
                      // Only "Delete Account" uses the error tone.
                      color: theme.colorScheme.onSurface,
                      onTap: () async {
                        final confirmed = await _showConfirmDialog(
                          context,
                          title: 'Sign Out',
                          message: 'Are you sure you want to sign out?',
                          confirmLabel: 'Sign Out',
                        );
                        if (confirmed && context.mounted) {
                          // Replay the branded splash while the session closes,
                          // so sign-out reads as the mirror of app load.
                          await GriotSplashScreen.showAndRun(
                            context,
                            caption: 'See you soon',
                            action: () =>
                                ref.read(authProvider.notifier).logout(),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ActionTile(
                      icon: AppIcons.delete_forever,
                      label: 'Delete Account & Data',
                      color: AppColors.error,
                      onTap: () => _showDeleteAccountDialog(context, user),
                    ),
                    const SizedBox(height: AppSpacing.section),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, UserModel user) {
    final theme = Theme.of(context);
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(
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
            const SizedBox(height: AppSpacing.md),
            Text(
              'All your data including saved stories, reading progress, '
              'and contributions will be permanently deleted.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Type "${user.username}" to confirm:',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
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
