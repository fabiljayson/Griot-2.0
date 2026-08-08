import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../stories/models/story_model.dart';
import '../../stories/screens/story_detail_screen.dart';

/// Horizontal scrollable widget showing trending stories.
///
/// Displayed on the home screen to help users discover popular content.
class TrendingStoriesWidget extends StatelessWidget {
  const TrendingStoriesWidget({super.key, required this.stories});

  final List<StoryModel> stories;

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(
                Icons.trending_up,
                color: AppColors.terracotta,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Trending Now',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: stories.length,
            itemBuilder: (context, index) {
              final story = stories[index];
              return _buildTrendingCard(context, story, index + 1);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTrendingCard(BuildContext context, StoryModel story, int rank) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StoryDetailScreen(slug: story.slug),
          ),
        );
      },
      child: Container(
        width: 260,
        margin: const EdgeInsets.symmetric(horizontal: 4),
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
            // Cover image with rank badge
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: story.coverImage != null
                      ? CachedNetworkImage(
                          imageUrl: story.coverImage!,
                          height: 100,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
                // Rank badge
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: rank <= 3
                          ? AppColors.ochre
                          : AppColors.charcoalMuted,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
                // Trending indicator
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.terracotta,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.trending_up, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Trending',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.remove_red_eye_outlined,
                          size: 14,
                          color: AppColors.charcoalMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          story.formattedViewCount,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.charcoalMuted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.favorite_outline,
                          size: 14,
                          color: AppColors.charcoalMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          story.formattedLikeCount,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.terracottaTint, AppColors.ochreTint],
        ),
      ),
      child: const Center(child: Text('📖', style: TextStyle(fontSize: 32))),
    );
  }
}
