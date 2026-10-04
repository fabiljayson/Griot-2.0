import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/core/widgets/griot_skeleton.dart';

/// Loading states and motion, which are both invisible in a screenshot.
///
/// The app had twenty-six raw `CircularProgressIndicator`s and no skeleton at
/// all, so every list, grid and dashboard waited behind a centred ring, and
/// the app honoured `prefers-reduced-motion` nowhere — the bottom-nav
/// cross-fade and the page transition both ran regardless of the setting.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
          ),
          child: widget!,
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  group('GriotSkeleton', () {
    testWidgets('renders a block at the requested size', (tester) async {
      await pump(tester, const GriotSkeleton(width: 120, height: 20));
      final block = tester.widget<Container>(find.byType(Container).first);
      expect(block.constraints?.maxWidth, 120);
    });

    testWidgets('the circle variant ignores the radius', (tester) async {
      await pump(tester, const GriotSkeleton.circle(size: 40));
      final box = tester.widget<Container>(find.byType(Container).first);
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.borderRadius, isNull);
    });

    testWidgets('pulses when animation is allowed', (tester) async {
      await pump(tester, const GriotSkeleton(width: 100, height: 20));
      await tester.pump(const Duration(milliseconds: 400));
      // The invariant is "the placeholder is animating", not "a FadeTransition
      // exists" — MaterialApp puts its own route transition in the tree, so a
      // byType count would be measuring the framework as well.
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets(
      'does not animate when prefers-reduced-motion is set',
      (tester) async {
        // This is the regression the primitive exists to prevent: a shimmering
        // placeholder is exactly the kind of thing a motion-sensitive person
        // did not sign up for.
        await pump(
          tester,
          const GriotSkeleton(width: 100, height: 20),
          disableAnimations: true,
        );
        expect(tester.hasRunningAnimations, isFalse);

        await tester.pump(const Duration(seconds: 1));
        expect(tester.hasRunningAnimations, isFalse);
      },
    );
  });

  group('GriotSkeletonList', () {
    testWidgets('renders one leading circle per row', (tester) async {
      await pump(tester, const GriotSkeletonList(itemCount: 5));
      expect(find.byType(GriotSkeleton), findsNWidgets(5 * 2 + 5));
      // 5 rows x (circle + two lines)
      final circles = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => (c.decoration as BoxDecoration?)?.shape == BoxShape.circle)
          .length;
      expect(circles, 5);
    });

    testWidgets('respects itemCount', (tester) async {
      await pump(tester, const GriotSkeletonList(itemCount: 2));
      final circles = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => (c.decoration as BoxDecoration?)?.shape == BoxShape.circle)
          .length;
      expect(circles, 2);
    });

    testWidgets('showLeading: false drops the avatar column', (tester) async {
      await pump(tester, const GriotSkeletonList(itemCount: 3, showLeading: false));
      final circles = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => (c.decoration as BoxDecoration?)?.shape == BoxShape.circle)
          .length;
      expect(circles, 0);
    });

    testWidgets('holds still under reduced motion', (tester) async {
      await pump(
        tester,
        const GriotSkeletonList(itemCount: 3),
        disableAnimations: true,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('GriotSkeletonCards', () {
    testWidgets('lays the cards out in a row', (tester) async {
      await pump(tester, const GriotSkeletonCards(itemCount: 4));
      expect(find.byType(Expanded), findsNWidgets(4));
      expect(find.byType(GriotSkeleton), findsNWidgets(4));
    });

    testWidgets('holds still under reduced motion', (tester) async {
      await pump(
        tester,
        const GriotSkeletonCards(itemCount: 3),
        disableAnimations: true,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('every GriotImage call site is labelled', () {
    // The accessibility audit reported "5 of 15 GriotImage call sites lack a
    // semanticLabel". Counting the argument list properly shows all 15 have
    // one — the original count came from grepping fixed line windows around
    // each call, which misses a label that sits further down a long argument
    // list. This test pins the real number so the discrepancy cannot come back
    // as a false alarm.
    test('no image is rendered without a semanticLabel', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.contains('griot_image.dart')) continue;

        final source = entity.readAsStringSync();
        for (final match in RegExp(r'\bGriot(?:Cover)?Image\s*\(').allMatches(source)) {
          var depth = 0;
          var i = match.end - 1;
          for (; i < source.length; i++) {
            if (source[i] == '(') {
              depth++;
            } else if (source[i] == ')') {
              depth--;
              if (depth == 0) break;
            }
          }
          final args = source.substring(match.end - 1, i + 1);
          if (!args.contains('semanticLabel')) {
            offenders.add(
              '${entity.path}:${source.substring(0, match.start).split('\n').length}',
            );
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });
}