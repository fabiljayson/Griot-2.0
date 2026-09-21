import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_image.dart';
import '../../stories/models/story_model.dart';
import '../../stories/screens/story_detail_screen.dart';

/// Horizontal carousel of trending story cards for the home screen.
///
/// The section header lives in the parent screen — this widget renders only
/// the card strip so it can be reused beneath any heading. Colors come from
/// the active [ColorScheme], so the strip adapts to light & dark themes.
class TrendingStoriesWidget extends StatelessWidget {
  const TrendingStoriesWidget({super.key, required this.stories});

  final List<StoryModel> stories;

  @override
  Widget build(BuildContext context) {
    if (stories.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemCount: stories.length,
      itemBuilder: (context, index) {
        final story = stories[index];
        return _buildTrendingCard(context, story, index + 1);
      },
    );
  }

  Widget _buildTrendingCard(BuildContext context, StoryModel story, int rank) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      width: 250,
      child: AppCard(
        padding: EdgeInsets.zero,
        elevated: true,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => StoryDetailScreen(slug: story.slug),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image with rank badge.
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
                // Rank badge.
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rank <= 3
                          ? AppColors.ochre
                          : scheme.onSurfaceVariant,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: rank <= 3 ? AppColors.charcoal : scheme.surface,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                // Trending indicator.
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FaIcon(
                          AppIcons.trending_up,
                          color: scheme.onPrimary,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Trending',
                          style: TextStyle(
                            color: scheme.onPrimary,
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

            // Content.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),

                    // FittedBox keeps the meta row from overflowing on
                    // narrow cards / larger font scales.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          FaIcon(
                            AppIcons.remove_red_eye_outlined,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            story.formattedViewCount,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                          FaIcon(
                            AppIcons.favorite_outline,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            story.formattedLikeCount,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            story.readTimeDisplay,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
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
}
