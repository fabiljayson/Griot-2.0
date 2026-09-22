import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/features/gamification/services/gamification_api_service.dart';
import 'package:griot_ai/features/gamification/widgets/badge_card.dart';

/// Regression test for the "BOTTOM OVERFLOWED BY 62 PIXELS" bug on the
/// Rewards screen.
///
/// The badge grid lays its tiles out with `childAspectRatio: 0.85` (originally)
/// inside a `maxCrossAxisExtent: 130` grid. On a small phone the tile width is
/// ~96px → tile height ~113px, while the old fixed-height card content (64px
/// icon + 12px gap + two-line name + "XP needed" row + 16px paddings) needed
/// ~175px — hence the 62px overflow. These tests pin the cell to the exact
/// sizes that used to overflow and assert the tile lays out cleanly.
void main() {
  BadgeModel badge({
    String name = 'Guardian of the Oral Tradition',
    bool earned = false,
    int xpRequired = 500,
  }) =>
      BadgeModel(
        id: 1,
        name: name,
        slug: 'guardian',
        earned: earned,
        xpRequired: xpRequired,
      );

  /// Pumps one [BadgeCard] inside a tile of the rewards grid geometry.
  Future<void> pumpTile(
    WidgetTester tester, {
    required Size tile,
    required BadgeModel badgeModel,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Center(
          child: SizedBox(
            width: tile.width,
            height: tile.height,
            child: BadgeCard(badge: badgeModel),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('locked badge fits the smallest historical grid tile', (
    tester,
  ) async {
    // 320dp screen: (320 - 32 gutters - 2×8 gaps) / 3 ≈ 90.7 wide,
    // 90.7 / 0.85 ≈ 106.7 tall — the geometry that used to overflow by ~62px.
    final Size small = const Size(90.7, 106.7);
    await pumpTile(tester, tile: small, badgeModel: badge());

    expect(tester.takeException(), isNull);
    expect(find.byType(BadgeCard), findsOneWidget);
    expect(find.text('Guardian of the Oral Tradition'), findsOneWidget);
    expect(find.text('500 XP needed'), findsOneWidget);
  });

  testWidgets('earned badge with a long two-line name fits the same tile', (
    tester,
  ) async {
    final Size small = const Size(90.7, 106.7);
    await pumpTile(
      tester,
      tile: small,
      badgeModel: badge(earned: true),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('badge fits typical (390dp) and large (412dp) phone tiles', (
    tester,
  ) async {
    // 390dp screen: (390 - 32 - 16) / 3 ≈ 114 wide → 114 / 0.85 ≈ 134 tall.
    // 412dp screen: (412 - 32 - 16) / 3 ≈ 121.3 wide → ~142.7 tall.
    const tiles = <Size>[
      Size(114.0, 134.1),
      Size(121.3, 142.7),
    ];
    for (final tile in tiles) {
      await pumpTile(tester, tile: tile, badgeModel: badge());
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('badge fits at large text scale (accessibility)', (
    tester,
  ) async {
    final Size small = const Size(90.7, 106.7);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Center(
            child: SizedBox(
              width: small.width,
              height: small.height,
              child: BadgeCard(badge: badge()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
