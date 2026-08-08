import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/video_provider.dart';

/// Bottom sheet for requesting AI video generation for a story.
///
/// Shows a prompt input, duration selector, and aspect ratio picker.
/// The user describes the visual style they want, and the backend
/// submits the request to Luma AI Dream Machine.
class VideoGenerationSheet extends ConsumerStatefulWidget {
  const VideoGenerationSheet({
    super.key,
    required this.storyId,
    required this.storyTitle,
  });

  final int storyId;
  final String storyTitle;

  static Future<void> show(
    BuildContext context, {
    required int storyId,
    required String storyTitle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          VideoGenerationSheet(storyId: storyId, storyTitle: storyTitle),
    );
  }

  @override
  ConsumerState<VideoGenerationSheet> createState() =>
      _VideoGenerationSheetState();
}

class _VideoGenerationSheetState extends ConsumerState<VideoGenerationSheet> {
  final _promptController = TextEditingController();
  final _promptFocusNode = FocusNode();
  int _selectedDuration = 10;
  String _selectedAspectRatio = '16:9';

  static const _durations = [5, 10, 15, 20, 30];
  static const _aspectRatios = [
    {'value': '16:9', 'label': 'Landscape', 'icon': Icons.crop_landscape},
    {'value': '9:16', 'label': 'Portrait', 'icon': Icons.crop_portrait},
    {'value': '1:1', 'label': 'Square', 'icon': Icons.crop_square},
  ];

  // Prompt suggestions for AI video generation.
  static const _promptSuggestions = [
    'Aerial view of a lush African savanna at golden hour',
    'Traditional village with thatched huts and dancing flames',
    'Majestic baobab tree silhouetted against a sunset sky',
    'River winding through dense tropical forest',
    'Ancient stone ruins covered in vines and moss',
  ];

  @override
  void dispose() {
    _promptController.dispose();
    _promptFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe the video you want to generate'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final notifier = ref.read(videoGenerationProvider.notifier);
    final job = await notifier.createVideo(
      storyId: widget.storyId,
      prompt: prompt,
      duration: _selectedDuration,
      aspectRatio: _selectedAspectRatio,
    );

    if (mounted && job != null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎬 Video generation started! We\'ll notify you when it\'s ready.',
          ),
          backgroundColor: AppColors.savannahGreen,
          duration: const Duration(seconds: 4),
        ),
      );
    } else if (mounted) {
      final error = ref.read(videoGenerationProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Failed to start video generation'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = ref.watch(videoGenerationProvider).isCreating;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _buildDragHandle(),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    bottom: bottomPadding + 24,
                  ),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildPromptSection(),
                    const SizedBox(height: 24),
                    _buildDurationSection(),
                    const SizedBox(height: 24),
                    _buildAspectRatioSection(),
                    const SizedBox(height: 32),
                    _buildSubmitButton(isCreating),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.charcoalMuted.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.terracotta.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.movie_creation_outlined,
                color: AppColors.terracotta,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generate AI Video',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.storyTitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.charcoalMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: AppColors.charcoalMuted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPromptSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Describe your video',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Describe the visual style, mood, and imagery you want for the story video.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _promptController,
          focusNode: _promptFocusNode,
          maxLines: 4,
          minLines: 3,
          decoration: InputDecoration(
            hintText:
                'e.g. "Aerial view of a lush African savanna at golden hour, with warm light filtering through acacia trees..."',
            hintStyle: TextStyle(
              color: AppColors.charcoalMuted.withValues(alpha: 0.5),
              fontSize: 14,
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.charcoalMuted.withValues(alpha: 0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.charcoalMuted.withValues(alpha: 0.2),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.terracotta,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
          style: const TextStyle(fontSize: 14),
        ),
        const SizedBox(height: 12),
        // Prompt suggestions.
        Text('Suggestions', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _promptSuggestions.map((suggestion) {
            return ActionChip(
              label: Text(
                suggestion,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: AppColors.charcoalMuted.withValues(alpha: 0.2),
              ),
              onPressed: () {
                _promptController.text = suggestion;
                _promptController.selection = TextSelection.fromPosition(
                  TextPosition(offset: suggestion.length),
                );
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDurationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Duration', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: _durations.map((duration) {
            final isSelected = _selectedDuration == duration;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedDuration = duration),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.terracotta : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.terracotta
                            : AppColors.charcoalMuted.withValues(alpha: 0.2),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.terracotta.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${duration}s',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : AppColors.charcoal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          duration <= 10
                              ? 'Short'
                              : duration <= 20
                              ? 'Medium'
                              : 'Long',
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                                ? Colors.white70
                                : AppColors.charcoalMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAspectRatioSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Aspect Ratio', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: _aspectRatios.map((ratio) {
            final isSelected = _selectedAspectRatio == ratio['value'];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(
                    () => _selectedAspectRatio = ratio['value']! as String,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.terracotta : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.terracotta
                            : AppColors.charcoalMuted.withValues(alpha: 0.2),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.terracotta.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          ratio['icon'] as IconData,
                          color: isSelected
                              ? Colors.white
                              : AppColors.charcoalMuted,
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ratio['label'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : AppColors.charcoal,
                          ),
                        ),
                        Text(
                          ratio['value'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                                ? Colors.white70
                                : AppColors.charcoalMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(bool isCreating) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isCreating ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.terracotta,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.terracotta.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 2,
          shadowColor: AppColors.terracotta.withValues(alpha: 0.4),
        ),
        child: isCreating
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Generating...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Generate Video',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }
}
