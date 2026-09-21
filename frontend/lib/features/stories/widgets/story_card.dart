import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_image.dart';
import '../models/story_model.dart';

/// Card widget for displaying a story in the discovery grid.
///
/// Matches the webapp's `partials/story_card.html`: cover image, category chip,
/// region chip, title, summary, author, read time, view/like/bookmark counts.
///
/// Images now go through [GriotImage], so both bundled asset covers and
/// backend URLs load (the previous `Image.network` call could not resolve an
/// `assets/...` path and silently fell back to a gradient placeholder).
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
    final category = story.categories.isEmpty ? null : story.categories.first;

    return AppCard(
      padding: EdgeInsets.zero,
      elevated: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Cover ---
          Stack(
            children: [
              GriotCoverImage(
                source: story.coverImage,
                blurhash: story.coverImageBlurhash,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.card),
                ),
                semanticLabel: story.title,
              ),
              if (category != null)
                Positioned(
                  top: AppSpacing.sm,
                  left: AppSpacing.sm,
                  child: _OverlayPill(
                    // Real category icon instead of the stored emoji glyph.
                    icon: AppIcons.fromEmoji(category.icon),
                    label: category.name,
                  ),
                ),
              if (story.region.isNotEmpty)
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: _OverlayPill(
                    icon: AppIcons.location_on,
                    label: story.region,
                    emphasized: true,
                  ),
                ),
            ],
          ),

          // --- Content ---
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  story.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (story.summary.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs + 1),
                  Text(
                    story.summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),

                // --- Author + read time ---
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.bronze.withValues(alpha: 0.18),
                      child: Text(
                        story.author.username.isNotEmpty
                            ? story.author.username[0].toUpperCase()
                            : '?',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.bronzeDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        story.author.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    FaIcon(
                      AppIcons.schedule,
                      size: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${story.estimatedReadTime} min',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Divider(color: scheme.outline, height: 1),
                const SizedBox(height: AppSpacing.sm),

                // --- Stats & actions ---
                Row(
                  children: [
                    _Stat(
                      icon: AppIcons.remove_red_eye_outlined,
                      label: story.formattedViewCount,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _Stat(
                      icon: AppIcons.favorite_outline,
                      label: story.formattedLikeCount,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _Stat(
                      icon: AppIcons.bookmark_outline,
                      label: story.formattedBookmarkCount,
                    ),
                    const Spacer(),
                    // Language shown as a real icon, not a flag emoji.
                    _IconAction(
                      icon: story.isLiked
                          ? AppIcons.favorite
                          : AppIcons.favorite_border,
                      color: story.isLiked ? scheme.error : null,
                      tooltip: story.isLiked ? 'Unlike' : 'Like',
                      onPressed: onLike,
                    ),
                    _IconAction(
                      icon: story.isBookmarked
                          ? AppIcons.bookmark
                          : AppIcons.bookmark_border,
                      color: story.isBookmarked ? AppColors.bronzeDark : null,
                      tooltip: story.isBookmarked
                          ? 'Remove bookmark'
                          : 'Bookmark',
                      onPressed: onBookmark,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small translucent label laid over the cover.
class _OverlayPill extends StatelessWidget {
  const _OverlayPill({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final FaIconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: emphasized
            ? AppColors.indigo.withValues(alpha: 0.82)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            icon,
            size: 10,
            color: emphasized ? Colors.white : AppColors.indigo,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: emphasized ? Colors.white : AppColors.indigo,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + count pair.
class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final FaIconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// Compact icon button used for like/bookmark on the card.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final FaIconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: FaIcon(
        icon,
        size: 17,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
