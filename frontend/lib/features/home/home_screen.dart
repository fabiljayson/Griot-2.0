import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/settings_providers.dart';
import '../../core/theme/app_colors.dart';
import '../stories/models/story_model.dart';
import '../stories/screens/story_detail_screen.dart';
import '../auth/models/user_model.dart';
import '../auth/providers/auth_provider.dart';
import '../auth/screens/profile_screen.dart';
import '../auth/widgets/role_badge.dart';
import '../sharing/widgets/trending_stories_widget.dart';
import '../../core/widgets/griot_logo.dart';
import 'widgets/connectivity_status_widget.dart';
import 'widgets/offline_story_counter.dart';
import '../../core/theme/app_icons.dart';

/// Landing screen — the first impression of the Griot 2.0 app.
///
/// Features:
/// - Language toggle (EN/FR)
/// - Curated feeds (Trending, Popular, Discover)
/// - User role badge
/// - OfflineStoryCounter
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isEnglish = true;

  // Placeholder data for the design showcase — wire the stories feed
  // provider here once discovery (fuzzy search + masonry grid) lands.
  final List<StoryModel> _trendingStories = [
    const StoryModel(
      id: 1,
      title: 'The Spider\'s Gift: Anansi and the Wisdom Pot',
      slug: 'anansi-wisdom-pot',
      summary: 'How Anansi tried to hoard all the world\'s wisdom.',
      author: UserModel(
        id: 1,
        username: 'griot_ama',
        firstName: 'Ama',
        lastName: 'Ata',
      ),
      region: 'Grassfields',
      coverImage: 'assets/imagery/stories/anansi-wisdom-pot.jpg',
      estimatedReadTime: 5,
      likeCount: 234,
      viewCount: 1200,
      categories: [StoryCategory(id: 1, name: 'Folktales')],
    ),
    const StoryModel(
      id: 2,
      title: 'The Lion\'s Bath: A Tale from the Bamoun Kingdom',
      slug: 'lions-bath',
      summary: 'A clever rabbit outsmarts the lion king.',
      author: UserModel(
        id: 2,
        username: 'kofi_duma',
        firstName: 'Kofi',
        lastName: 'Duma',
      ),
      region: 'Bamoun',
      coverImage: 'assets/imagery/stories/lions-bath.jpg',
      estimatedReadTime: 8,
      likeCount: 189,
      viewCount: 980,
      categories: [StoryCategory(id: 2, name: 'Myths')],
    ),
    const StoryModel(
      id: 3,
      title: 'The Talking Drum of Foumban',
      slug: 'talking-drum-foumban',
      summary: 'The drum that spoke the truth to the people.',
      author: UserModel(
        id: 3,
        username: 'nana_yemo',
        firstName: 'Nana',
        lastName: 'Yemo',
      ),
      region: 'Bamoun',
      coverImage: 'assets/imagery/stories/talking-drum-foumban.jpg',
      estimatedReadTime: 12,
      likeCount: 312,
      viewCount: 1500,
      categories: [StoryCategory(id: 3, name: 'Legends')],
    ),
  ];

  final List<StoryModel> _popularStories = [
    const StoryModel(
      id: 4,
      title: 'The River Goddess of the Sanaga',
      slug: 'river-goddess',
      summary: 'A fisherman\'s encounter with the spirit of the water.',
      author: UserModel(
        id: 4,
        username: 'mami_wata',
        firstName: 'Sarah',
        lastName: 'Biya',
      ),
      region: 'Coastal',
      estimatedReadTime: 10,
      likeCount: 456,
      viewCount: 2300,
      categories: [StoryCategory(id: 4, name: 'Legends')],
    ),
    const StoryModel(
      id: 5,
      title: 'Why the Chameleon Changes Color',
      slug: 'chameleon-color',
      summary: 'A cautionary tale about greed and transformation.',
      author: UserModel(
        id: 5,
        username: 'papa_mbei',
        firstName: 'Papa',
        lastName: 'Mbei',
      ),
      region: 'Adamawa',
      estimatedReadTime: 4,
      likeCount: 178,
      viewCount: 890,
      categories: [StoryCategory(id: 1, name: 'Folktales')],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final authState = ref.watch(authProvider);
    final user = authState.maybeWhen(
      data: (s) => s.user,
      orElse: () => null,
    );

    return SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // Refresh is a no-op for local data, but provides UX feedback.
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: CustomScrollView(
          key: const ValueKey('homeScroll'),
          slivers: [
            // --- Header ---
            SliverToBoxAdapter(
              child: _buildHeader(context, theme, scheme, user),
            ),

            // --- Content ---
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // --- Language Toggle & Offline Counter ---
                  const SizedBox(height: 24),
                  _buildLanguageToggle(context, theme, scheme),
                  const SizedBox(height: 16),
                  const OfflineStoryCounter(),
                  const SizedBox(height: 16),
                  ConnectivityStatusWidget(),
                  const SizedBox(height: 32),

                  // --- Hero Text ---
                  Text(
                    _isEnglish
                        ? 'Journey through Cameroon\'s living heritage'
                        : 'Voyage à travers l\'héritage vivant du Cameroun',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isEnglish
                        ? 'Tales carried by griots, preserved for generations. Read, listen, and explore the voices of the motherland.'
                        : 'Contes transmis par les griots, préservés depuis des générations. Lisez, écoutez et explorez les voix de la mère patrie.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // --- Trending Section ---
                  _SectionHeader(
                    title: _isEnglish ? 'Trending Now' : 'Tendances',
                    icon: AppIcons.trending_up,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: TrendingStoriesWidget(stories: _trendingStories),
                  ),
                  const SizedBox(height: 32),

                  // --- Popular Section ---
                  _SectionHeader(
                    title: _isEnglish
                        ? 'Popular Stories'
                        : 'Histoires Populaires',
                    icon: AppIcons.favorite,
                  ),
                  const SizedBox(height: 12),
                  ...(_popularStories.map(
                    (story) => _StoryCard(
                      story: story,
                      onTap: () => _navigateToStory(context, story.slug),
                    ),
                  )),
                  const SizedBox(height: 32),

                  // --- Discover Regions ---
                  _SectionHeader(
                    title: _isEnglish
                        ? 'Discover Regions'
                        : 'Découvrir les Régions',
                    icon: AppIcons.explore,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _RegionChip(
                          icon: AppIcons.museum_outlined,
                          label: 'Bamoun',
                          color: AppColors.terracotta,
                        ),
                        const SizedBox(width: 12),
                        _RegionChip(
                          icon: AppIcons.explore,
                          label: 'Adamawa',
                          color: AppColors.ochre,
                        ),
                        const SizedBox(width: 12),
                        _RegionChip(
                          icon: AppIcons.place_outlined,
                          label: 'Coastal',
                          color: AppColors.savannahGreen,
                        ),
                        const SizedBox(width: 12),
                        _RegionChip(
                          icon: AppIcons.location_on,
                          label: 'Grassfields',
                          color: AppColors.terracottaDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                ]),
              ),
            ),
          ],
        ),
        ),
      );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    UserModel? user,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.8)],
        ),
      ),
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
                color: AppColors.surfaceLight,
              ),
              if (user != null)
                IconButton(
                  tooltip: 'Profile',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  icon: const FaIcon(AppIcons.account_circle_outlined),
                  color: AppColors.surfaceLight,
                ),
            ],
          ),
          // AuthWrapper gates this screen behind login, so a signed-in
          // user is always present here.
          if (user != null) ...[
            const SizedBox(height: 12),
            RoleBadge(role: user.role),
          ],
        ],
      ),
    );
  }

  Widget _buildLanguageToggle(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 4,
        children: [
          _LanguageChip(
            label: 'EN',
            isSelected: _isEnglish,
            onTap: () => setState(() => _isEnglish = true),
          ),
          _LanguageChip(
            label: 'FR',
            isSelected: !_isEnglish,
            onTap: () => setState(() => _isEnglish = false),
          ),
        ],
      ),
    );
  }

  void _navigateToStory(BuildContext context, String slug) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => StoryDetailScreen(slug: slug)));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final FaIconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        FaIcon(icon, color: AppColors.terracotta, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isSelected ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({required this.story, required this.onTap});

  final StoryModel story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outline),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.terracotta.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    story.categories.isNotEmpty
                        ? story.categories.first.icon
                        : '',
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${story.author.displayName} • ${story.readTimeDisplay}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              FaIcon(AppIcons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final FaIconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        // Navigate to region
      },
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FaIcon(icon, color: color, size: 24),
            const Spacer(),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
