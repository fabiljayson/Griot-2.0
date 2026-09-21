import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_image.dart';
import '../../qr_scanner/services/qr_api_service.dart';

/// Card for one museum artifact in the catalogue grid.
///
/// The artifact image comes from the backend (`/media/artifacts/images/...`);
/// [GriotImage] resolves the relative path. When an artifact genuinely has no
/// photograph the placeholder shows the artifact's **category icon** — never an
/// emoji, which is what the detail screen used to render.
class ArtifactCard extends StatelessWidget {
  const ArtifactCard({
    super.key,
    required this.artifact,
    required this.onTap,
  });

  final ArtifactModel artifact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      padding: EdgeInsets.zero,
      elevated: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GriotCoverImage(
            source: artifact.imageUrl,
            blurhash: artifact.imageBlurhash,
            aspectRatio: 4 / 3,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.card),
            ),
            semanticLabel: artifact.title,
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FaIcon(
                      AppIcons.artifactCategory(artifact.category),
                      size: 13,
                      color: AppColors.bronze,
                    ),
                    const SizedBox(width: AppSpacing.xs + 1),
                    Expanded(
                      child: Text(
                        artifact.categoryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.bronze,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  artifact.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                if (artifact.culture.isNotEmpty ||
                    artifact.region.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    [
                      if (artifact.culture.isNotEmpty) artifact.culture,
                      if (artifact.region.isNotEmpty) artifact.region,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (artifact.museumName.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      FaIcon(
                        AppIcons.museum_outlined,
                        size: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          artifact.museumName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
