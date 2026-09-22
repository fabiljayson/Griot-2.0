import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_image.dart';
import '../../../core/widgets/griot_loader.dart';
import '../../stories/models/story_model.dart';
import '../../stories/providers/story_provider.dart';
import '../../stories/screens/story_detail_screen.dart';
import '../../stories/widgets/story_card.dart';
import '../models/region_model.dart';
import '../providers/region_provider.dart';

/// Stories for a single Discover Region.
///
/// Reached from the Home region strip; previously that tap did nothing at all
/// (`onTap: () { // Navigate to region }`).
class RegionStoriesScreen extends ConsumerWidget {
  const RegionStoriesScreen({super.key, required this.regionSlug});

  final String regionSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final region = Regions.bySlug(regionSlug);
    final storiesAsync = ref.watch(regionStoriesProvider(regionSlug));

    if (region == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Region')),
        body: const EmptyState(
          title: 'Unknown region',
          subtitle: 'This region is not part of the catalogue.',
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _RegionHeader(region: region),
          storiesAsync.when(
            data: (stories) => stories.isEmpty
                ? SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      title: 'No stories yet',
                      subtitle:
                          'No published stories from ${region.label} are '
                          'available offline yet.',
                      icon: AppIcons.auto_stories_outlined,
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    sliver: SliverMasonryGrid.count(
                      crossAxisCount: _columns(context),
                      mainAxisSpacing: AppSpacing.lg,
                      crossAxisSpacing: AppSpacing.lg,
                      childCount: stories.length,
                      itemBuilder: (context, index) {
                        final story = stories[index];
                        return StoryCard(
                          story: story,
                          onTap: () => _open(context, story),
                          onBookmark: () => ref
                              .read(storyListProvider.notifier)
                              .toggleBookmark(story.slug),
                          onLike: () => ref
                              .read(storyListProvider.notifier)
                              .toggleLike(story.slug),
                        );
                      },
                    ),
                  ),
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: GriotLoadingState(label: 'Loading stories'),
            ),
            error: (error, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(message: '$error'),
            ),
          ),
        ],
      ),
    );
  }

  static int _columns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width > 1200) return 4;
    if (width > 800) return 3;
    if (width > 500) return 2;
    return 1;
  }

  static void _open(BuildContext context, StoryModel story) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryDetailScreen(slug: story.slug),
      ),
    );
  }
}

/// Region hero: the region's own photograph, icon, name and description.
class _RegionHeader extends StatelessWidget {
  const _RegionHeader({required this.region});

  final RegionModel region;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      foregroundColor: Colors.white,
      backgroundColor: theme.colorScheme.primary,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(
          left: AppSpacing.section + AppSpacing.md,
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
        ),
        title: Text(
          region.label,
          style: theme.textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            GriotImage(
              source: region.imageAsset,
              fit: BoxFit.cover,
              semanticLabel: '${region.label} region',
              placeholderIcon: AppIcons.landmark,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x22000000), Color(0xD90F1219)],
                  stops: [0.3, 1.0],
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.section * 1.4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: region.accent,
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Center(
                          child: Icon(
                            region.icon,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${region.storyCount} '
                        '${region.storyCount == 1 ? 'story' : 'stories'}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.86),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    region.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
