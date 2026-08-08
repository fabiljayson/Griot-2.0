import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/theme/app_colors.dart';
import '../models/story_model.dart';
import '../providers/story_provider.dart';
import '../widgets/story_actions.dart';

/// Story detail screen with interactive markdown reader.
///
/// Features:
/// - Full markdown rendering
/// - Reading progress tracking
/// - Like/bookmark/flag actions
/// - Author info
/// - Cultural context and moral lesson
/// - Related stories (Phase 7)
class StoryDetailScreen extends ConsumerStatefulWidget {
  const StoryDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends ConsumerState<StoryDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0;

  @override
  void initState() {
    super.initState();
    // Load story
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storyDetailProvider.notifier).loadStory(widget.slug);
    });

    // Track scroll progress
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.hasContentDimensions) {
      final progress =
          (_scrollController.offset /
                  _scrollController.position.maxScrollExtent)
              .clamp(0.0, 1.0);

      if (progress != _scrollProgress) {
        setState(() => _scrollProgress = progress);

        // Update reading progress in backend (debounced)
        _updateReadingProgress((progress * 100).round());
      }
    }
  }

  void _updateReadingProgress(int percent) {
    ref
        .read(storyDetailProvider.notifier)
        .updateProgress(
          percent: percent,
          lastPosition: _scrollController.offset.round(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storyState = ref.watch(storyDetailProvider);

    return Scaffold(
      body: storyState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : storyState.errorMessage != null
          ? _ErrorWidget(
              message: storyState.errorMessage!,
              onRetry: () {
                ref.read(storyDetailProvider.notifier).loadStory(widget.slug);
              },
            )
          : storyState.story == null
          ? const SizedBox.shrink()
          : _buildStoryContent(storyState.story!, theme),
    );
  }

  Widget _buildStoryContent(StoryModel story, ThemeData theme) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // --- App Bar with progress ---
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(
              story.title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            background: story.coverImage != null
                ? Image.network(
                    story.coverImage!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildCoverPlaceholder(story);
                    },
                  )
                : _buildCoverPlaceholder(story),
          ),
          actions: [
            // Reading progress indicator
            if (_scrollProgress > 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${(_scrollProgress * 100).round()}%',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            // Actions menu
            StoryActionsMenu(story: story),
          ],
        ),

        // --- Story content ---
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Author & metadata ---
                _AuthorSection(story: story),
                const SizedBox(height: 24),

                // --- Summary ---
                if (story.summary.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.ochreTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      story.summary,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // --- Main content (Markdown) ---
                MarkdownBody(
                  data: story.content,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
                    h1: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    h2: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    h3: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    blockquote: theme.textTheme.bodyLarge?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    code: TextStyle(
                      fontFamily: 'monospace',
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // --- Tags ---
                if (story.tagList.isNotEmpty) ...[
                  _SectionTitle(title: 'Tags'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: story.tagList.map((tag) {
                      return Chip(
                        label: Text(tag),
                        backgroundColor: AppColors.terracotta.withValues(
                          alpha: 0.1,
                        ),
                        labelStyle: TextStyle(color: AppColors.terracotta),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // --- Cultural Context ---
                if (story.culturalContext.isNotEmpty) ...[
                  _SectionTitle(title: 'Cultural Context'),
                  const SizedBox(height: 8),
                  Text(
                    story.culturalContext,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                ],

                // --- Moral Lesson ---
                if (story.moralLesson.isNotEmpty) ...[
                  _SectionTitle(title: 'Moral Lesson'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.savannahGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.savannahGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text('💡', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            story.moralLesson,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // --- Source ---
                if (story.source.isNotEmpty) ...[
                  _SectionTitle(title: 'Source'),
                  const SizedBox(height: 8),
                  Text(
                    story.source,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverPlaceholder(StoryModel story) {
    return Container(
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
      child: Center(
        child: Text(
          story.categories.isNotEmpty ? story.categories.first.icon : '📖',
          style: const TextStyle(fontSize: 64),
        ),
      ),
    );
  }
}

/// Author section widget.
class _AuthorSection extends StatelessWidget {
  const _AuthorSection({required this.story});

  final StoryModel story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        // Author avatar
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.terracotta.withValues(alpha: 0.2),
          child: Text(
            story.author.username.isNotEmpty
                ? story.author.username[0].toUpperCase()
                : '?',
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.terracotta,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                story.author.displayName,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                story.readTimeDisplay,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // Language badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.ochre.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${StoryLanguage.fromString(story.language).flag} ${StoryLanguage.fromString(story.language).label}',
            style: theme.textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

/// Section title widget.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.terracotta,
      ),
    );
  }
}

/// Error widget.
class _ErrorWidget extends StatelessWidget {
  const _ErrorWidget({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load story',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
