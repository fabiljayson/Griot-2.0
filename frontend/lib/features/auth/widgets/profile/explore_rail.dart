import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_components.dart';
import '../../../../core/widgets/griot_loader.dart';
import '../../../stories/models/story_model.dart';
import '../../../stories/providers/story_provider.dart';
import '../../../stories/screens/stories_screen.dart';

/// Horizontal category rail, mirroring the reference's "Explore Categories".
class ExploreRail extends ConsumerWidget {
  const ExploreRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Explore', icon: AppIcons.explore),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 112,
          child: categoriesAsync.when(
            data: (categories) => categories.isEmpty
                ? const EmptyState(
                    title: 'No categories yet',
                    icon: AppIcons.layerGroup,
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (context, index) => ExploreCard(
                      category: categories[index],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StoriesScreen(),
                        ),
                      ),
                    ),
                  ),
            loading: () => const Center(child: GriotLoader(size: 26)),
            error: (_, _) => const EmptyState(
              title: 'Categories unavailable',
              icon: AppIcons.layerGroup,
            ),
          ),
        ),
      ],
    );
  }
}

class ExploreCard extends StatelessWidget {
  const ExploreCard({super.key, required this.category, required this.onTap});

  final StoryCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 104,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.bronzeTint,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              // Real icon resolved from the stored glyph.
              child: Icon(
                AppIcons.fromEmoji(category.icon),
                size: 20,
                color: AppColors.accentTextStrong,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
