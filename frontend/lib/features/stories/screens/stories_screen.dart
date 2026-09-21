import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../core/providers/database_providers.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_loader.dart';
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

    // This screen is reached two ways: as a bottom-bar tab (inside MainShell,
    // which supplies the Scaffold) and as a pushed route from Home's "See all"
    // button and category pills. A pushed route has no background and no safe
    // insets of its own, so the screen carries its own Scaffold + SafeArea —
    // matching the sibling Artifacts screen. Nesting is harmless in the shell.
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // --- Search bar ---
            _SearchBar(
              controller: _searchController,
              onSearch: (query) {
                ref.read(storyListProvider.notifier).search(query);
                if (query.trim().isNotEmpty) {
                  ref
                      .read(searchHistoryRepositoryProvider)
                      .addQuery(query.trim());
                  ref.invalidate(recentSearchQueriesProvider);
                }
              },
              onFilterToggle: () {
                setState(() => _showFilters = !_showFilters);
              },
              showFilters: _showFilters,
            ),

            // --- Filters ---
            if (_showFilters)
              _FilterChips(
                selectedLanguage: ref
                    .read(storyListProvider.notifier)
                    .selectedLanguage,
                selectedCategory: ref
                    .read(storyListProvider.notifier)
                    .selectedCategory,
                sortBy: ref.read(storyListProvider.notifier).currentSortBy,
                categories: categories,
                onLanguageChanged: (lang) {
                  ref.read(storyListProvider.notifier).filterByLanguage(lang);
                },
                onCategoryChanged: (cat) {
                  ref.read(storyListProvider.notifier).filterByCategory(cat);
                },
                onSortChanged: (sort) {
                  ref.read(storyListProvider.notifier).sortStories(sort);
                },
                onClearFilters: () {
                  ref.read(storyListProvider.notifier).clearFilters();
                  _searchController.clear();
                },
              ),

            // --- Story grid ---
            Expanded(child: _buildStoryGrid(storyState, theme)),
          ],
        ),
      ),
    );
  }

  void _retry() =>
      ref.read(storyListProvider.notifier).loadStories(refresh: true);

  Future<void> _refresh() async {
    await ref.read(storyListProvider.notifier).loadStories(refresh: true);
  }

  /// Story grid, shared by every state that has stories to show.
  ///
  /// Each branch used to carry its own copy of this subtree; the only genuine
  /// difference between them is whether a footer row (a loading row, or an
  /// error banner) is appended.
  Widget _buildGrid({
    required List<StoryModel> stories,
    required bool hasMore,
    Widget? footer,
  }) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollController,
        key: const ValueKey('storiesScroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: _getCrossAxisCount(context),
              mainAxisSpacing: AppSpacing.lg,
              crossAxisSpacing: AppSpacing.lg,
              childCount: stories.length + (hasMore || footer != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == stories.length) {
                  return footer ??
                      const Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: Center(child: GriotLoader(size: 24)),
                      );
                }

                final story = stories[index];
                return StoryCard(
                  story: story,
                  onTap: () => _navigateToStory(story),
                  onBookmark: () => ref
                      .read(storyListProvider.notifier)
                      .toggleBookmark(story.slug),
                  onLike: () => ref
                      .read(storyListProvider.notifier)
                      .toggleLike(story.slug),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryGrid(StoryListState state, ThemeData theme) {
    return switch (state) {
      StoryListInitial() || StoryListLoading(stories: []) =>
        const GriotLoadingState(label: 'Loading stories'),

      StoryListFailure(:final message, stories: []) => ErrorState(
        message: message,
        title: 'Could not load stories',
        onRetry: _retry,
      ),

      StoryListReady(stories: []) => EmptyState(
        title: ref.read(storyListProvider.notifier).searchQuery.isNotEmpty
            ? 'No stories found for '
                  '"${ref.read(storyListProvider.notifier).searchQuery}"'
            : 'No stories yet',
        subtitle: ref.read(storyListProvider.notifier).searchQuery.isNotEmpty
            ? 'Try a different word, or clear the filters.'
            : 'Stories shared by griots and contributors will appear here.',
        icon: AppIcons.auto_stories_outlined,
      ),

      StoryListReady(:final stories, :final hasMore) => _buildGrid(
        stories: stories,
        hasMore: hasMore,
      ),

      // Loading more pages on top of existing results.
      StoryListLoading(:final stories) => _buildGrid(
        stories: stories,
        hasMore: false,
        footer: const SizedBox.shrink(),
      ),

      // A failure with results already on screen keeps the list and reports the
      // failure above it, rather than throwing the content away.
      StoryListFailure(:final message, :final stories) => Column(
        children: [
          MaterialBanner(
            content: Text(message),
            leading: FaIcon(
              AppIcons.warning_amber_rounded,
              color: theme.colorScheme.error,
            ),
            actions: [
              TextButton(onPressed: _retry, child: const Text('Retry')),
            ],
          ),
          Expanded(child: _buildGrid(stories: stories, hasMore: false)),
        ],
      ),
    };
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
      MaterialPageRoute(builder: (_) => StoryDetailScreen(slug: story.slug)),
    );
  }
}

