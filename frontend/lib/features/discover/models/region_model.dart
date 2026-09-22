import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';

/// A Cameroonian region used by the Home "Discover Regions" strip.
///
/// Before this model existed the strip was four hardcoded chips with an empty
/// `onTap` and no imagery. The curated entries mirror the webapp's
/// `HOME_REGIONS` list (same first four, same order) and extend it with the
/// remaining regions so real content can appear automatically as stories are
/// added. Every region owns a **distinct** image — regions never share art.
@immutable
class RegionModel {
  const RegionModel({
    required this.slug,
    required this.label,
    required this.icon,
    required this.imageAsset,
    required this.description,
    required this.matchTerms,
    required this.accent,
    this.storyCount = 0,
  });

  /// Stable identifier (`bamoun`, `grassfields`, ...).
  final String slug;

  /// Display name, matching the webapp's region labels.
  final String label;

  /// Real icon replacing the web's `HOME_REGIONS` emoji glyph.
  final IconData icon;

  /// Bundled, region-specific photograph.
  final String imageAsset;

  /// One-line cultural summary shown on the region screen.
  final String description;

  /// Region strings this entry matches in story data. The first term is the
  /// canonical value used by the local seed; the rest cover the backend's
  /// `<Name> Region` spellings.
  final List<String> matchTerms;

  /// Accent drawn from the shared palette (bronze / green / earth / indigo).
  final Color accent;

  /// Number of published stories for this region (filled in by the provider).
  final int storyCount;

  RegionModel copyWith({int? storyCount}) => RegionModel(
    slug: slug,
    label: label,
    icon: icon,
    imageAsset: imageAsset,
    description: description,
    matchTerms: matchTerms,
    accent: accent,
    storyCount: storyCount ?? this.storyCount,
  );

  /// True when [regionValue] (as stored on a story) belongs to this region.
  bool matches(String regionValue) {
    final needle = regionValue.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return matchTerms.any((term) => term.toLowerCase() == needle);
  }

  /// True when the free-text filter matches this region.
  bool matchesQuery(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return label.toLowerCase().contains(needle) ||
        description.toLowerCase().contains(needle);
  }
}

/// Curated region catalogue.
///
/// The first four mirror the webapp's `HOME_REGIONS` exactly (`web/views.py`),
/// which in turn mirrors the mobile strip; the remaining entries cover the rest
/// of Cameroon. Ordering is intentional: most-populated regions first.
abstract final class Regions {
  static const _dir = 'assets/imagery/regions/';

  /// The four regions the webapp surfaces on Home, in web order.
  static const List<RegionModel> primary = [bamoun, adamawa, coastal, grassfields];

  static const RegionModel bamoun = RegionModel(
    slug: 'bamoun',
    label: 'Bamoun',
    icon: AppIcons.gopuram,
    imageAsset: '$_dir/bamoun.jpg',
    description:
        'The Bamoun Sultanate of Foumban — royal palace, bronze casters and '
        'one of the oldest continuous monarchies in Africa.',
    matchTerms: ['Bamoun', 'West Region'],
    accent: AppColors.bronze,
  );

  static const RegionModel adamawa = RegionModel(
    slug: 'adamawa',
    label: 'Adamawa',
    icon: AppIcons.mountain_sun,
    imageAsset: '$_dir/adamawa.jpg',
    description:
        'Highland plateaus, cattle trails and crater lakes between Ngaoundéré '
        'and the Far North.',
    matchTerms: ['Adamawa', 'Adamawa Region', 'Adamawa Region '],
    accent: AppColors.indigo,
  );

  static const RegionModel coastal = RegionModel(
    slug: 'coastal',
    label: 'Coastal',
    icon: AppIcons.water,
    imageAsset: '$_dir/coastal.jpg',
    description:
        'Atlantic shorelines, mangrove creeks and fishing towns where Mami '
        'Wata stories live.',
    matchTerms: [
      'Coastal',
      'Littoral Region',
      'Southwest Region',
      'South Region',
    ],
    accent: AppColors.equatorialGreen,
  );

  static const RegionModel grassfields = RegionModel(
    slug: 'grassfields',
    label: 'Grassfields',
    icon: AppIcons.monument,
    imageAsset: '$_dir/grassfields.jpg',
    description:
        'The western highlands — fondoms, masquerade dances and the densest '
        'concentration of oral tradition in the country.',
    matchTerms: ['Grassfields', 'Northwest Region', 'West Region'],
    accent: AppColors.earth,
  );

