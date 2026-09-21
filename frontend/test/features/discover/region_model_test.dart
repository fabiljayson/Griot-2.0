import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_icons.dart';
import 'package:griot_ai/features/discover/models/region_model.dart';

void main() {
  group('Regions catalogue', () {
    test('keeps the webapp\u2019s four Home regions, in web order', () {
      expect(
        Regions.primary.map((r) => r.slug).toList(),
        ['bamoun', 'adamawa', 'coastal', 'grassfields'],
      );
    });

    test('every region has a unique slug and its own artwork', () {
      final slugs = Regions.all.map((r) => r.slug).toList();
      expect(slugs.toSet(), hasLength(slugs.length));

      final images = Regions.all.map((r) => r.imageAsset).toList();
      expect(
        images.toSet(),
        hasLength(images.length),
        reason: 'regions must not share a cover image',
      );
    });

    test('every region is reachable by slug', () {
      for (final region in Regions.all) {
        expect(Regions.bySlug(region.slug), same(region));
      }
      expect(Regions.bySlug('atlantis'), isNull);
    });

    test('has no empty label, description or match terms', () {
      for (final region in Regions.all) {
        expect(region.label.trim(), isNotEmpty);
        expect(region.description.trim(), isNotEmpty);
        expect(region.matchTerms, isNotEmpty);
      }
    });
  });

  group('RegionModel.matches', () {
    test('matches its canonical term', () {
      expect(Regions.bamoun.matches('Bamoun'), isTrue);
    });

    test('matches the backend spellings of the same region', () {
      expect(Regions.grassfields.matches('Northwest Region'), isTrue);
      expect(Regions.littoral.matches('Littoral Region'), isTrue);
    });

    test('is case- and whitespace-insensitive', () {
      expect(Regions.coastal.matches('  southwest REGION '), isTrue);
    });

    test('does not match unrelated or blank values', () {
      expect(Regions.bamoun.matches('Adamawa'), isFalse);
      expect(Regions.bamoun.matches(''), isFalse);
      expect(Regions.bamoun.matches('   '), isFalse);
    });
  });

  group('RegionModel.matchesQuery', () {
    test('matches on label and description', () {
      expect(Regions.bamoun.matchesQuery('bamoun'), isTrue);
      expect(Regions.bamoun.matchesQuery('sultanate'), isTrue);
      expect(Regions.bamoun.matchesQuery('montana'), isFalse);
    });
  });

  group('AppIcons.artifactCategory', () {
    test('maps known categories to distinct icons', () {
      final icons = {
        for (final category in [
          'sculpture',
          'textile',
          'instrument',
          'jewelry',
          'pottery',
          'mask',
          'weapon',
          'fabric',
          'tool',
        ])
          category: AppIcons.artifactCategory(category),
      };

      expect(icons.values.toSet(), hasLength(icons.length));
    });

    test('falls back for unknown categories', () {
      expect(AppIcons.artifactCategory('other'), AppIcons.box_open);
      expect(AppIcons.artifactCategory(''), AppIcons.box_open);
    });
  });

  group('AppIcons.fromEmoji', () {
    test('maps every glyph stored by the seed data', () {
      // These are the exact emoji the badge/category seed rows carry — each one
      // must resolve to a real icon so no screen renders emoji as UI text.
      const seeded = [
        '👣',
        '🐛',
        '🧭',
        '🛡️',
        '📝',
        '🎓',
        '💯',
        '🔥',
        '🌍',
        '📖',
        '⚔️',
        '🌐',
        '🏆',
        '📚',
        '🏛️',
        '🗿',
        '🛕',
        '🌄',
        '🌊',
        '✍️',
        '⚡',
        '❤️',
        '🔖',
        '👁',
        '🥇',
        '🎭',
        '🪘',
        '🏺',
        '💎',
      ];

      for (final glyph in seeded) {
        expect(
          AppIcons.fromEmoji(glyph),
          isNotNull,
          reason: 'no icon mapped for $glyph',
        );
      }
    });

    test('falls back to a book icon for an unknown glyph', () {
      expect(AppIcons.fromEmoji('🛸'), AppIcons.auto_stories);
    });
  });
}
