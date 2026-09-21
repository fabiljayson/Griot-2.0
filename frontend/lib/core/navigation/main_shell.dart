import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/home_screen.dart';
import '../../features/stories/screens/stories_screen.dart';
import '../../features/library/screens/library_screen.dart';
import '../../features/gamification/screens/gamification_screen.dart';
import '../../features/auth/screens/profile_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

/// Shell widget that provides a persistent bottom navigation bar
/// with 5 tabs: Home, Stories, Library, Gamification, Profile.
///
/// Uses [IndexedStack] to preserve tab state across switches.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  /// Cache pages to avoid rebuilding on every switch.
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = const [
      HomeScreen(),
      StoriesScreen(),
      LibraryScreen(),
      GamificationScreen(),
      ProfileScreen(),
    ];
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) {
      // Tapping the active tab — could scroll to top.
      return;
    }
    // Light haptic feedback on tab switch.
    HapticFeedback.lightImpact();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTapped,
        backgroundColor: scheme.surface,
        indicatorColor: AppColors.terracotta.withValues(alpha: 0.12),
        elevation: 2,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: FaIcon(AppIcons.explore, size: 24),
            selectedIcon: FaIcon(AppIcons.explore, size: 24, color: AppColors.terracotta),
            label: 'Home',
          ),
          NavigationDestination(
            icon: FaIcon(AppIcons.auto_stories_outlined, size: 24),
            selectedIcon: FaIcon(AppIcons.auto_stories, size: 24, color: AppColors.terracotta),
            label: 'Stories',
          ),
          NavigationDestination(
            icon: FaIcon(AppIcons.menu_book_outlined, size: 24),
            selectedIcon: FaIcon(AppIcons.menu_book_outlined, size: 24, color: AppColors.terracotta),
            label: 'Library',
          ),
          NavigationDestination(
            icon: FaIcon(AppIcons.emoji_events_outlined, size: 24),
            selectedIcon: FaIcon(AppIcons.emoji_events_outlined, size: 24, color: AppColors.terracotta),
            label: 'Achieve',
          ),
          NavigationDestination(
            icon: FaIcon(AppIcons.person_outline, size: 24),
            selectedIcon: FaIcon(AppIcons.person_outline, size: 24, color: AppColors.terracotta),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