  static const RegionModel west = RegionModel(
    slug: 'west',
    label: 'West',
    icon: AppIcons.landmark,
    imageAsset: '$_dir/west.jpg',
    description:
        'Bamiléké chiefdoms, elephant masquerades and the market towns around '
        'Bafoussam and Dschang.',
    matchTerms: ['West Region', 'West'],
    accent: AppColors.bronze,
  );

  static const RegionModel southwest = RegionModel(
    slug: 'southwest',
    label: 'Southwest',
    icon: AppIcons.mountain_sun,
    imageAsset: '$_dir/southwest.jpg',
    description:
        'Mount Cameroon, Limbe’s botanical garden and the slave-trade history '
        'of Bimbia.',
    matchTerms: ['Southwest Region', 'South West Region'],
    accent: AppColors.equatorialGreen,
  );

  static const RegionModel littoral = RegionModel(
    slug: 'littoral',
    label: 'Littoral',
    icon: AppIcons.landmark,
    imageAsset: '$_dir/littoral.jpg',
    description:
        'Douala, the economic capital, and the Wouri estuary that carries the '
        'Ngondo festival.',
    matchTerms: ['Littoral Region', 'Littoral'],
    accent: AppColors.indigo,
  );

  static const RegionModel south = RegionModel(
    slug: 'south',
    label: 'South',
    icon: AppIcons.scroll,
    imageAsset: '$_dir/south.jpg',
    description:
        'Equatorial forest, Baka encampments and the memory of the Bimbia '
        'crossing.',
    matchTerms: ['South Region', 'South'],
    accent: AppColors.equatorialGreen,
  );

  static const RegionModel centre = RegionModel(
    slug: 'centre',
    label: 'Centre',
    icon: AppIcons.gopuram,
    imageAsset: '$_dir/centre.jpg',
    description:
        'Yaoundé and the Fang-Beti heartland, ringed by forest reserves and '
        'the Mefou sanctuary.',
    matchTerms: ['Centre Region', 'Central Region', 'Centre'],
    accent: AppColors.bronze,
  );

  static const RegionModel east = RegionModel(
    slug: 'east',
    label: 'East',
    icon: AppIcons.scroll,
    imageAsset: '$_dir/east.jpg',
    description:
        'Deep rainforest along the Sangha and Boumba rivers, home to Baka and '
        'Kola pygmy communities.',
    matchTerms: ['East Region', 'Eastern Region', 'East'],
    accent: AppColors.equatorialGreen,
  );

  static const RegionModel north = RegionModel(
    slug: 'north',
    label: 'North',
    icon: AppIcons.mountain_sun,
    imageAsset: '$_dir/north.jpg',
    description:
        'Sudano-Sahelian savannah, the Bénoué and Bouba Ndjida parks, and '
        'Garoua’s river trade.',
    matchTerms: ['North Region', 'North'],
    accent: AppColors.earth,
  );

  static const RegionModel farNorth = RegionModel(
    slug: 'far-north',
    label: 'Far North',
    icon: AppIcons.monument,
    imageAsset: '$_dir/far-north.jpg',
    description:
        'The Mandara mountains, Rhumsiki’s lunar peaks and Kapsiki forge '
        'traditions.',
    matchTerms: ['Far North Region', 'Far-North Region', 'Far North'],
    accent: AppColors.earth,
  );

  static const RegionModel northwest = RegionModel(
    slug: 'northwest',
    label: 'Northwest',
    icon: AppIcons.landmark,
    imageAsset: '$_dir/northwest.jpg',
    description:
        'Bamenda’s highlands, palaces of the Grassfields fondoms and the '
        'Ring Road markets.',
    matchTerms: ['Northwest Region', 'North West Region', 'Northwest'],
    accent: AppColors.indigo,
  );

  /// The full catalogue, in display order.
  static const List<RegionModel> all = [
    bamoun,
    adamawa,
    coastal,
    grassfields,
    west,
    southwest,
    littoral,
    south,
    centre,
    east,
    north,
    farNorth,
    northwest,
  ];

  /// Look up a curated region by slug.
  static RegionModel? bySlug(String slug) {
    for (final region in all) {
      if (region.slug == slug) return region;
    }
    return null;
  }
}
