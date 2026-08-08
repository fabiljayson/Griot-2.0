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
import 'widgets/offline_story_counter.dart';

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
      author: UserModel(id: 1, username: 'griot_ama', firstName: 'Ama', lastName: 'Ata'),
      region: 'Grassfields',
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
      author: UserModel(id: 2, username: 'kofi_duma', firstName: 'Kofi', lastName: 'Duma'),
      region: 'Bamoun',
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
      author: UserModel(id: 3, username: 'nana_yemo', firstName: 'Nana', lastName: 'Yemo'),
      region: 'Bamoun',
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
      author: UserModel(id: 4, username: 'mami_wata', firstName: 'Sarah', lastName: 'Biya'),
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
      author: UserModel(id: 5, username: 'papa_mbei', firstName: 'Papa', lastName: 'Mbei'),
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
    final user = authState.valueOrNull?.user;

    return Scaffold(
      body: SafeArea(
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
                    icon: Icons.trending_up,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: TrendingStoriesWidget(
                      stories: _trendingStories,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // --- Popular Section ---
                  _SectionHeader(
                    title: _isEnglish ? 'Popular Stories' : 'Histoires Populaires',
                    icon: Icons.favorite,
                  ),
                  const SizedBox(height: 12),
                  ...(_popularStories.map((story) => _StoryCard(
                        story: story,
                        onTap: () => _navigateToStory(context, story.slug),
                      ))),
                  const SizedBox(height: 32),

                  // --- Discover Regions ---
                  _SectionHeader(
                    title: _isEnglish ? 'Discover Regions' : 'Découvrir les Régions',
                    icon: Icons.explore,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 120,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _RegionChip(
                          emoji: '🛕',
                          label: 'Bamoun',
                          color: AppColors.terracotta,
                        ),
                        const SizedBox(width: 12),
                        _RegionChip(
                          emoji: '🌄',
                          label: 'Adamawa',
                          color: AppColors.ochre,
                        ),
                        const SizedBox(width: 12),
                        _RegionChip(
                          emoji: '🌊',
                          label: 'Coastal',
                          color: AppColors.savannahGreen,
                        ),
                        const SizedBox(width: 12),
                        _RegionChip(
                          emoji: '🗿',
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
          colors: [
            scheme.primary,
            scheme.primary.withValues(alpha: 0.8),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.ochre.withValues(alpha: 0.7),
                    width: 1.2,
                  ),
                ),
                child: const Text(
                  '🪘',
                  style: TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GRIOT 2.0',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.surfaceLight,
                        letterSpacing: 1.4,
                      ),
                    ),
                    Text(
                      'African Teller',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.ochre,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Toggle theme',
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .toggleDarkMode(
                      systemBrightness:
                          MediaQuery.of(context).platformBrightness,
                    ),
                icon: const Icon(Icons.dark_mode_outlined),
                color: AppColors.surfaceLight,
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
                  icon: const Icon(Icons.account_circle_outlined),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LanguageChip(
            label: '🇬🇧 EN',
            isSelected: _isEnglish,
            onTap: () => setState(() => _isEnglish = true),
          ),
          _LanguageChip(
            label: '🇫🇷 FR',
            isSelected: !_isEnglish,
            onTap: () => setState(() => _isEnglish = false),
          ),
        ],
      ),
    );
  }

  void _navigateToStory(BuildContext context, String slug) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryDetailScreen(slug: slug),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: AppColors.terracotta, size: 20),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleLarge),
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
  const _StoryCard({
    required this.story,
    required this.onTap,
  });

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
                color: AppColors.charcoal.withValues(alpha: 0.04),
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
                        : '📖',
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
              Icon(
                Icons.chevron_right,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({
    required this.emoji,
    required this.label,
    required this.color,
  });

  final String emoji;
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
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const Spacer(),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
