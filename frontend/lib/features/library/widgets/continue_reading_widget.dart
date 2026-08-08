import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../stories/screens/story_detail_screen.dart';
import '../providers/library_provider.dart';
import '../screens/library_screen.dart';

/// Horizontal scrollable widget showing stories in progress.
///
/// Displayed on the home screen to let users quickly resume reading.
class ContinueReadingWidget extends ConsumerWidget {
  const ContinueReadingWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryProvider);

    if (state.continueReading.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'Continue Reading',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LibraryScreen()),
                  );
                },
                child: const Text('See All'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: state.continueReading.length,
            itemBuilder: (context, index) {
              final story = state.continueReading[index];
              return _buildContinueCard(context, story);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContinueCard(BuildContext context, story) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StoryDetailScreen(slug: story.slug),
          ),
        );
      },
      child: Container(
        width: 280,
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
            // Cover image with progress
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
                // Progress badge
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
                    child: Text(
                      '${story.progressPercent}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 12,
                          color: AppColors.charcoalMuted,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${story.estimatedReadTime} min left',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.charcoalMuted,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: story.progressFraction,
                        backgroundColor: AppColors.parchmentDark,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.terracotta,
                        ),
                        minHeight: 4,
                      ),
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
