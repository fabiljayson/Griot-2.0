import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/story_model.dart';
import '../providers/story_provider.dart';

/// Story actions menu (bookmark, like, flag, share).
class StoryActionsMenu extends ConsumerWidget {
  const StoryActionsMenu({
    super.key,
    required this.story,
  });

  final StoryModel story;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;

    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_vert,
        color: Colors.white,
      ),
      onSelected: (value) => _handleAction(context, ref, value, isAuthenticated),
      itemBuilder: (context) => [
        // Bookmark
        PopupMenuItem(
          value: 'bookmark',
          child: Row(
            children: [
              Icon(
                story.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                color: story.isBookmarked ? AppColors.ochre : null,
              ),
              const SizedBox(width: 12),
              Text(story.isBookmarked ? 'Remove Bookmark' : 'Bookmark'),
            ],
          ),
        ),

        // Like
        PopupMenuItem(
          value: 'like',
          child: Row(
            children: [
              Icon(
                story.isLiked ? Icons.favorite : Icons.favorite_border,
                color: story.isLiked ? AppColors.error : null,
              ),
              const SizedBox(width: 12),
              Text(story.isLiked ? 'Unlike' : 'Like'),
            ],
          ),
        ),

        const PopupMenuDivider(),

        // Flag
        PopupMenuItem(
          value: 'flag',
          child: Row(
            children: [
              const Icon(Icons.flag_outlined, color: AppColors.error),
              const SizedBox(width: 12),
              Text(
                'Flag Cultural Inaccuracy',
                style: TextStyle(color: AppColors.error),
              ),
            ],
          ),
        ),

        // Share
        PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              const Icon(Icons.share_outlined),
              const SizedBox(width: 12),
              const Text('Share'),
            ],
          ),
        ),
      ],
    );
  }

  void _handleAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    bool isAuthenticated,
  ) {
    if (!isAuthenticated && (action == 'bookmark' || action == 'like' || action == 'flag')) {
      _showLoginPrompt(context);
      return;
    }

    switch (action) {
      case 'bookmark':
        ref.read(storyDetailProvider.notifier).toggleBookmark();
        break;
      case 'like':
        ref.read(storyDetailProvider.notifier).toggleLike();
        break;
      case 'flag':
        _showFlagDialog(context, ref);
        break;
      case 'share':
        _shareStory(context);
        break;
    }
  }

  void _showLoginPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign In Required'),
        content: const Text('Please sign in to interact with stories.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Navigation to login would be handled by auth wrapper
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  void _showFlagDialog(BuildContext context, WidgetRef ref) {
    String? selectedReason;
    final detailsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          icon: const Icon(
            Icons.flag_outlined,
            color: AppColors.error,
            size: 48,
          ),
          title: const Text('Flag Cultural Inaccuracy'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Help us maintain cultural accuracy. Select the reason for flagging:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedReason,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'cultural_inaccuracy',
                    child: Text('Cultural Inaccuracy'),
                  ),
                  DropdownMenuItem(
                    value: 'inappropriate_content',
                    child: Text('Inappropriate Content'),
                  ),
                  DropdownMenuItem(
                    value: 'copyright_violation',
                    child: Text('Copyright Violation'),
                  ),
                  DropdownMenuItem(
                    value: 'wrong_category',
                    child: Text('Wrong Category'),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text('Other'),
                  ),
                ],
                onChanged: (value) {
                  setState(() => selectedReason = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: detailsController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Additional details (optional)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                detailsController.dispose();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              onPressed: selectedReason == null
                  ? null
                  : () async {
                      try {
                        await ref.read(storyDetailProvider.notifier).flagStory(
                              reason: selectedReason!,
                              details: detailsController.text.isNotEmpty
                                  ? detailsController.text
                                  : null,
                            );
                        if (context.mounted) {
                          detailsController.dispose();
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Thank you for your report. We will review it shortly.'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to submit report: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
              child: const Text('Submit Report'),
            ),
          ],
        ),
      ),
    );
  }

  void _shareStory(BuildContext context) {
    // TODO: Implement share functionality (Phase 8)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share functionality coming soon!'),
      ),
    );
  }
}

/// Quick action buttons row for story cards.
class StoryQuickActions extends ConsumerWidget {
  const StoryQuickActions({
    super.key,
    required this.story,
  });

  final StoryModel story;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like button
        IconButton(
          icon: Icon(
            story.isLiked ? Icons.favorite : Icons.favorite_border,
            color: story.isLiked ? AppColors.error : null,
            size: 20,
          ),
          onPressed: () {
            if (!isAuthenticated) {
              _showLoginPrompt(context);
              return;
            }
            ref.read(storyListProvider.notifier).toggleLike(story.slug);
          },
          tooltip: 'Like',
        ),

        // Bookmark button
        IconButton(
          icon: Icon(
            story.isBookmarked ? Icons.bookmark : Icons.bookmark_border,
            color: story.isBookmarked ? AppColors.ochre : null,
            size: 20,
          ),
          onPressed: () {
            if (!isAuthenticated) {
              _showLoginPrompt(context);
              return;
            }
            ref.read(storyListProvider.notifier).toggleBookmark(story.slug);
          },
          tooltip: 'Bookmark',
        ),
      ],
    );
  }

  void _showLoginPrompt(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Sign in to interact with stories'),
        action: SnackBarAction(
          label: 'Sign In',
          onPressed: () {
            // Navigation to login would be handled by auth wrapper
          },
        ),
      ),
    );
  }
}