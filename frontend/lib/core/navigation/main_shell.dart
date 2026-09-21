import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/artifacts/screens/artifacts_screen.dart';
import '../../features/gamification/screens/gamification_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/library/screens/library_screen.dart';
import '../../features/stories/screens/stories_screen.dart';
import '../theme/app_icons.dart';
import '../theme/app_spacing.dart';

/// Destination in the bottom bar.
class _Destination {
  const _Destination({
    required this.icon,
    required this.label,
    required this.builder,
  });

  final FaIconData icon;
  final String label;
  final WidgetBuilder builder;
}

/// Shell widget that provides the persistent bottom navigation bar.
///
/// Destinations and their order mirror the webapp's bottom bar exactly
/// (`templates/web/partials/nav_items.html`): **Home, Stories, Artifacts,
/// Library, Rewards**. The app previously had `Profile` in the bar and no
/// Artifacts destination at all, even though the web has both — Profile now
/// lives in the Home header avatar, where it already had a button.
///
/// The bar itself follows the supplied UI-model reference: a floating, rounded,
/// label-light bar with a notched centre and an elevated circular accent button.
/// The centre slot is Artifacts (the app's museum/heritage hub), and QR scanning
/// lives on that screen's header — one tap from the tab.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _currentIndex = 0;

  /// Pages are cached so tab state survives switches.
  late final List<_Destination> _destinations = [
    _Destination(
      icon: AppIcons.explore,
      label: 'Home',
      builder: (_) => const HomeScreen(),
    ),
    _Destination(
      icon: AppIcons.auto_stories,
      label: 'Stories',
      builder: (_) => const StoriesScreen(),
    ),
    _Destination(
      icon: AppIcons.museum,
      label: 'Artifacts',
      builder: (_) => const ArtifactsScreen(),
    ),
    _Destination(
      icon: AppIcons.bookmark,
      label: 'Library',
      builder: (_) => const LibraryScreen(),
    ),
    _Destination(
      icon: AppIcons.emoji_events_outlined,
      label: 'Rewards',
      builder: (_) => const GamificationScreen(),
    ),
  ];

  /// Index of the destination rendered as the elevated centre button.
  static const int _centreIndex = 2;

  /// Pages, created the first time their tab is opened and kept alive after.
  ///
  /// Building all five eagerly would mount every screen at launch, so each tab
  /// would fire its own database/network load before the user ever visits it
  /// (an offstage indeterminate spinner also never lets a widget test settle).
  late final List<Widget?> _pages =
      List<Widget?>.filled(_destinations.length, null);

  /// The page for [index], built on first use.
  Widget _pageAt(int index) =>
      _pages[index] ??= Builder(builder: _destinations[index].builder);

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.lightImpact();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (var i = 0; i < _destinations.length; i++)
            // Indexes must stay stable, so unvisited tabs hold a placeholder
            // until they are opened for the first time.
            if (i == _currentIndex || _pages[i] != null)
              _pageAt(i)
            else
              const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: _NotchedNavBar(
        destinations: _destinations,
        currentIndex: _currentIndex,
        centreIndex: _centreIndex,
        onSelected: _onTabTapped,
        background: scheme.surface,
        border: scheme.outline,
        accent: scheme.primary,
        inactive: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// Floating navigation bar with a notched centre and an elevated action.
class _NotchedNavBar extends StatelessWidget {
  const _NotchedNavBar({
    required this.destinations,
    required this.currentIndex,
    required this.centreIndex,
    required this.onSelected,
    required this.background,
    required this.border,
    required this.accent,
    required this.inactive,
  });

  final List<_Destination> destinations;
  final int currentIndex;
  final int centreIndex;
  final ValueChanged<int> onSelected;
  final Color background;
  final Color border;
  final Color accent;
  final Color inactive;

  static const double _barHeight = 64;
  static const double _raisedSize = AppSizes.navActionSize;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm + bottomInset,
      ),
      child: SizedBox(
        height: _barHeight + _raisedSize * 0.32,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // The bar itself.
            Container(
              height: _barHeight,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadius.hero),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: i == centreIndex
                          // Space reserved for the raised centre button.
                          ? const SizedBox.shrink()
                          : _NavSlot(
                              icon: destinations[i].icon,
                              label: destinations[i].label,
                              isSelected: i == currentIndex,
                              accent: accent,
                              inactive: inactive,
                              onTap: () => onSelected(i),
                            ),
                    ),
                ],
              ),
            ),
            // The elevated centre action, sitting in the notch.
            Positioned(
              bottom: _barHeight - _raisedSize * 0.42,
              child: _RaisedNavAction(
                icon: destinations[centreIndex].icon,
                label: destinations[centreIndex].label,
                isSelected: currentIndex == centreIndex,
                size: _raisedSize,
                accent: accent,
                background: background,
                border: border,
                onTap: () => onSelected(centreIndex),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One standard (non-centre) destination.
class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.accent,
    required this.inactive,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final bool isSelected;
  final Color accent;
  final Color inactive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.hero),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(icon, size: 20, color: isSelected ? accent : inactive),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: isSelected ? accent : inactive,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The elevated circular centre action.
class _RaisedNavAction extends StatelessWidget {
  const _RaisedNavAction({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.size,
    required this.accent,
    required this.background,
    required this.border,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final bool isSelected;
  final double size;
  final Color accent;
  final Color background;
  final Color border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected ? background : accent;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? accent : background,
                border: Border.all(
                  color: isSelected ? accent : accent.withValues(alpha: 0.45),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: FaIcon(icon, size: 22, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
