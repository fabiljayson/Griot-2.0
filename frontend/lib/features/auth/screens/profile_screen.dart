import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_loader.dart';
import '../../../core/widgets/griot_logo.dart';
import '../../admin/admin_feature.dart';
import '../../gamification/providers/gamification_provider.dart';
import '../../stories/models/story_model.dart';
import '../../stories/providers/story_provider.dart';
import '../../stories/screens/stories_screen.dart';
import '../../stories/screens/story_form_screen.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../widgets/role_badge.dart';

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
                child: _GreetingHeader(
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
                    const _JourneyBlock(),
                    const SizedBox(height: AppSpacing.section),

                    // --- Explore rail ---
                    const _ExploreRail(),
                    const SizedBox(height: AppSpacing.section),

                    // --- Edit profile section ---
                    if (_isEditing) ...[
                      _SectionTitle(title: 'Edit Profile'),
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
                    _SectionTitle(title: 'Account Information'),
                    const SizedBox(height: AppSpacing.md),
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
                    const SizedBox(height: AppSpacing.section),

                    // --- Role switcher ---
                    _SectionTitle(title: 'Current Mode'),
                    const SizedBox(height: AppSpacing.md),
                    _RoleSwitcher(user: user),
                    const SizedBox(height: AppSpacing.section),

                    // --- Contributor studio ---
                    if (user.role != UserRole.visitor) ...[
                      _SectionTitle(title: 'Contributor Studio'),
                      const SizedBox(height: AppSpacing.md),
                      _ActionTile(
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
                      _SectionTitle(title: 'Administration'),
                      const SizedBox(height: AppSpacing.md),
                      _ActionTile(
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
                    _SectionTitle(title: 'Danger Zone'),
                    const SizedBox(height: AppSpacing.md),
                    _ActionTile(
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
                          await ref.read(authProvider.notifier).logout();
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ActionTile(
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

// ═══════════════════════════════════════════════════════════════════════
//  Greeting header
// ═══════════════════════════════════════════════════════════════════════

/// Brand + greeting band, mirroring the reference screen's header row
/// (avatar and a single trailing action beside a greeting and the date).
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({
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

// ═══════════════════════════════════════════════════════════════════════
//  Your journey
// ═══════════════════════════════════════════════════════════════════════

/// Level, XP progress and reading streak — the reference screen's hero block.
///
/// Every value comes from the local gamification store; nothing is mocked. The
/// weekly strip is derived from the stored streak (the last N days were read),
/// so it cannot show activity the reader did not have.
class _JourneyBlock extends ConsumerWidget {
  const _JourneyBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(gamificationProfileProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Your Journey', icon: AppIcons.medal),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: profileAsync.when(
            loading: () => const SizedBox(
              height: 96,
              child: Center(child: GriotLoader(size: 28)),
            ),
            error: (_, _) => _JourneyUnavailable(
              onRetry: () => ref.invalidate(gamificationProfileProvider),
            ),
            data: (profile) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${profile.currentStreak}',
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          profile.currentStreak == 1
                              ? 'Day streak'
                              : 'Days streak',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    Icon(AppIcons.fire, size: 22, color: AppColors.bronze),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Text(
                      'Level ${profile.level}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const Spacer(),
                    Text(
                      '${profile.totalXp}/${profile.xpForNextLevel} XP',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // Bar only: the level and XP label live in the row above, so
                // the value never overlaps or truncates.
                ProgressRow(fraction: profile.xpProgress, showValue: false),
                const SizedBox(height: AppSpacing.lg),
                _WeekStrip(streak: profile.currentStreak),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    _MiniStat(
                      icon: AppIcons.auto_stories_outlined,
                      value: '${profile.storiesRead}',
                      label: 'Read',
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    _MiniStat(
                      icon: AppIcons.quiz_outlined,
                      value: '${profile.quizzesPassed}',
                      label: 'Quizzes',
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    _MiniStat(
                      icon: AppIcons.emoji_events_outlined,
                      value: '${profile.badgesCount}',
                      label: 'Badges',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fallback when the local gamification profile cannot be read.
class _JourneyUnavailable extends StatelessWidget {
  const _JourneyUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          AppIcons.error_outline,
          size: 22,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            'Your journey is unavailable right now.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

/// Seven-day strip: the days the stored streak covers, up to today.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.streak});

  final int streak;

  static const _labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final todayIndex = DateTime.now().weekday - 1; // 0 = Monday
    final lit = streak.clamp(0, 7);
    final firstLit = todayIndex + 1 - lit;

    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _DayDot(
              label: _labels[i],
              isToday: i == todayIndex,
              isLit: i >= firstLit && i <= todayIndex,
            ),
          ),
        ],
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.isToday,
    required this.isLit,
  });

  final String label;
  final bool isToday;
  final bool isLit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Color fill = isLit
        ? (isToday ? AppColors.bronze : AppColors.bronzeTint)
        : Colors.transparent;
    final Color border = isLit
        ? AppColors.bronze
        : scheme.outline.withValues(alpha: 0.6);

    return Column(
      children: [
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: border),
          ),
          // A day the streak did not cover stays an empty slot rather than
          // borrowing a tick it did not earn.
          child: isLit
              ? const Center(
                  child: Icon(
                    AppIcons.check,
                    size: 13,
                    color: AppColors.charcoal,
                  ),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isToday ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Explore rail
// ═══════════════════════════════════════════════════════════════════════

/// Horizontal category rail, mirroring the reference's "Explore Categories".
class _ExploreRail extends ConsumerWidget {
  const _ExploreRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Explore', icon: AppIcons.explore),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 112,
          child: categoriesAsync.when(
            data: (categories) => categories.isEmpty
                ? const EmptyState(
                    title: 'No categories yet',
                    icon: AppIcons.layerGroup,
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (context, index) => _ExploreCard(
                      category: categories[index],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StoriesScreen(),
                        ),
                      ),
                    ),
                  ),
            loading: () => const Center(child: GriotLoader(size: 26)),
            error: (_, _) => const EmptyState(
              title: 'Categories unavailable',
              icon: AppIcons.layerGroup,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({required this.category, required this.onTap});

  final StoryCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 104,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.bronzeTint,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              // Real icon resolved from the stored glyph.
              child: Icon(
                AppIcons.fromEmoji(category.icon),
                size: 20,
                color: AppColors.accentTextStrong,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Settings groups
// ═══════════════════════════════════════════════════════════════════════

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

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.lg,
      ),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.error;

    return Material(
      color: effectiveColor.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: effectiveColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: effectiveColor, size: 20),
              const SizedBox(width: AppSpacing.md),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: effectiveColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(
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
