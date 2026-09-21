import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_providers.dart';
import '../../stories/models/story_model.dart';
import '../models/region_model.dart';

/// Curated regions enriched with the number of published stories held locally.
///
/// Regions with no content are filtered out so the Home strip never shows an
/// empty card — matching the webapp, which only renders regions that resolve to
/// at least one story.
final regionListProvider = FutureProvider<List<RegionModel>>((ref) async {
  final repository = ref.watch(localStoryRepositoryProvider);
  final counts = await repository.regionCounts();

  final enriched = <RegionModel>[];
  for (final region in Regions.all) {
    var total = 0;
    counts.forEach((storedRegion, count) {
      if (region.matches(storedRegion)) total += count;
    });
    if (total > 0) enriched.add(region.copyWith(storyCount: total));
  }
  return enriched;
});

/// Stories published in the region identified by [slug], most viewed first.
final regionStoriesProvider =
    FutureProvider.family<List<StoryModel>, String>((ref, slug) async {
  final region = Regions.bySlug(slug);
  if (region == null) return const [];

  final repository = ref.watch(localStoryRepositoryProvider);
  final counts = await repository.regionCounts();
  final matchedRegions = counts.keys
      .where(region.matches)
      .toList(growable: false);
  if (matchedRegions.isEmpty) return const [];

  return repository.getStoriesForRegions(matchedRegions);
});
