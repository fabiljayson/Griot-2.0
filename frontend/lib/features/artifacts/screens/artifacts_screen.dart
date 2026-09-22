import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/griot_loader.dart';
import '../../qr_scanner/screens/artifact_detail_screen.dart';
import '../../qr_scanner/services/qr_api_service.dart';
import '../../qr_scanner/widgets/qr_scanner_widget.dart';
import '../providers/artifacts_provider.dart';
import '../widgets/artifact_card.dart';

/// Museum artifacts catalogue.
///
/// This screen did not exist: the artifact model, API service and detail screen
/// were all built, but nothing ever presented them — `listArtifacts()` had no
/// caller and the QR scanner was unreachable. The webapp has had an Artifacts
/// nav destination all along, so this brings the app to parity.
class ArtifactsScreen extends ConsumerStatefulWidget {
  const ArtifactsScreen({super.key});

  @override
  ConsumerState<ArtifactsScreen> createState() => _ArtifactsScreenState();
}

class _ArtifactsScreenState extends ConsumerState<ArtifactsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(artifactsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      ref.read(artifactsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(artifactsProvider);
    final visible = state.visible;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(artifactsProvider.notifier).load(refresh: true),
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Artifacts',
                              style: theme.textTheme.displaySmall,
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Scan a QR code',
                            onPressed: () async {
                              final artifact =
                                  await QrScannerScreen.show(context);
                              if (artifact != null && context.mounted) {
                                ArtifactDetailScreen.open(context, artifact);
                              }
                            },
                            icon: const Icon(AppIcons.qr_code_scanner),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Objects, masks and monuments held by Cameroonian '
                        'museums — scan a code on site to open one directly.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: _searchController,
                        onChanged: (value) =>
                            ref.read(artifactsProvider.notifier).search(value),
                        onSubmitted: (value) =>
                            ref.read(artifactsProvider.notifier).search(value),
                        decoration: InputDecoration(
                          hintText: 'Search artifacts, cultures, museums...',
                          prefixIcon: const Icon(AppIcons.search),
                          suffixIcon: state.query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(AppIcons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    ref
                                        .read(artifactsProvider.notifier)
                                        .search('');
                                  },
                                ),
                        ),
                      ),
                      if (state.availableCategories.length > 1) ...[
                        const SizedBox(height: AppSpacing.md),
                        _CategoryFilters(
                          categories: state.availableCategories,
                          selected: state.category,
                          onSelected: (value) => ref
                              .read(artifactsProvider.notifier)
                              .setCategory(value),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
              ..._buildBody(state, visible),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(ArtifactsState state, List<ArtifactModel> visible) {
    if (state.isLoading && state.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: GriotLoadingState(label: 'Loading artifacts'),
        ),
      ];
    }

    if (state.errorMessage != null && state.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorState(
            message: state.errorMessage!,
            title: 'Could not load artifacts',
            onRetry: () => ref.read(artifactsProvider.notifier).load(),
          ),
        ),
      ];
    }

    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: state.isEmpty
                ? 'No artifacts published yet'
                : 'No artifacts match your search',
            subtitle: state.isEmpty
                ? 'Museum objects added by curators will appear here.'
                : 'Try a different term or clear the filters.',
            icon: AppIcons.museum_outlined,
            action: state.isEmpty
                ? null
                : TextButton(
                    onPressed: () {
                      _searchController.clear();
                      ref.read(artifactsProvider.notifier).clearFilters();
                    },
                    child: const Text('Clear filters'),
                  ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columns(context),
            mainAxisSpacing: AppSpacing.lg,
            crossAxisSpacing: AppSpacing.lg,
            // The cover is a fixed 4:3, but the text block below it must
            // grow with the column width and the active text scale. The old
            // constant 300 overflowed by ~85px on 1-column phones, pushing
            // the title / rows outside the card.
            mainAxisExtent: _cellExtent(context, _columns(context)),
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final artifact = visible[index];
            return ArtifactCard(
              artifact: artifact,
              onTap: () => ArtifactDetailScreen.open(context, artifact),
            );
          }, childCount: visible.length),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.section),
          child: state.isLoadingMore
              ? const Center(child: GriotLoader(size: 24))
              : const SizedBox.shrink(),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.section)),
    ];
  }

  static int _columns(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width > 1200) return 4;
    if (width > 840) return 3;
    if (width > 560) return 2;
    return 1;
  }

  /// Height of one artifact grid cell.
  ///
  /// Fits the 4:3 cover plus the full text block (category, two-line title,
  /// culture/region and museum rows) at the current text scale, so the card's
  /// content never overflows the cell — the previous fixed `300` broke the
  /// layout on narrow phones.
  static double _cellExtent(BuildContext context, int columns) {
    final width = MediaQuery.sizeOf(context).width;
    final usable = width - AppSpacing.lg * 2;
    final crossAxisExtent =
        (usable - (columns - 1) * AppSpacing.lg) / columns;

    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1.0);

    double line(TextStyle? style) =>
        (style?.fontSize ?? 14) * (style?.height ?? 1.4) * scale;

    final textBlock =
        AppSpacing.md * 2 + // vertical card padding
        line(theme.textTheme.labelSmall) + // category row
        line(theme.textTheme.titleSmall) * 2 + // title (2 lines)
        line(theme.textTheme.bodySmall) * 2 + // culture + museum rows
        AppSpacing.sm * 3 + // row gaps
        AppSpacing.xs; // reflow cushion

    return crossAxisExtent * 3 / 4 + textBlock;
  }
}

/// Horizontal category filter strip.
class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final value = categories[index];
          final isSelected = value == selected;
          final label = value == kAllArtifactCategories
              ? 'All'
              : _labelFor(value);

          return ChoiceChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) => onSelected(value),
            avatar: value == kAllArtifactCategories
                ? null
                : Icon(
                    AppIcons.artifactCategory(value),
                    size: 13,
                    color: isSelected
                        ? theme.colorScheme.onPrimary
                        : AppColors.bronze,
                  ),
          );
        },
      ),
    );
  }

  static String _labelFor(String slug) {
    if (slug.isEmpty) return 'Other';
    return slug[0].toUpperCase() + slug.substring(1);
  }
}
