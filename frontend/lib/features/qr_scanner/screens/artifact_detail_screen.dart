import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../audio/models/narration_job_model.dart';
import '../../audio/providers/audio_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../stories/models/story_model.dart';
import '../services/qr_api_service.dart';

/// Full-screen detail view for a museum artifact.
///
/// Shows artifact information, images, cultural context,
/// related stories, and QR code for sharing.
class ArtifactDetailScreen extends ConsumerWidget {
  const ArtifactDetailScreen({super.key, required this.artifact});

  final ArtifactModel artifact;

  static void open(BuildContext context, ArtifactModel artifact) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtifactDetailScreen(artifact: artifact),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero image with app bar
          _buildSliverAppBar(context),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category badge
                  _buildCategoryBadge(),
                  const SizedBox(height: 12),

                  // Title
                  Text(
                    artifact.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),

                  // Culture & Region
                  if (artifact.culture.isNotEmpty || artifact.region.isNotEmpty)
                    _buildMetadataRow(context),

                  const SizedBox(height: 20),

                  // Description
                  if (artifact.description.isNotEmpty) ...[
                    Text(
                      'About This Artifact',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      artifact.description,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.6),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Audio guide (text-to-speech narration)
                  const SizedBox(height: 20),
                  _buildAudioGuide(context, ref),

                  // Physical details
                  _buildPhysicalDetails(context),

                  // Museum location
                  if (artifact.museumName.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildMuseumLocation(context),
                  ],

                  // Related stories
                  if (artifact.stories.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildRelatedStories(context, ref),
                  ],

                  // Scan count
                  if (artifact.scanCount > 0) ...[
                    const SizedBox(height: 20),
                    _buildScanStats(context),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: Colors.black,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (artifact.imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: artifact.imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(color: AppColors.terracotta),
                ),
                errorWidget: (_, _, _) => Container(
                  color: AppColors.parchmentDark,
                  child: Center(
                    child: Text(
                      artifact.categoryEmoji,
                      style: const TextStyle(fontSize: 64),
                    ),
                  ),
                ),
              )
            else
              Container(
                color: AppColors.parchmentDark,
                child: Center(
                  child: Text(
                    artifact.categoryEmoji,
                    style: const TextStyle(fontSize: 80),
                  ),
                ),
              ),

            // Gradient overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.3),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.terracottaTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(artifact.categoryEmoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(
            artifact.categoryLabel,
            style: const TextStyle(
              color: AppColors.terracotta,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        if (artifact.culture.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.people_outline,
                size: 16,
                color: AppColors.charcoalMuted,
              ),
              const SizedBox(width: 4),
              Text(
                artifact.culture,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.charcoalMuted,
                ),
              ),
            ],
          ),
        if (artifact.region.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.place_outlined,
                size: 16,
                color: AppColors.charcoalMuted,
              ),
              const SizedBox(width: 4),
              Text(
                artifact.region,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.charcoalMuted,
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// Card offering a narrated audio guide for this artifact.
  Widget _buildAudioGuide(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final narrationState = ref.watch(audioNarrationProvider);
    final authState = ref.watch(authProvider);
    final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;
    final isGenerating = narrationState.isGenerating;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.terracotta.withValues(alpha: 0.1),
            AppColors.ochre.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.terracotta.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.terracotta,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.headphones, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audio Guide',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isGenerating
                      ? 'Generating narration…'
                      : 'Listen to the story of this artifact',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.charcoalMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isGenerating)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.terracotta,
                ),
              ),
            )
          else
            IconButton.filled(
              onPressed: isAuthenticated
                  ? () => _generateArtifactNarration(context, ref)
                  : () => _showLoginPrompt(context),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.terracotta,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.play_arrow_rounded),
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
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    } else if (job.isCompleted && job.audioUrl.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎧 Playing “${artifact.title}”'),
          backgroundColor: AppColors.savannahGreen,
        ),
      );
    }
  }

  void _showLoginPrompt(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Sign in to listen to audio guides'),
        action: SnackBarAction(
          label: 'Sign In',
          onPressed: () {
            // Navigation to login is handled by the auth wrapper.
          },
        ),
      ),
    );
  }

  Widget _buildPhysicalDetails(BuildContext context) {
    final details = <MapEntry<String, String>>[];

    if (artifact.estimatedDate.isNotEmpty) {
      details.add(MapEntry('Period', artifact.estimatedDate));
    }
    if (artifact.materials.isNotEmpty) {
      details.add(MapEntry('Materials', artifact.materials));
    }
    if (artifact.dimensions.isNotEmpty) {
      details.add(MapEntry('Dimensions', artifact.dimensions));
    }

    if (details.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.charcoalMuted.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Physical Details',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          ...details.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.charcoalMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMuseumLocation(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ochreTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.museum, color: AppColors.ochre, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artifact.museumName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: AppColors.charcoal),
                ),
                if (artifact.floor.isNotEmpty ||
                    artifact.displayCase.isNotEmpty)
                  Text(
                    [
                      if (artifact.floor.isNotEmpty) 'Floor: ${artifact.floor}',
                      if (artifact.displayCase.isNotEmpty)
                        'Case: ${artifact.displayCase}',
                    ].join(' • '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.charcoalMuted,
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
    final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Related Stories', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: artifact.stories.length,
            itemBuilder: (context, index) {
              final story = artifact.stories[index];
              return _RelatedStoryCard(
                story: story,
                isAuthenticated: isAuthenticated,
                onListen: () {
                  if (!isAuthenticated) {
                    _showLoginPrompt(context);
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
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }

  Widget _buildScanStats(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.qr_code_scanner,
          size: 16,
          color: AppColors.charcoalMuted,
        ),
        const SizedBox(width: 8),
        Text(
          '${artifact.scanCount} scan${artifact.scanCount == 1 ? '' : 's'}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.charcoalMuted),
        ),
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
    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.charcoalMuted.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            story.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              IconButton(
                onPressed: onListen,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.terracotta.withValues(alpha: 0.1),
                  foregroundColor: AppColors.terracotta,
                ),
                iconSize: 18,
                icon: Icon(
                  isAuthenticated
                      ? Icons.play_arrow_rounded
                      : Icons.lock_outline,
                ),
                tooltip: isAuthenticated
                    ? 'Listen to this story'
                    : 'Sign in to listen',
              ),
              const Spacer(),
              Text(
                story.language.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.terracotta,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
