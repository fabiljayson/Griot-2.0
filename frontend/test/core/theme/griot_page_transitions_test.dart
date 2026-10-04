import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_theme.dart';

/// `prefers-reduced-motion` has to reach the app's *own* animations, not just
/// the ones a framework supplies.
///
/// Flutter's stock `MaterialPageRoute` honours the platform setting. This app
/// does not use it: `GriotPageTransitionsBuilder` replaces the default fade
/// with a fade plus an upward slide, and the bottom navigation runs its own
/// 240ms cross-fade in `MainShell`. Replacing a framework behaviour means
/// taking on its accessibility contract too — otherwise the app is *less*
/// accessible than the Material default it opted out of, which is the failure
/// mode nobody tests for.
void main() {
  Route<void> route(Widget child) => PageRouteBuilder<void>(
    pageBuilder: (_, _, _) => child,
    transitionDuration: const Duration(milliseconds: 300),
  );

  Future<void> pumpTransition(
    WidgetTester tester, {
    required bool disableAnimations,
  }) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        navigatorKey: navigatorKey,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
          ),
          child: widget!,
        ),
        home: const Scaffold(body: Text('first')),
      ),
    );

    unawaited(navigatorKey.currentState!.push(route(const Text('second'))));
    await tester.pump();
  }

  group('GriotPageTransitionsBuilder', () {
    testWidgets('animates when motion is allowed', (tester) async {
      await pumpTransition(tester, disableAnimations: false);
      await tester.pump();
      // The slide is the app's own flourish on top of the fade; if it is gone
      // the builder is not being used at all.
      expect(find.byType(SlideTransition), findsOneWidget);
      expect(find.byType(FadeTransition), findsWidgets);
    });

    testWidgets(
      'presents the destination immediately when motion is reduced',
      (tester) async {
        await pumpTransition(tester, disableAnimations: true);
        await tester.pump();

        // The route change still happened...
        expect(find.text('second'), findsOneWidget);
        // ...but nothing is animating into place.
        expect(find.byType(SlideTransition), findsNothing);
      },
    );
  });
}

/// Local stand-in for `dart:async`'s `unawaited`, kept here so the test file
/// does not import anything it does not otherwise need.
void unawaited(Future<void> future) {}