import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_image.dart';
import '../../../core/widgets/griot_loader.dart';
import '../../audio/models/narration_job_model.dart';
import '../../audio/providers/audio_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/sign_in_prompt.dart';
import '../../gamification/providers/gamification_provider.dart';
import '../../gamification/screens/quiz_screen.dart';
import '../../gamification/widgets/quiz_picker_sheet.dart';
import '../../sharing/widgets/share_sheet.dart';
import '../models/story_model.dart';
import '../providers/story_provider.dart';
import '../widgets/story_actions.dart';

/// Story detail screen with interactive markdown reader.
///
/// Features:
/// - Full markdown rendering
/// - Reading progress tracking (own layout row — never over the title)
/// - Like / bookmark / flag / share actions
/// - Author info, cultural context, moral lesson
/// - "Take Quiz" CTA wired to the quizzes linked to this story
class StoryDetailScreen extends ConsumerStatefulWidget {
  const StoryDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends ConsumerState<StoryDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0;
  bool _isStartingQuiz = false;

  /// Throttle reading-progress writes: only persist when the percentage moves
  /// by at least this much. Previously every scroll event triggered a setState
  /// plus a SQLite write.
  static const int _progressStep = 2;

  int _lastPersistedPercent = 0;

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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.position.hasContentDimensions) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final progress = maxExtent <= 0
        ? 0.0
        : (_scrollController.offset / maxExtent).clamp(0.0, 1.0);

    if ((progress - _scrollProgress).abs() < 0.004) return;

    setState(() => _scrollProgress = progress);

    final percent = (progress * 100).round();
    if ((percent - _lastPersistedPercent).abs() < _progressStep &&
        percent < 95) {
      return;
    }
    _lastPersistedPercent = percent;
    ref
        .read(storyDetailProvider.notifier)
        .updateProgress(
          percent: percent,
          lastPosition: _scrollController.offset.round(),
          completed: percent >= 95,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final storyState = ref.watch(storyDetailProvider);
    final authState = ref.watch(authProvider);
    final isAuthenticated = authState.value?.isAuthenticated ?? false;

    return Scaffold(
      body: switch (storyState) {
        StoryDetailInitial() ||
        StoryDetailLoading() => const GriotLoadingState(label: 'Loading story'),
        StoryDetailFailure(:final message) => ErrorState(
          message: message,
          title: 'Failed to load story',
          onRetry: () {
            ref.read(storyDetailProvider.notifier).loadStory(widget.slug);
          },
        ),
        StoryDetailReady(:final story) => _buildStoryContent(
          story,
          theme,
          scheme,
          isAuthenticated,
        ),
      },
      bottomNavigationBar: switch (storyState) {
        StoryDetailReady(:final story) => _buildBottomBar(
          context,
          theme,
          scheme,
          story,
          isAuthenticated,
        ),
        _ => null,
      },
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
        // --- App bar ---
        SliverAppBar(
          expandedHeight: 240,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(
              left: AppSpacing.sectionLarge + AppSpacing.xs,
              right: AppSpacing.section,
              bottom: AppSpacing.lg,
            ),
            title: Text(
              story.title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            background: GriotImage(
              source: story.coverImage,
              blurhash: story.coverImageBlurhash,
              fit: BoxFit.cover,
              semanticLabel: story.title,
              placeholderIcon: AppIcons.auto_stories_outlined,
            ),
          ),
          // NOTE: the reading percentage deliberately does NOT live in
          // `actions`. It used to sit here as a pill, where it collided with the
          // collapsed title. It now has its own row below (see below).
          actions: [StoryActionsMenu(story: story)],
        ),

        // --- Reading progress: dedicated row, never over the title ---
        SliverToBoxAdapter(
          child: Container(
            color: scheme.surface,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: ProgressRow(
              fraction: _scrollProgress,
              label: _scrollProgress >= 0.95 ? 'Finished' : 'Read',
              thickness: 5,
            ),
          ),
        ),

        // --- Story content ---
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AuthorSection(story: story),
                const SizedBox(height: AppSpacing.section),

                // --- Region badge ---
                if (story.region.isNotEmpty) ...[
                  MetadataPill(
                    label: story.region,
                    icon: AppIcons.location_on,
                    color: AppColors.accentTextStrong,
                  ),
                  const SizedBox(height: AppSpacing.section),
                ],

                // --- Summary ---
                if (story.summary.isNotEmpty) ...[
                  AppCard(
                    color: scheme.secondaryContainer,
                    borderColor: AppColors.bronze.withValues(alpha: 0.35),
                    child: Text(
                      story.summary,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
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

                const SizedBox(height: AppSpacing.section),

                // --- Cultural context ---
                if (story.culturalContext.isNotEmpty) ...[
                  const _SectionTitle(
                    title: 'Cultural Context',
                    icon: AppIcons.museum_outlined,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    story.culturalContext,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.section),
                ],

                // --- Moral lesson ---
                if (story.moralLesson.isNotEmpty) ...[
                  const _SectionTitle(
                    title: 'Moral Lesson',
                    icon: AppIcons.lightbulb_outline,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppCard(
                    color: scheme.tertiaryContainer,
                    borderColor: AppColors.savannahGreen.withValues(alpha: 0.3),
                    child: Text(
                      story.moralLesson,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.section),
                ],

                const SizedBox(height: AppSpacing.lg),
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outline)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Listen (text-to-speech narration).
            IconButton(
              onPressed: isNarrating
                  ? null
                  : () => isAuthenticated
                        ? _listenToStory(story)
                        : _showLoginPrompt(context),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.bronze.withValues(alpha: 0.12),
                foregroundColor: AppColors.bronzeDark,
              ),
              icon: isNarrating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: GriotLoader.inline(color: AppColors.bronzeDark),
                    )
                  : const Icon(AppIcons.headphones),
              tooltip: isNarrating ? 'Generating narration…' : 'Listen',
            ),
            const SizedBox(width: AppSpacing.md),

            // Like.
            _ActionButton(
              icon: story.isLiked
                  ? AppIcons.favorite
                  : AppIcons.favorite_border,
              label: story.formattedLikeCount,
              color: story.isLiked ? scheme.error : null,
              onTap: isAuthenticated
                  ? () => ref.read(storyDetailProvider.notifier).toggleLike()
                  : () => _showLoginPrompt(context),
            ),
            const SizedBox(width: AppSpacing.lg),

            // Bookmark.
            _ActionButton(
              icon: story.isBookmarked
                  ? AppIcons.bookmark
                  : AppIcons.bookmark_border,
              label: story.formattedBookmarkCount,
              color: story.isBookmarked ? AppColors.bronzeDark : null,
              onTap: isAuthenticated
                  ? () =>
                        ref.read(storyDetailProvider.notifier).toggleBookmark()
                  : () => _showLoginPrompt(context),
            ),
            const SizedBox(width: AppSpacing.lg),

            // Share — previously an empty callback.
            _ActionButton(
              icon: AppIcons.share_outlined,
              label: 'Share',
              onTap: () => _shareStory(story),
            ),

            const Spacer(),

            // Take Quiz — previously an empty callback.
            if (isAuthenticated)
              FilledButton.icon(
                onPressed: _isStartingQuiz ? null : () => _takeQuiz(story),
                icon: _isStartingQuiz
                    ? const GriotLoader.inline(color: Colors.white)
                    : const Icon(AppIcons.quiz, size: 16),
                label: const Text('Take Quiz'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.bronze,
                  foregroundColor: AppColors.charcoal,
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _showLoginPrompt(
                  context,
                  message:
                      'Sign in to take the quiz for this story and earn XP.',
                ),
                icon: const Icon(AppIcons.lock_outline, size: 16),
                label: const Text('Quiz'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.bronzeDark,
                  side: const BorderSide(color: AppColors.bronze),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Take Quiz CTA.
  ///
  /// Quizzes are linked to stories by id in the local gamification store
  /// (`quizzesByStoryProvider`). Resolution order:
  ///   1 query — open it directly
  ///   0 quizzes — explain that the quiz is not published yet
  ///   >1 — let the reader pick (e.g. language variants)
  Future<void> _takeQuiz(StoryModel story) async {
    setState(() => _isStartingQuiz = true);
    try {
      // Make sure the quiz catalogue is loaded before filtering it.
      await ref.read(quizzesProvider.future);
      if (!mounted) return;

      final quizzes = ref.read(quizzesByStoryProvider(story.id));
      if (quizzes.isEmpty) {
        setState(() => _isStartingQuiz = false);
        await _showNoQuizDialog();
        return;
      }

      final quiz = quizzes.length == 1
          ? quizzes.first
          : await QuizPickerSheet.show(context, quizzes);

      if (!mounted) return;
      setState(() => _isStartingQuiz = false);
      if (quiz == null) return;
      await QuizScreen.open(context, quiz);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isStartingQuiz = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start the quiz: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showNoQuizDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(AppIcons.quiz_outlined, size: 40),
        title: const Text('Quiz coming soon'),
        content: const Text(
          'No quiz has been published for this story yet. Keep reading — new '
          'quizzes and badges are added regularly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _shareStory(StoryModel story) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareSheet(
        title: story.title,
        slug: story.slug,
        summary: story.summary,
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
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Sign-in prompt for gated actions. Delegates to [SignInPrompt] so every
  /// gate in the app behaves identically and actually opens the login route.
  void _showLoginPrompt(BuildContext context, {String? message}) {
    SignInPrompt.show(
      context,
      message:
          message ??
          'Please sign in to interact with stories and take quizzes.',
    );
  }
}

class _AuthorSection extends StatelessWidget {
  const _AuthorSection({required this.story});

  final StoryModel story;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final language = StoryLanguage.fromString(story.language);

    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.bronze.withValues(alpha: 0.16),
          child: Text(
            story.author.username.isNotEmpty
                ? story.author.username[0].toUpperCase()
                : '?',
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.bronzeDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
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
              Text(story.readTimeDisplay, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        // Language shown as a real icon + label instead of a flag emoji.
        MetadataPill(
          label: language.label,
          icon: AppIcons.language,
          color: scheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, color: AppColors.bronzeDark, size: 17),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.bronzeDark,
          ),
        ),
      ],
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

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? theme.colorScheme.onSurface, size: 22),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
