import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_image.dart';
import '../../../core/widgets/griot_loader.dart';
import '../../stories/screens/story_detail_screen.dart';
import '../providers/library_provider.dart';
import '../services/library_api_service.dart';

/// Main library screen with three tabs:
///   - Continue Reading (stories in progress)
///   - Recently Read
///   - Bookmarks
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryProvider.notifier).loadAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Column(
        children: [
          // --- Header ---
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            color: scheme.surface,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('My Library', style: theme.textTheme.displaySmall),
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: scheme.primary,
            unselectedLabelColor: scheme.onSurfaceVariant,
            indicatorColor: scheme.primary,
            tabs: const [
              Tab(text: 'Continue', icon: FaIcon(AppIcons.play_circle_outline)),
              Tab(text: 'Recent', icon: FaIcon(AppIcons.history)),
              Tab(text: 'Saved', icon: FaIcon(AppIcons.bookmark_outline)),
            ],
          ),
          Expanded(
            child: state.isLoading
                ? const GriotLoadingState(label: 'Loading library')
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTab(
                        stories: state.continueReading,
                        error: state.errorMessage,
                        emptyTitle: 'Nothing in progress',
                        emptySubtitle:
                            'Start reading a story and it will appear here.',
                        icon: AppIcons.auto_stories,
                        cardBuilder: (story) => _ContinueCard(story: story),
                      ),
                      _buildTab(
                        stories: state.recentlyRead,
                        error: state.errorMessage,
                        emptyTitle: 'No reading history',
                        emptySubtitle: 'Stories you read will appear here.',
                        icon: AppIcons.history,
                        cardBuilder: (story) => _StoryListTile(story: story),
                      ),
                      _buildTab(
                        stories: state.bookmarks,
                        error: state.errorMessage,
                        emptyTitle: 'No saved stories',
                        emptySubtitle: 'Bookmark stories to find them here.',
                        icon: AppIcons.bookmark_border,
                        cardBuilder: (story) =>
                            _StoryListTile(story: story, showBookmark: true),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Renders a tab, surfacing load failures instead of showing a misleadingly
  /// empty list (the previous behaviour).
  Widget _buildTab({
    required List<LibraryStoryModel> stories,
    required String? error,
    required String emptyTitle,
    required String emptySubtitle,
    required FaIconData icon,
    required Widget Function(LibraryStoryModel) cardBuilder,
  }) {
    if (stories.isEmpty && error != null) {
      return ErrorState(
        message: error,
        title: 'Could not load your library',
        onRetry: () => ref.read(libraryProvider.notifier).loadAll(),
      );
    }

    if (stories.isEmpty) {
      return EmptyState(
        title: emptyTitle,
        subtitle: emptySubtitle,
        icon: icon,
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(libraryProvider.notifier).loadAll(),
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: stories.length,
        itemBuilder: (context, index) => cardBuilder(stories[index]),
      ),
    );
  }
}

/// Continue-reading card.
///
/// The percentage previously floated as a badge over the cover art. It now sits
/// in its own dedicated row next to the bar, so it can never overlap the title
/// or the image.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.story});

  final LibraryStoryModel story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: () => _open(context, story),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GriotCoverImage(
              source: story.coverImage,
              aspectRatio: 16 / 9,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.card),
              ),
              semanticLabel: story.title,
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (story.summary.isNotEmpty || story.region.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      story.summary.isNotEmpty ? story.summary : story.region,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  // Bar + value, each in their own box.
                  ProgressRow(
                    fraction: story.progressFraction,
                    label: '${story.estimatedReadTime} min',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _open(BuildContext context, LibraryStoryModel story) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoryDetailScreen(slug: story.slug)),
    );
  }
}

/// Compact row used by the Recent and Saved tabs.
///
/// The old version squeezed a 40 px ring with the number inside it next to a
/// single-line title, which clipped on narrow screens and at larger text
/// scales. The value now renders as text in a reserved width beside a thin bar.
class _StoryListTile extends StatelessWidget {
  const _StoryListTile({required this.story, this.showBookmark = false});

  final LibraryStoryModel story;
  final bool showBookmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: () => _open(context, story),
        child: Row(
          children: [
            GriotThumbnail(source: story.coverImage, size: 60),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      if (story.region.isNotEmpty) ...[
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FaIcon(
                                AppIcons.place_outlined,
                                size: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  story.region,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      FaIcon(
                        AppIcons.timer_outlined,
                        size: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${story.estimatedReadTime} min',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (story.progressPercent > 0 &&
                      story.progressPercent < 100) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ProgressRow(
                      fraction: story.progressFraction,
                      thickness: 4,
                      label: 'read',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (story.completed)
              FaIcon(AppIcons.check_circle, color: scheme.tertiary, size: 18)
            else if (showBookmark)
              FaIcon(AppIcons.bookmark, color: scheme.secondary, size: 18)
            else
              FaIcon(
                AppIcons.chevron_right,
                color: scheme.onSurfaceVariant,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  static void _open(BuildContext context, LibraryStoryModel story) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoryDetailScreen(slug: story.slug)),
    );
  }
}
