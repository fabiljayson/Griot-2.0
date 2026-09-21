import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/settings_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/app_components.dart';
import '../../core/widgets/griot_image.dart';
import '../../core/widgets/griot_loader.dart';
import '../../core/widgets/griot_logo.dart';
import '../auth/models/user_model.dart';
import '../auth/providers/auth_provider.dart';
import '../auth/screens/profile_screen.dart';
import '../auth/widgets/role_badge.dart';
import '../discover/discover_feature.dart';
import '../library/widgets/continue_reading_widget.dart';
import '../stories/models/story_model.dart';
import '../stories/providers/story_provider.dart';
import '../stories/screens/stories_screen.dart';
import '../stories/screens/story_detail_screen.dart';
import 'widgets/connectivity_status_widget.dart';
import 'widgets/offline_story_counter.dart';

/// Landing screen — the first impression of the Griot 2.0 app.
///
/// All content is read from the local data layer (previously this screen
/// carried two hardcoded demo lists that duplicated the story repository and
/// was the only place covers appeared to work).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isEnglish = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storyListProvider.notifier).loadStories(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final authState = ref.watch(authProvider);
    final user = authState.maybeWhen(
      data: (s) => s.user,
      orElse: () => null,
    );
    final stories = _storiesFrom(ref.watch(storyListProvider));
    final regionsAsync = ref.watch(regionListProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await ref.read(storyListProvider.notifier).loadStories(refresh: true);
          ref.invalidate(regionListProvider);
        },
        child: CustomScrollView(
          key: const ValueKey('homeScroll'),
          slivers: [
            SliverToBoxAdapter(
              child: _buildHeader(context, theme, ref, user),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? AppSpacing.gutterWide : AppSpacing.lg,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: AppSpacing.xl),

                  // --- Hero text ---
                  Text(
                    _isEnglish
                        ? "Journey through Cameroon's living heritage"
                        : "Voyage à travers l'héritage vivant du Cameroun",
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _isEnglish
                        ? 'Tales carried by griots, preserved for generations. '
                              'Read, listen, and explore the voices of the '
                              'motherland.'
                        : 'Contes transmis par les griots, préservés depuis des '
                              'générations. Lisez, écoutez et explorez les voix '
                              'de la mère patrie.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),

                  // --- Continue reading (only when there is progress) ---
                  const ContinueReadingWidget(),

                  // --- Trending ---
                  if (stories.isNotEmpty) ...[
                    SectionHeader(
                      title: _isEnglish ? 'Trending Now' : 'Tendances',
                      icon: AppIcons.trending_up,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: 236,
                      child: _TrendingStrip(
                        stories: _trending(stories),
                        onOpen: _openStory,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.section),
                  ],

                  // --- Category browse ---
                  const _CategoryStrip(),
                  const SizedBox(height: AppSpacing.section),

                  // --- Popular stories ---
                  SectionHeader(
                    title: _isEnglish
                        ? 'Popular Stories'
                        : 'Histoires Populaires',
                    icon: AppIcons.favorite,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ..._buildStoryList(theme, scheme, stories),

                  const SizedBox(height: AppSpacing.section),

                  // --- Discover regions ---
                  SectionHeader(
                    title: _isEnglish
                        ? 'Discover Regions'
                        : 'Découvrir les Régions',
                    icon: AppIcons.explore,
                    trailing: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StoriesScreen(),
                        ),
                      ),
                      child: const Text('See all'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 176,
                    child: regionsAsync.when(
                      data: (regions) => regions.isEmpty
                          ? const EmptyState(
                              title: 'No regions yet',
                              icon: AppIcons.explore,
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: regions.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: AppSpacing.md),
                              itemBuilder: (context, index) {
                                final region = regions[index];
                                return RegionCard(
                                  region: region,
                                  onTap: () => _openRegion(region.slug),
                                );
                              },
                            ),
                      loading: () => const Center(child: GriotLoader()),
                      error: (error, _) => ErrorState(message: '$error'),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.sectionLarge),

                  // --- Offline/library status (secondary, below the fold) ---
                  const OfflineStoryCounter(),
                  const SizedBox(height: AppSpacing.md),
                  const ConnectivityStatusWidget(),
                  const SizedBox(height: AppSpacing.sectionLarge),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<StoryModel> _storiesFrom(StoryListState state) => switch (state) {
    StoryListReady(:final stories) => stories,
    StoryListLoading(:final stories) => stories,
    StoryListFailure(:final stories) => stories,
    _ => const <StoryModel>[],
  };

  List<StoryModel> _trending(List<StoryModel> stories) {
    final sorted = [...stories]
      ..sort((a, b) => b.viewCount.compareTo(a.viewCount));
    return sorted.take(5).toList();
  }

  List<StoryModel> _popular(List<StoryModel> stories) {
    final sorted = [...stories]
      ..sort((a, b) => b.likeCount.compareTo(a.likeCount));
    return sorted.take(4).toList();
  }

  List<Widget> _buildStoryList(
    ThemeData theme,
    ColorScheme scheme,
    List<StoryModel> stories,
  ) {
    if (stories.isEmpty) {
      return [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              FaIcon(
                AppIcons.auto_stories_outlined,
                size: 32,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No stories available yet.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ];
    }

    return _popular(stories)
        .map(
          (story) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _CompactStoryRow(
              story: story,
              onTap: () => _openStory(story.slug),
            ),
          ),
        )
        .toList();
  }

  void _openStory(String slug) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoryDetailScreen(slug: slug)),
    );
  }

  void _openRegion(String slug) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RegionStoriesScreen(regionSlug: slug)),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    UserModel? user,
  ) {
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      decoration: const BoxDecoration(gradient: AppColors.brandGradientWide),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: GriotLogo(size: 44, light: true)),
              IconButton(
                tooltip: 'Toggle theme',
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .toggleDarkMode(
                      systemBrightness: MediaQuery.of(
                        context,
                      ).platformBrightness,
                    ),
                icon: const FaIcon(AppIcons.dark_mode_outlined),
                color: AppColors.ivory,
              ),
              if (user != null)
                IconButton(
                  tooltip: 'Profile',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProfileScreen(),
                      ),
                    );
                  },
                  icon: const FaIcon(AppIcons.account_circle_outlined),
                  color: AppColors.ivory,
                ),
            ],
          ),
          if (user != null) ...[
            const SizedBox(height: AppSpacing.md),
            RoleBadge(role: user.role),
          ],
          const SizedBox(height: AppSpacing.lg),
          _LanguageToggle(
            isEnglish: _isEnglish,
            onChanged: (value) => setState(() => _isEnglish = value),
            scheme: scheme,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Trending strip
// ═══════════════════════════════════════════════════════════════════════

class _TrendingStrip extends StatelessWidget {
  const _TrendingStrip({required this.stories, required this.onOpen});

  final List<StoryModel> stories;
  final void Function(String slug) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: stories.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
      itemBuilder: (context, index) {
        final story = stories[index];
        return SizedBox(
          width: 240,
          child: AppCard(
            padding: EdgeInsets.zero,
            elevated: true,
            onTap: () => onOpen(story.slug),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    GriotCoverImage(
                      source: story.coverImage,
                      blurhash: story.coverImageBlurhash,
                      aspectRatio: 16 / 9,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.card),
                      ),
                      semanticLabel: story.title,
                    ),
                    Positioned(
                      top: AppSpacing.sm,
                      left: AppSpacing.sm,
                      child: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.bronze,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${index + 1}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.charcoal,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          story.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            FaIcon(
                              AppIcons.remove_red_eye_outlined,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              story.formattedViewCount,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            FaIcon(
                              AppIcons.favorite_outline,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              story.formattedLikeCount,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Compact list row (popular stories)
// ═══════════════════════════════════════════════════════════════════════

class _CompactStoryRow extends StatelessWidget {
  const _CompactStoryRow({required this.story, required this.onTap});

  final StoryModel story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          GriotImage(
            source: story.coverImage,
            width: 64,
            height: 64,
            blurhash: story.coverImageBlurhash,
            semanticLabel: story.title,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            placeholderIcon: AppIcons.auto_stories_outlined,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${story.author.displayName} • ${story.readTimeDisplay}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          FaIcon(
            AppIcons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
            size: 16,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Category strip
// ═══════════════════════════════════════════════════════════════════════

class _CategoryStrip extends ConsumerWidget {
  const _CategoryStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return categoriesAsync.when(
      data: (categories) {
        if (categories.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Browse by Category',
              icon: AppIcons.layerGroup,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: categories
                  .map(
                    (category) => MetadataPill(
                      // Real icon instead of the stored emoji glyph.
                      icon: AppIcons.fromEmoji(category.icon),
                      label: category.name,
                      color: AppColors.bronze,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StoriesScreen(),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Language toggle
// ═══════════════════════════════════════════════════════════════════════

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({
    required this.isEnglish,
    required this.onChanged,
    required this.scheme,
  });

  final bool isEnglish;
  final ValueChanged<bool> onChanged;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.onPrimary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LanguageChip(
            label: 'EN',
            isSelected: isEnglish,
            onTap: () => onChanged(true),
          ),
          _LanguageChip(
            label: 'FR',
            isSelected: !isEnglish,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.ivory : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isSelected ? AppColors.indigo : AppColors.ivory,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
