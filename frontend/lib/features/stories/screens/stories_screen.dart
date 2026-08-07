import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../core/theme/app_colors.dart';
import '../models/story_model.dart';
import '../providers/story_provider.dart';
import '../widgets/story_card.dart';
import 'story_detail_screen.dart';

/// Discovery dashboard for browsing and discovering stories.
///
/// Features:
/// - Masonry grid layout
/// - Search bar with fuzzy search
/// - Category chips for filtering
/// - Language and region filters
/// - Sort options
/// - Pull-to-refresh
/// - Infinite scroll pagination
class StoriesScreen extends ConsumerStatefulWidget {
  const StoriesScreen({super.key});

  @override
  ConsumerState<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends ConsumerState<StoriesScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    // Load stories on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(storyListProvider.notifier).loadStories(refresh: true);
    });

    // Infinite scroll
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(storyListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storyState = ref.watch(storyListProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      body: Column(
        children: [
          // --- Search bar ---
          _SearchBar(
            controller: _searchController,
            onSearch: (query) {
              ref.read(storyListProvider.notifier).search(query);
            },
            onFilterToggle: () {
              setState(() => _showFilters = !_showFilters);
            },
            showFilters: _showFilters,
          ),

          // --- Filters ---
          if (_showFilters)
            _FilterChips(
              storyState: storyState,
              categories: categories,
              onLanguageChanged: (lang) {
                ref.read(storyListProvider.notifier).filterByLanguage(lang);
              },
              onCategoryChanged: (cat) {
                ref.read(storyListProvider.notifier).filterByCategory(cat);
              },
              onSortChanged: (sort) {
                ref.read(storyListProvider.notifier).sortBy(sort);
              },
              onClearFilters: () {
                ref.read(storyListProvider.notifier).clearFilters();
                _searchController.clear();
              },
            ),

          // --- Story grid ---
          Expanded(
            child: _buildStoryGrid(storyState, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryGrid(StoryListState state, ThemeData theme) {
    if (state.isLoading && state.stories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.errorMessage != null && state.stories.isEmpty) {
      return _ErrorWidget(
        message: state.errorMessage!,
        onRetry: () {
          ref.read(storyListProvider.notifier).loadStories(refresh: true);
        },
      );
    }

    if (state.stories.isEmpty) {
      return _EmptyWidget(
        message: state.searchQuery.isNotEmpty
            ? 'No stories found for "${state.searchQuery}"'
            : 'No stories yet. Be the first to share!',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(storyListProvider.notifier).loadStories(refresh: true);
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Stories grid
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: _getCrossAxisCount(context),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childCount: state.stories.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == state.stories.length) {
                  // Loading indicator at the end
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final story = state.stories[index];
                return StoryCard(
                  story: story,
                  onTap: () => _navigateToStory(story),
                  onBookmark: () {
                    ref.read(storyListProvider.notifier).toggleBookmark(story.slug);
                  },
                  onLike: () {
                    ref.read(storyListProvider.notifier).toggleLike(story.slug);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 4;
    if (width > 800) return 3;
    if (width > 500) return 2;
    return 1;
  }

  void _navigateToStory(StoryModel story) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryDetailScreen(slug: story.slug),
      ),
    );
  }
}

/// Search bar widget.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onSearch,
    required this.onFilterToggle,
    required this.showFilters,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final VoidCallback onFilterToggle;
  final bool showFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Search stories...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          controller.clear();
                          onSearch('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onSubmitted: onSearch,
              onChanged: (value) {
                // Debounce search could be added here
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              showFilters ? Icons.filter_list_off : Icons.filter_list,
              color: showFilters ? AppColors.terracotta : null,
            ),
            onPressed: onFilterToggle,
            tooltip: 'Filters',
          ),
        ],
      ),
    );
  }
}

/// Filter chips widget.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.storyState,
    required this.categories,
    required this.onLanguageChanged,
    required this.onCategoryChanged,
    required this.onSortChanged,
    required this.onClearFilters,
  });

  final StoryListState storyState;
  final AsyncValue<List<StoryCategory>> categories;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFilters = storyState.selectedLanguage != null ||
        storyState.selectedCategory != null ||
        storyState.selectedRegion != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Language filter
          Text(
            'Language',
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('All'),
                selected: storyState.selectedLanguage == null,
                onSelected: (_) => onLanguageChanged(null),
              ),
              ...StoryLanguage.values.map((lang) {
                return FilterChip(
                  label: Text('${lang.flag} ${lang.label}'),
                  selected: storyState.selectedLanguage == lang.value,
                  onSelected: (_) {
                    onLanguageChanged(
                      storyState.selectedLanguage == lang.value
                          ? null
                          : lang.value,
                    );
                  },
                );
              }),
            ],
          ),
          const SizedBox(height: 12),

          // Category filter
          categories.when(
            data: (cats) {
              if (cats.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: storyState.selectedCategory == null,
                        onSelected: (_) => onCategoryChanged(null),
                      ),
                      ...cats.map((cat) {
                        return FilterChip(
                          label: Text('${cat.icon} ${cat.name}'),
                          selected: storyState.selectedCategory == cat.slug,
                          onSelected: (_) {
                            onCategoryChanged(
                              storyState.selectedCategory == cat.slug
                                  ? null
                                  : cat.slug,
                            );
                          },
                        );
                      }),
                    ],
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, stack) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),

          // Sort & clear
          Row(
            children: [
              Text(
                'Sort by',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: storyState.sortBy,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(
                    value: '-created_at',
                    child: Text('Newest'),
                  ),
                  DropdownMenuItem(
                    value: 'created_at',
                    child: Text('Oldest'),
                  ),
                  DropdownMenuItem(
                    value: '-view_count',
                    child: Text('Most Viewed'),
                  ),
                  DropdownMenuItem(
                    value: '-like_count',
                    child: Text('Most Liked'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) onSortChanged(value);
                },
              ),
              const Spacer(),
              if (hasFilters)
                TextButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Error widget.
class _ErrorWidget extends StatelessWidget {
  const _ErrorWidget({
    required this.message,
    required this.onRetry,
  });

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
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Oops!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
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

/// Empty widget.
class _EmptyWidget extends StatelessWidget {
  const _EmptyWidget({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories,
              size: 64,
              color: AppColors.ochre,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}