import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_image.dart';
import '../../stories/screens/story_detail_screen.dart';
import '../providers/library_provider.dart';
import '../screens/library_screen.dart';
import '../services/library_api_service.dart';

/// Horizontal strip of stories the reader has started but not finished.
///
/// This widget already existed but had **no call site** anywhere in the app, so
/// nothing ever surfaced reading progress to the reader. It is now part of Home.
class ContinueReadingWidget extends ConsumerStatefulWidget {
  const ContinueReadingWidget({super.key});

  @override
  ConsumerState<ContinueReadingWidget> createState() =>
      _ContinueReadingWidgetState();
}

class _ContinueReadingWidgetState extends ConsumerState<ContinueReadingWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(libraryProvider);
      if (state.continueReading.isEmpty && !state.isLoading) {
        ref.read(libraryProvider.notifier).loadContinueReading();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final stories = ref.watch(
      libraryProvider.select((state) => state.continueReading),
    );

    // Nothing in progress — stay out of the way.
    if (stories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Continue Reading',
          icon: AppIcons.play_circle_outline,
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LibraryScreen()),
            ),
            child: const Text('See all'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stories.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) =>
                _ContinueCard(story: stories[index]),
          ),
        ),
        const SizedBox(height: AppSpacing.section),
      ],
    );
  }
}

/// Card for one in-progress story.
///
/// The percentage used to be a badge overlaid on the cover, which crowded the
/// art and — on the list variant — collided with the title. It now has its own
/// row via [ProgressRow]: bar on the left, value in a reserved trailing box.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.story});

  final LibraryStoryModel story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 264,
      child: AppCard(
        padding: EdgeInsets.zero,
        elevated: true,
        onTap: () => _open(context),
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
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
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
                        FaIcon(
                          AppIcons.timer_outlined,
                          size: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            '${story.estimatedReadTime} min read',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Progress gets its own row — never over the title.
                    ProgressRow(
                      fraction: story.progressFraction,
                      thickness: 5,
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

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoryDetailScreen(slug: story.slug)),
    );
  }
}
