import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/story_model.dart';

/// Card widget for displaying a story in the discovery grid.
///
/// Features:
/// - Cover image with BlurHash placeholder
/// - Title and summary
/// - Author info with avatar
/// - Category badges
/// - Reading time
/// - Like/bookmark counts
/// - Tap to open story detail
class StoryCard extends StatelessWidget {
  const StoryCard({
    super.key,
    required this.story,
    required this.onTap,
    required this.onBookmark,
    required this.onLike,
  });

  final StoryModel story;
  final VoidCallback onTap;
  final VoidCallback onBookmark;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Cover image ---
            _CoverImage(
              story: story,
              onBookmark: onBookmark,
              isBookmarked: story.isBookmarked,
            ),

            // --- Content ---
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Categories
                  if (story.categories.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: story.categories.take(2).map((cat) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cat.colorValue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${cat.icon} ${cat.name}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cat.colorValue,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 8),

                  // Title
                  Text(
                    story.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Summary
                  if (story.summary.isNotEmpty)
                    Text(
                      story.summary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 12),

                  // Author & metadata
                  Row(
                    children: [
                      // Author avatar
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.terracotta.withValues(alpha: 0.2),
                        child: Text(
                          story.author.username.isNotEmpty
                              ? story.author.username[0].toUpperCase()
                              : '?',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.terracotta,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              story.author.displayName,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              story.readTimeDisplay,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Stats row
                  Row(
                    children: [
                      // Views
                      _StatChip(
                        icon: Icons.remove_red_eye_outlined,
                        label: story.formattedViewCount,
                      ),
                      const SizedBox(width: 12),

                      // Likes
                      GestureDetector(
                        onTap: onLike,
                        child: _StatChip(
                          icon: story.isLiked
                              ? Icons.favorite
                              : Icons.favorite_border,
                          label: story.formattedLikeCount,
                          color: story.isLiked ? AppColors.error : null,
                        ),
                      ),
                      const Spacer(),

                      // Language flag
                      if (story.language.isNotEmpty)
                        Text(
                          StoryLanguage.fromString(story.language).flag,
                          style: const TextStyle(fontSize: 16),
                        ),
                    ],
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

/// Cover image with blurhash placeholder and bookmark button.
class _CoverImage extends StatelessWidget {
  const _CoverImage({
    required this.story,
    required this.onBookmark,
    required this.isBookmarked,
  });

  final StoryModel story;
  final VoidCallback onBookmark;
  final bool isBookmarked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // If no cover image, show a gradient placeholder
    if (story.coverImage == null || story.coverImage!.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.terracotta.withValues(alpha: 0.8),
              AppColors.ochre.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                story.categories.isNotEmpty
                    ? story.categories.first.icon
                    : '📖',
                style: const TextStyle(fontSize: 48),
              ),
            ),
            // Bookmark button
            Positioned(
              top: 8,
              right: 8,
              child: _BookmarkButton(
                isBookmarked: isBookmarked,
                onPressed: onBookmark,
              ),
            ),
          ],
        ),
      );
    }

    // With cover image
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: Image.network(
            story.coverImage!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: AppColors.parchment,
                child: Center(
                  child: Icon(
                    Icons.image_outlined,
                    size: 48,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ),
        // Bookmark button
        Positioned(
          top: 8,
          right: 8,
          child: _BookmarkButton(
            isBookmarked: isBookmarked,
            onPressed: onBookmark,
          ),
        ),
      ],
    );
  }
}

/// Bookmark button.
class _BookmarkButton extends StatelessWidget {
  const _BookmarkButton({
    required this.isBookmarked,
    required this.onPressed,
  });

  final bool isBookmarked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.3),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            color: isBookmarked ? AppColors.ochre : Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// Stat chip (views, likes).
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color ?? theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}