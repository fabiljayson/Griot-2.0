import 'package:flutter/material.dart';
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
import '../../stories/models/story_model.dart';
import '../services/qr_api_service.dart';

/// Full-screen detail view for a museum artifact.
///
/// Shows the artifact's photograph, catalogue metadata, cultural context,
/// related stories and its narrated audio guide.
///
/// Previously every panel on this screen was hardcoded `Colors.white` /
/// `AppColors.parchmentDark` with `charcoalMuted` ink and an emoji glyph stood
/// in for the artifact's category — so on dark themes it was a stack of bright
/// light-mode panels, and on every theme the category was rendered as emoji
/// text instead of an icon.
class ArtifactDetailScreen extends ConsumerWidget {
  const ArtifactDetailScreen({super.key, required this.artifact});

  final ArtifactModel artifact;

  static Future<void> open(BuildContext context, ArtifactModel artifact) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtifactDetailScreen(artifact: artifact),
      ),
    );
  }

  /// Icon representing the artifact's category (never an emoji).
  FaIconData get _categoryIcon =>
      AppIcons.artifactCategory(artifact.category);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MetadataPill(
                    label: artifact.categoryLabel,
                    icon: _categoryIcon,
                    color: AppColors.bronze,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  Text(
                    artifact.title,
                    style: theme.textTheme.headlineMedium,
                  ),

                  if (artifact.culture.isNotEmpty ||
                      artifact.region.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _buildMetadataRow(context),
                  ],

                  if (artifact.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    const SectionHeader(
                      title: 'About This Artifact',
                      icon: AppIcons.info_outline,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      artifact.description,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.xl),
                  _buildAudioGuide(context, ref),

                  if (_physicalDetails.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _buildPhysicalDetails(context),
                  ],

                  if (artifact.museumName.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _buildMuseumLocation(context),
                  ],

                  if (artifact.stories.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _buildRelatedStories(context, ref),
                  ],

                  if (artifact.scanCount > 0) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _buildScanStats(context),
                  ],

                  const SizedBox(height: AppSpacing.sectionLarge),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: scheme.surface,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            GriotImage(
              source: artifact.imageUrl,
              blurhash: artifact.imageBlurhash,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              placeholderIcon: _categoryIcon,
              semanticLabel: artifact.title,
            ),

            // Legibility scrim for the app bar's back button / title over a
            // photograph. This is a neutral black scrim, not a brand gradient.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.35),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.25),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataRow(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        if (artifact.culture.isNotEmpty)
          _MetadataEntry(
            icon: AppIcons.people_outline,
            label: artifact.culture,
          ),
        if (artifact.region.isNotEmpty)
          _MetadataEntry(
            icon: AppIcons.place_outlined,
            label: artifact.region,
          ),
        if (artifact.isPublished)
          MetadataPill(
            label: 'Published',
            icon: AppIcons.check_circle,
            color: scheme.tertiary,
          ),
      ],
    );
  }

  /// Card offering a narrated audio guide for this artifact.
  Widget _buildAudioGuide(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final narrationState = ref.watch(audioNarrationProvider);
    final authState = ref.watch(authProvider);
    final isAuthenticated = authState.value?.isAuthenticated ?? false;
    final isGenerating = narrationState.isGenerating;

    return AppCard(
      color: scheme.secondaryContainer,
      borderColor: scheme.secondary.withValues(alpha: 0.35),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm + 2),
            decoration: BoxDecoration(
              color: scheme.secondary,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: FaIcon(
              AppIcons.headphones,
              color: scheme.onSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audio Guide',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isGenerating
                      ? 'Generating narration…'
                      : 'Listen to the story of this artifact',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (isGenerating)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: const GriotLoader(size: 22),
            )
          else
            IconButton.filled(
              onPressed: isAuthenticated
                  ? () => _generateArtifactNarration(context, ref)
                  : () => SignInPrompt.show(
                      context,
                      message:
                          'Sign in to play the narrated audio guide for this '
                          'artifact.',
                    ),
              style: IconButton.styleFrom(
                backgroundColor: scheme.secondary,
                foregroundColor: scheme.onSecondary,
              ),
              icon: const FaIcon(AppIcons.play_arrow_rounded),
              tooltip: 'Play audio guide',
            ),
        ],
      ),
    );
  }

  Future<void> _generateArtifactNarration(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final notifier = ref.read(audioNarrationProvider.notifier);
    final job = await notifier.generateNarration(artifactId: artifact.id);

    if (!context.mounted) return;
    if (job == null || job.hasFailed) {
      final message =
          ref.read(audioNarrationProvider).errorMessage ??
          job?.errorMessage ??
          'Failed to generate the audio guide.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } else if (job.isCompleted && job.audioUrl.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Narration ready: ${artifact.title}')),
      );
    }
  }

  /// Period / materials / dimensions, in the webapp's label-value layout.
  List<MapEntry<String, String>> get _physicalDetails => [
    if (artifact.estimatedDate.isNotEmpty)
      MapEntry('Period', artifact.estimatedDate),
    if (artifact.materials.isNotEmpty)
      MapEntry('Materials', artifact.materials),
    if (artifact.dimensions.isNotEmpty)
      MapEntry('Dimensions', artifact.dimensions),
  ];

  Widget _buildPhysicalDetails(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Physical Details',
            icon: AppIcons.layerGroup,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final entry in _physicalDetails)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      entry.key,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMuseumLocation(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final location = [
      if (artifact.floor.isNotEmpty) 'Floor: ${artifact.floor}',
      if (artifact.displayCase.isNotEmpty) 'Case: ${artifact.displayCase}',
    ].join(' • ');

    return AppCard(
      color: scheme.primaryContainer,
      borderColor: scheme.primary.withValues(alpha: 0.3),
      child: Row(
        children: [
          FaIcon(AppIcons.museum, color: scheme.primary, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artifact.museumName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                if (location.isNotEmpty)
                  Text(
                    location,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedStories(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isAuthenticated = authState.value?.isAuthenticated ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Related Stories',
          icon: AppIcons.auto_stories_outlined,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: artifact.stories.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final story = artifact.stories[index];
              return _RelatedStoryCard(
                story: story,
                isAuthenticated: isAuthenticated,
                onListen: () {
                  if (!isAuthenticated) {
                    SignInPrompt.show(
                      context,
                      message: 'Sign in to listen to this story.',
                    );
                    return;
                  }
                  _generateStoryNarration(context, ref, story);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _generateStoryNarration(
    BuildContext context,
    WidgetRef ref,
    StoryModel story,
  ) async {
    final notifier = ref.read(audioNarrationProvider.notifier);
    final job = await notifier.generateNarration(
      storyId: story.id,
      language: NarrationJobModel.supportedLanguage(story.language),
    );

    if (!context.mounted) return;
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

  Widget _buildScanStats(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        FaIcon(
          AppIcons.qr_code_scanner,
          size: 15,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '${artifact.scanCount} scan${artifact.scanCount == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// One icon + text metadata entry (culture, region).
class _MetadataEntry extends StatelessWidget {
  const _MetadataEntry({required this.icon, required this.label});

  final FaIconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FaIcon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs + 1),
        Text(label, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Horizontal story card with a play button to start its narration.
class _RelatedStoryCard extends StatelessWidget {
  const _RelatedStoryCard({
    required this.story,
    required this.isAuthenticated,
    required this.onListen,
  });

  final StoryModel story;
  final bool isAuthenticated;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      width: 176,
      child: AppCard(
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
            const Spacer(),
            Row(
              children: [
                IconButton(
                  onPressed: onListen,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.bronze.withValues(alpha: 0.12),
                    foregroundColor: AppColors.bronzeDark,
                  ),
                  iconSize: 18,
                  icon: FaIcon(
                    isAuthenticated
                        ? AppIcons.play_arrow_rounded
                        : AppIcons.lock_outline,
                  ),
                  tooltip: isAuthenticated
                      ? 'Listen to this story'
                      : 'Sign in to listen',
                ),
                const Spacer(),
                MetadataPill(
                  label: story.language.toUpperCase(),
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
