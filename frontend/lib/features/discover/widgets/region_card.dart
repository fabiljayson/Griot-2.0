import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/griot_image.dart';
import '../models/region_model.dart';

/// Card for a single region in the Home "Discover Regions" strip and on the
/// region grid.
///
/// Replaces the previous icon-only `_RegionChip`, which had no image, no story
/// count and a dead `onTap`. Each card renders its **own** region photograph —
/// regions never share art — plus the real number of stories available.
class RegionCard extends StatelessWidget {
  const RegionCard({
    super.key,
    required this.region,
    required this.onTap,
    this.width = 200,
    this.height = 176,
    this.layout = RegionCardLayout.chip,
  });

  final RegionModel region;
  final VoidCallback onTap;
  final double width;
  final double height;
  final RegionCardLayout layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isGrid = layout == RegionCardLayout.grid;
    final radius = BorderRadius.circular(AppRadius.card);

    final content = SizedBox(
      width: isGrid ? null : width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: scheme.outline),
              color: scheme.surface,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Region-specific photograph.
                  GriotImage(
                    source: region.imageAsset,
                    fit: BoxFit.cover,
                    semanticLabel: '${region.label} region',
                    placeholderIcon: AppIcons.landmark,
                  ),
                  // Legibility scrim (functional, not decorative): keeps the
                  // label readable over arbitrary photography in both themes.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x14000000), Color(0xCC0F1219)],
                        stops: [0.35, 1.0],
                      ),
                    ),
                  ),
                  // Region icon.
                  Positioned(
                    top: AppSpacing.md,
                    left: AppSpacing.md,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: region.accent,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Center(
                        child: FaIcon(
                          region.icon,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Label + story count.
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          region.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${region.storyCount} '
                          '${region.storyCount == 1 ? 'story' : 'stories'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return content;
  }
}

/// Presentation variants for [RegionCard].
enum RegionCardLayout {
  /// Fixed-width card for the horizontal Home strip.
  chip,

  /// Fluid card for a responsive grid.
  grid,
}
