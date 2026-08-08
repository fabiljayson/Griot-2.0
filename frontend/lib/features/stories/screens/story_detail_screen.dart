import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/theme/app_colors.dart';
import '../../audio/models/narration_job_model.dart';
import '../../audio/providers/audio_provider.dart';
import '../../auth/providers/auth_provider.dart';
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
/// - "Take Quiz" CTA with guest-locked state
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storyDetailProvider.notifier).loadStory(widget.slug);
    });
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
          (_scrollController.offset / _scrollController.position.maxScrollExtent)
              .clamp(0.0, 1.0);
      if (progress != _scrollProgress) {
        setState(() => _scrollProgress = progress);
        _updateReadingProgress((progress * 100).round());
      }
    }
  }

  void _updateReadingProgress(int percent) {
    ref.read(storyDetailProvider.notifier).updateProgress(
          percent: percent,
          lastPosition: _scrollController.offset.round(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final storyState = ref.watch(storyDetailProvider);
    final authState = ref.watch(authProvider);
    final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;

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
                  : _buildStoryContent(storyState.story!, theme, scheme, isAuthenticated),
      bottomNavigationBar: storyState.story != null
          ? _buildBottomBar(context, theme, scheme, storyState.story!, isAuthenticated)
          : null,
    );
  }

  Widget _buildStoryContent(
    StoryModel story,
    ThemeData theme,
    ColorScheme scheme,
    bool isAuthenticated,
  ) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // --- App Bar with progress ---
        SliverAppBar(
          expandedHeight: 240,
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
            if (_scrollProgress > 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.terracotta,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(_scrollProgress * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
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

                // --- Region Badge ---
                if (story.region.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.ochre.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on, size: 16, color: AppColors.ochre),
                        const SizedBox(width: 4),
                        Text(
                          story.region,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppColors.ochre,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // --- Summary ---
                if (story.summary.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.ochre.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.ochre.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      story.summary,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: AppColors.ochre,
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
                    h1: theme.textTheme.headlineLarge,
                    h2: theme.textTheme.headlineMedium,
                    h3: theme.textTheme.headlineSmall,
                    blockquote: theme.textTheme.bodyLarge?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant,
                    ),
                    code: TextStyle(
                      fontFamily: 'monospace',
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // --- Cultural Context ---
                if (story.culturalContext.isNotEmpty) ...[
                  _SectionTitle(title: '🏛️ Cultural Context'),
                  const SizedBox(height: 8),
                  Text(
                    story.culturalContext,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                ],

                // --- Moral Lesson ---
                if (story.moralLesson.isNotEmpty) ...[
                  _SectionTitle(title: '💡 Moral Lesson'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.savannahGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.savannahGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      story.moralLesson,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
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

  Widget _buildBottomBar(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    StoryModel story,
    bool isAuthenticated,
  ) {
    final isNarrating = ref.watch(audioNarrationProvider).isGenerating;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Listen button (text-to-speech narration)
            IconButton(
              onPressed: isNarrating
                  ? null
                  : () => isAuthenticated
                        ? _listenToStory(story)
                        : _showLoginPrompt(context),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.terracotta.withValues(alpha: 0.1),
                foregroundColor: AppColors.terracotta,
              ),
              icon: isNarrating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.terracotta,
                      ),
                    )
                  : const Icon(Icons.headphones),
              tooltip: isNarrating ? 'Generating narration…' : 'Listen',
            ),
            const SizedBox(width: 12),
            // Like button
            _ActionButton(
              icon: story.isLiked ? Icons.favorite : Icons.favorite_border,
              label: story.formattedLikeCount,
              color: story.isLiked ? AppColors.error : null,
              onTap: isAuthenticated
                  ? () => ref.read(storyDetailProvider.notifier).toggleLike()
                  : () => _showLoginPrompt(context),
            ),
            const SizedBox(width: 16),
            // Bookmark button
            _ActionButton(
              icon: story.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              label: story.formattedBookmarkCount,
              color: story.isBookmarked ? AppColors.ochre : null,
              onTap: isAuthenticated
                  ? () => ref.read(storyDetailProvider.notifier).toggleBookmark()
                  : () => _showLoginPrompt(context),
            ),
            const SizedBox(width: 16),
            // Share button
            _ActionButton(
              icon: Icons.share_outlined,
              label: 'Share',
              onTap: () {
                // Share functionality
              },
            ),
            const Spacer(),
            // Take Quiz CTA
            if (isAuthenticated)
              ElevatedButton.icon(
                onPressed: () {
                  // Navigate to quiz
                },
                icon: const Icon(Icons.quiz, size: 18),
                label: const Text('Take Quiz'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: AppColors.surfaceLight,
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _showLoginPrompt(context),
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Quiz'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.terracotta,
                  side: const BorderSide(color: AppColors.terracotta),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _listenToStory(StoryModel story) async {
    final notifier = ref.read(audioNarrationProvider.notifier);
    final job = await notifier.generateNarration(
      storyId: story.id,
      language: NarrationJobModel.supportedLanguage(story.language),
    );

    if (!mounted) return;
    if (job == null || job.hasFailed) {
      final message =
          ref.read(audioNarrationProvider).errorMessage ??
          job?.errorMessage ??
          'Failed to generate the narration.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }

  Widget _buildCoverPlaceholder(StoryModel story) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.terracotta.withValues(alpha: 0.9),
            AppColors.ochre.withValues(alpha: 0.9),
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

  void _showLoginPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign In Required'),
        content: const Text('Please sign in to interact with stories and take quizzes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Navigation to login
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }
}

class _AuthorSection extends StatelessWidget {
  const _AuthorSection({required this.story});

  final StoryModel story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
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
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color ?? theme.colorScheme.onSurface, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

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
