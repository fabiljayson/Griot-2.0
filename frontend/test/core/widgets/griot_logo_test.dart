import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/core/widgets/brand_widgets.dart';
import 'package:griot_ai/core/widgets/griot_logo.dart';

/// The brand lockup must fit whatever box it is given.
///
/// `BrandHeader` renders `GriotLogo(size: 58, tagline: …)` in a row padded by
/// 24px each side, so the mark and the wordmark together have to fit inside
/// `width - 48`. On a 400px viewport they did not: the logo used
/// `MainAxisSize.min` with inflexible children, and the tagline — whose size
/// is derived from `size * 0.20` but whose *advance width* grows with the
/// reader's text scale — painted outside the box. That surfaced as a
/// RenderFlex overflow, which `widget_test.dart` had been quietly dodging by
/// running only at 1280px wide.
///
/// These tests pin the fit at the sizes and scales where it used to break.
void main() {
  Future<void> pumpBrandHeader(
    WidgetTester tester, {
    required Size size,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: const Scaffold(body: BrandHeader()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('BrandHeader fits its box', () {
    // Below the 720px wide breakpoint BrandHeader is the compact header, so
    // these are the viewports that actually exercise this path.
    const widths = <double>[320, 360, 400, 480];

    for (final width in widths) {
      testWidgets('no overflow at ${width.toInt()}px wide', (tester) async {
        await pumpBrandHeader(tester, size: Size(width, 800));

        expect(tester.takeException(), isNull);
        expect(find.byType(GriotLogo), findsOneWidget);
      });
    }

    // A reader who has enlarged system text should still get the logo, not an
    // overflow stripe. The tagline is the widest part of the lockup, so this
    // is where text scaling does its damage.
    for (final scale in <double>[1.3, 1.8, 2.0]) {
      testWidgets('no overflow at ${scale}x text scale', (tester) async {
        await pumpBrandHeader(
          tester,
          size: const Size(360, 800),
          textScaler: TextScaler.linear(scale),
        );

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('GriotLogo', () {
    testWidgets('keeps its mark at a fixed size regardless of text scale', (
      tester,
    ) async {
      // The mark is the brand anchor: it must not scale with the reader's
      // settings, or the lockup drifts apart.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: const Scaffold(
            body: Center(child: GriotLogo(size: 58, tagline: 'Digital Heritage')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mark = tester.widget<GriotMark>(find.byType(GriotMark));
      expect(mark.size, 58);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without a tagline', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Center(child: GriotLogo(size: 44)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GriotMark), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}