/// Search bar widget.
class _SearchBar extends StatefulWidget {
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
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // Refresh the clear button visibility.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.onSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
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
              controller: widget.controller,
              decoration: InputDecoration(
                hintText: 'Search stories...',
                prefixIcon: const FaIcon(AppIcons.search),
                suffixIcon: widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const FaIcon(AppIcons.clear),
                        onPressed: () {
                          widget.controller.clear();
                          widget.onSearch('');
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
              ),
              onSubmitted: widget.onSearch,
              onChanged: _onChanged,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            icon: FaIcon(
              widget.showFilters
                  ? AppIcons.filter_list_off
                  : AppIcons.filter_list,
              color: widget.showFilters ? theme.colorScheme.secondary : null,
            ),
            onPressed: widget.onFilterToggle,
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
    required this.selectedLanguage,
    required this.selectedCategory,
    required this.sortBy,
    required this.categories,
    required this.onLanguageChanged,
    required this.onCategoryChanged,
    required this.onSortChanged,
    required this.onClearFilters,
  });

  final String? selectedLanguage;
  final String? selectedCategory;
  final String sortBy;
  final AsyncValue<List<StoryCategory>> categories;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFilters = selectedLanguage != null || selectedCategory != null;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
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
          Text('Language', style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              FilterChip(
                label: const Text('All'),
                selected: selectedLanguage == null,
                onSelected: (_) => onLanguageChanged(null),
              ),
              ...StoryLanguage.values.map((lang) {
                return FilterChip(
                  // Language name instead of the model's flag emoji.
                  avatar: const FaIcon(AppIcons.language, size: 13),
                  label: Text(lang.label),
                  selected: selectedLanguage == lang.value,
                  onSelected: (_) {
                    onLanguageChanged(
                      selectedLanguage == lang.value ? null : lang.value,
                    );
                  },
                );
              }),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Category filter
          categories.when(
            data: (cats) {
              if (cats.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Category', style: theme.textTheme.labelMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: selectedCategory == null,
                        onSelected: (_) => onCategoryChanged(null),
                      ),
                      ...cats.map((cat) {
                        return FilterChip(
                          // Real icon resolved from the stored glyph, instead of
                          // rendering the emoji itself.
                          avatar: FaIcon(
                            AppIcons.fromEmoji(cat.icon),
                            size: 13,
                          ),
                          label: Text(cat.name),
                          selected: selectedCategory == cat.slug,
                          onSelected: (_) {
                            onCategoryChanged(
                              selectedCategory == cat.slug ? null : cat.slug,
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
          const SizedBox(height: AppSpacing.md),

          // Sort & clear
          Row(
            children: [
              Text('Sort by', style: theme.textTheme.labelMedium),
              const SizedBox(width: AppSpacing.sm),
              DropdownButton<String>(
                value: sortBy,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: '-created_at', child: Text('Newest')),
                  DropdownMenuItem(value: 'created_at', child: Text('Oldest')),
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
                  icon: const FaIcon(AppIcons.clear_all, size: 18),
                  label: const Text('Clear'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
