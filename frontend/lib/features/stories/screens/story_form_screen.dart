import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../models/story_model.dart';
import '../providers/story_provider.dart';

/// Story submission form for contributors.
///
/// Features:
/// - Create new stories
/// - Edit existing stories
/// - Rich text content with markdown preview
/// - Category selection
/// - Language and region selection
/// - Tags input
/// - Save as draft or submit for review
class StoryFormScreen extends ConsumerStatefulWidget {
  const StoryFormScreen({
    super.key,
    this.existingStory,
  });

  final StoryModel? existingStory;

  @override
  ConsumerState<StoryFormScreen> createState() => _StoryFormScreenState();
}

class _StoryFormScreenState extends ConsumerState<StoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _summaryController;
  late TextEditingController _tagsController;
  late TextEditingController _regionController;
  late TextEditingController _culturalContextController;
  late TextEditingController _moralLessonController;
  late TextEditingController _sourceController;

  String _selectedLanguage = 'en';
  List<int> _selectedCategoryIds = [];
  bool _isPreviewMode = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Initialize controllers with existing story data
    final story = widget.existingStory;
    _titleController = TextEditingController(text: story?.title ?? '');
    _contentController = TextEditingController(text: story?.content ?? '');
    _summaryController = TextEditingController(text: story?.summary ?? '');
    _tagsController = TextEditingController(text: story?.tags ?? '');
    _regionController = TextEditingController(text: story?.region ?? '');
    _culturalContextController =
        TextEditingController(text: story?.culturalContext ?? '');
    _moralLessonController =
        TextEditingController(text: story?.moralLesson ?? '');
    _sourceController = TextEditingController(text: story?.source ?? '');

    if (story != null) {
      _selectedLanguage = story.language;
      _selectedCategoryIds = story.categories.map((c) => c.id).toList();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _summaryController.dispose();
    _tagsController.dispose();
    _regionController.dispose();
    _culturalContextController.dispose();
    _moralLessonController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  bool get isEditing => widget.existingStory != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Story' : 'Create Story'),
        actions: [
          // Preview toggle
          IconButton(
            icon: Icon(_isPreviewMode ? Icons.edit : Icons.preview),
            onPressed: () {
              setState(() => _isPreviewMode = !_isPreviewMode);
            },
            tooltip: _isPreviewMode ? 'Edit' : 'Preview',
          ),
          // Save button
          TextButton(
            onPressed: _isSaving ? null : _handleSave,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _isPreviewMode
          ? _buildPreview(theme)
          : _buildForm(theme, categories),
      bottomNavigationBar: _buildBottomBar(theme),
    );
  }

  Widget _buildForm(ThemeData theme, AsyncValue<List<StoryCategory>> categories) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Title ---
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Story Title',
                hintText: 'Enter a compelling title',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                if (value.trim().length < 5) {
                  return 'Title must be at least 5 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // --- Summary ---
            TextFormField(
              controller: _summaryController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Summary',
                hintText: 'Brief summary for story previews',
                alignLabelWithHint: true,
              ),
              validator: (value) {
                if (value != null && value.length > 500) {
                  return 'Summary must be 500 characters or less';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // --- Content ---
            Text(
              'Story Content (Markdown)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _contentController,
              maxLines: null,
              minLines: 15,
              decoration: const InputDecoration(
                hintText: 'Write your story here...\n\nUse Markdown for formatting:\n# Heading\n## Subheading\n**bold** *italic*\n\n> Blockquote\n\n- List item',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter story content';
                }
                if (value.trim().length < 50) {
                  return 'Story content must be at least 50 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // --- Language ---
            DropdownButtonFormField<String>(
              initialValue: _selectedLanguage,
              decoration: const InputDecoration(
                labelText: 'Language',
              ),
              items: StoryLanguage.values.map((lang) {
                return DropdownMenuItem(
                  value: lang.value,
                  child: Text('${lang.flag} ${lang.label}'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedLanguage = value);
                }
              },
            ),
            const SizedBox(height: 20),

            // --- Categories ---
            Text(
              'Categories',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            categories.when(
              data: (cats) {
                if (cats.isEmpty) {
                  return const Text('No categories available');
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cats.map((cat) {
                    final isSelected = _selectedCategoryIds.contains(cat.id);
                    return FilterChip(
                      label: Text('${cat.icon} ${cat.name}'),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCategoryIds.add(cat.id);
                          } else {
                            _selectedCategoryIds.remove(cat.id);
                          }
                        });
                      },
                    );
                  }).toList(),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (error, stack) => const Text('Failed to load categories'),
            ),
            const SizedBox(height: 20),

            // --- Region ---
            TextFormField(
              controller: _regionController,
              decoration: const InputDecoration(
                labelText: 'Region of Origin',
                hintText: 'e.g., Northwest Region, Cameroon',
              ),
            ),
            const SizedBox(height: 20),

            // --- Tags ---
            TextFormField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'Comma-separated tags (e.g., folktale, moral, wisdom)',
              ),
            ),
            const SizedBox(height: 20),

            // --- Cultural Context ---
            TextFormField(
              controller: _culturalContextController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Cultural Context',
                hintText: 'Historical and cultural background for the story',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),

            // --- Moral Lesson ---
            TextFormField(
              controller: _moralLessonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Moral Lesson',
                hintText: 'Key teaching or message from the story',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),

            // --- Source ---
            TextFormField(
              controller: _sourceController,
              decoration: const InputDecoration(
                labelText: 'Source',
                hintText: 'Original source or teller of the story',
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            _titleController.text.isEmpty
                ? 'Untitled Story'
                : _titleController.text,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Summary
          if (_summaryController.text.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.ochreTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _summaryController.text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Content preview
          if (_contentController.text.isNotEmpty)
            Text(
              _contentController.text,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
            ),

          // Metadata preview
          if (_regionController.text.isNotEmpty ||
              _tagsController.text.isNotEmpty) ...[
            const Divider(height: 40),
            if (_regionController.text.isNotEmpty) ...[
              Text(
                'Region: ${_regionController.text}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
            ],
            if (_tagsController.text.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tagsController.text
                    .split(',')
                    .map((tag) => tag.trim())
                    .where((tag) => tag.isNotEmpty)
                    .map((tag) {
                  return Chip(
                    label: Text(tag),
                    backgroundColor: AppColors.terracotta.withValues(alpha: 0.1),
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Save as Draft
          Expanded(
            child: OutlinedButton(
              onPressed: _isSaving ? null : () => _handleSave(draft: true),
              child: const Text('Save Draft'),
            ),
          ),
          const SizedBox(width: 12),
          // Submit for Review
          Expanded(
            child: FilledButton(
              onPressed: _isSaving ? null : () => _handleSave(draft: false),
              child: const Text('Submit for Review'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSave({bool draft = true}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final repository = ref.read(storyRepositoryProvider);

      if (isEditing) {
        // Update existing story
        await repository.updateStory(
          widget.existingStory!.slug,
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          summary: _summaryController.text.trim(),
          categoryIds: _selectedCategoryIds.isNotEmpty
              ? _selectedCategoryIds
              : null,
          language: _selectedLanguage,
          region: _regionController.text.trim().isNotEmpty
              ? _regionController.text.trim()
              : null,
          tags: _tagsController.text.trim().isNotEmpty
              ? _tagsController.text.trim()
              : null,
          status: draft ? 'draft' : 'pending',
        );
      } else {
        // Create new story
        await repository.createStory(
          title: _titleController.text.trim(),
          content: _contentController.text.trim(),
          summary: _summaryController.text.trim().isNotEmpty
              ? _summaryController.text.trim()
              : null,
          categoryIds: _selectedCategoryIds.isNotEmpty
              ? _selectedCategoryIds
              : null,
          language: _selectedLanguage,
          region: _regionController.text.trim().isNotEmpty
              ? _regionController.text.trim()
              : null,
          tags: _tagsController.text.trim().isNotEmpty
              ? _tagsController.text.trim()
              : null,
          culturalContext: _culturalContextController.text.trim().isNotEmpty
              ? _culturalContextController.text.trim()
              : null,
          moralLesson: _moralLessonController.text.trim().isNotEmpty
              ? _moralLessonController.text.trim()
              : null,
          source: _sourceController.text.trim().isNotEmpty
              ? _sourceController.text.trim()
              : null,
        );
      }

      // Refresh my stories
      ref.invalidate(myStoriesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              draft ? 'Story saved as draft' : 'Story submitted for review',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save story: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}