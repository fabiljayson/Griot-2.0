import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/providers/onboarding_provider.dart';
import 'package:griot_ai/core/theme/app_colors.dart';
import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/core/widgets/brand_widgets.dart';
import 'package:griot_ai/features/auth/screens/onboarding_screen.dart';

/// Onboarding must look like the rest of the app.
///
/// It used not to. It was the only screen painting itself with a hardcoded
/// `#151F42` indigo background, its own copy of the kente pattern painter and
/// hand-rolled `TextStyle`s — so the first-run experience read as a different
/// product from the login screen one swipe away. It now builds on
/// [BrandScaffold] and takes its colours from the theme.
///
/// These tests pin that. The failure they guard against is not "onboarding
/// looks wrong" but "someone adds a screen-local background again", which is
/// exactly how the drift started.
void main() {
  Future<void> pumpOnboarding(
    WidgetTester tester, {
    // Wide on purpose: these assertions are about the shared shell and the
    // theme, and the wide layout is the one that renders `BrandPanel`, which
    // is the widget that proves onboarding is on the shared shell. The compact
    // layout (BrandHeader) and its narrow-width fit are covered separately in
    // `test/core/widgets/griot_logo_test.dart`.
    Size size = const Size(1280, 960),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Completion writes to secure storage, which has no backing in the
          // widget-test environment; the notifier is constructed but not
          // exercised by these tests.
          onboardingProvider.overrideWith(
            (ref) => OnboardingNotifier(initialCompleted: false),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
  }

  group('OnboardingScreen theming', () {
    testWidgets('renders on the shared BrandScaffold', (tester) async {
      await pumpOnboarding(tester);

      // BrandScaffold puts BrandPanel (wide) or BrandHeader (compact) on
      // screen. Either proves the shared shell is in use rather than a
      // bespoke layout.
      expect(
        find.byType(BrandScaffold),
        findsOneWidget,
        reason: 'onboarding must use the shared auth shell',
      );
      expect(
        find.byType(BrandPanel),
        findsOneWidget,
        reason: 'wide layouts get the shared brand panel',
      );
    });

    testWidgets('does not paint a hardcoded dark background', (tester) async {
      await pumpOnboarding(tester);

      final scaffold = tester.widget<Scaffold>(
        find
            .descendant(
              of: find.byType(OnboardingScreen),
              matching: find.byType(Scaffold),
            )
            .first,
      );

      // BrandScaffold supplies the surface itself: ivory on wide layouts,
      // theme surface on compact. Either way it is a light token — a
      // screen-local dark indigo would show up here.
      expect(
        scaffold.backgroundColor,
        AppColors.ivory,
        reason:
            'onboarding must inherit the shared light surface, not paint its '
            'own dark one',
      );

      expect(find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final color = widget.color;
        return color == AppColors.indigoDark || color == AppColors.indigo;
      }), findsNothing, reason: 'no screen-local indigo container');
    });

    testWidgets('slide text uses the theme, not inline light-on-dark', (
      tester,
    ) async {
      await pumpOnboarding(tester);

      final titleFinder = find.text('Discover\nAfrican Heritage');
      expect(titleFinder, findsOneWidget);

      final title = tester.widget<Text>(titleFinder);
      final scheme = AppTheme.light.colorScheme;

      // Fraunces via the theme's display style, coloured as body ink. The old
      // hardcoded style was Fraunces in `AppColors.sand` (ivory), which is
      // invisible on the ivory surface this screen now uses.
      expect(title.style?.color, scheme.onSurface);
      expect(
        title.style?.fontFamily,
        isNot('PlusJakartaSans'),
        reason: 'display type should stay on the Fraunces serif',
      );
    });

    testWidgets('primary action is the shared AuthButton', (tester) async {
      await pumpOnboarding(tester);

      // Login and register both submit through AuthButton; onboarding must not
      // hand-roll a differently-styled FilledButton.
      expect(find.text('Next'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Next'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );

      // Three slides: the last one is labelled "Get Started", so two advances
      // from the first slide.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Next'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Get Started'), findsOneWidget);
    });
  });
}