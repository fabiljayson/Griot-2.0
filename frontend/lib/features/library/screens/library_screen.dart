import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
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
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Load library data
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

    return Scaffold(
      backgroundColor: AppColors.parchment,
      appBar: AppBar(
        title: const Text('My Library'),
        backgroundColor: AppColors.parchment,
        elevation: 0,
        foregroundColor: AppColors.charcoal,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.terracotta,
          unselectedLabelColor: AppColors.charcoalMuted,
          indicatorColor: AppColors.terracotta,
          tabs: const [
            Tab(text: 'Continue', icon: Icon(Icons.play_circle_outline)),
            Tab(text: 'Recent', icon: Icon(Icons.history)),
            Tab(text: 'Saved', icon: Icon(Icons.bookmark_outline)),
          ],
        ),
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.terracotta),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildContinueReading(state.continueReading),
                _buildRecentlyRead(state.recentlyRead),
                _buildBookmarks(state.bookmarks),
              ],
            ),
    );
  }

  Widget _buildContinueReading(List<LibraryStoryModel> stories) {
    if (stories.isEmpty) {
      return _buildEmptyState(
        icon: Icons.auto_stories,
        title: 'Nothing in progress',
        subtitle: 'Start reading a story to see it here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: stories.length,
      itemBuilder: (context, index) {
        final story = stories[index];
        return _buildContinueCard(story);
      },
    );
  }

  Widget _buildRecentlyRead(List<LibraryStoryModel> stories) {
    if (stories.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history,
        title: 'No reading history',
        subtitle: 'Stories you read will appear here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: stories.length,
      itemBuilder: (context, index) {
        final story = stories[index];
        return _buildStoryListTile(story);
      },
    );
  }

  Widget _buildBookmarks(List<LibraryStoryModel> stories) {
    if (stories.isEmpty) {
      return _buildEmptyState(
        icon: Icons.bookmark_border,
        title: 'No saved stories',
        subtitle: 'Bookmark stories to find them here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: stories.length,
      itemBuilder: (context, index) {
        final story = stories[index];
        return _buildStoryListTile(story, showBookmark: true);
      },
    );
  }

  Widget _buildContinueCard(LibraryStoryModel story) {
    return GestureDetector(
      onTap: () => _openStory(story),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Story image with progress overlay
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: story.coverImage != null
                      ? CachedNetworkImage(
                          imageUrl: story.coverImage!,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            height: 140,
                            color: AppColors.parchmentDark,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.terracotta,
                              ),
                            ),
                          ),
                          errorWidget: (_, _, _) => _buildPlaceholderImage(),
                        )
                      : _buildPlaceholderImage(),
                ),
                // Progress badge
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.terracotta,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${story.progressPercent}% read',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    story.summary.isNotEmpty ? story.summary : story.region,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.charcoalMuted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: story.progressFraction,
                      backgroundColor: AppColors.parchmentDark,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.terracotta,
                      ),
                      minHeight: 6,
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

  Widget _buildStoryListTile(
    LibraryStoryModel story, {
    bool showBookmark = false,
  }) {
    return GestureDetector(
      onTap: () => _openStory(story),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.charcoalMuted.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: story.coverImage != null
                  ? CachedNetworkImage(
                      imageUrl: story.coverImage!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _buildSmallPlaceholder(),
                    )
                  : _buildSmallPlaceholder(),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (story.region.isNotEmpty) ...[
                        Icon(
                          Icons.place_outlined,
                          size: 12,
                          color: AppColors.charcoalMuted,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          story.region,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.charcoalMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(
                        Icons.timer_outlined,
                        size: 12,
                        color: AppColors.charcoalMuted,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${story.estimatedReadTime} min',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.charcoalMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Progress indicator
            if (story.progressPercent > 0 && !story.completed)
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: story.progressFraction,
                      backgroundColor: AppColors.parchmentDark,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.terracotta,
                      ),
                      strokeWidth: 3,
                    ),
                    Text(
                      '${story.progressPercent}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.terracotta,
                      ),
                    ),
                  ],
                ),
              )
            else if (story.completed)
              const Icon(
                Icons.check_circle,
                color: AppColors.savannahGreen,
                size: 24,
              )
            else if (showBookmark)
              Icon(Icons.bookmark, color: AppColors.ochre, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: AppColors.charcoalMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.charcoalMuted),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.charcoalMuted.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.terracottaTint, AppColors.ochreTint],
        ),
      ),
      child: const Center(child: Text('📖', style: TextStyle(fontSize: 48))),
    );
  }

  Widget _buildSmallPlaceholder() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.parchmentDark,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(child: Text('📖', style: TextStyle(fontSize: 24))),
    );
  }

  void _openStory(LibraryStoryModel story) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoryDetailScreen(slug: story.slug)),
    );
  }
}
