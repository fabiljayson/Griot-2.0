import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/features/gamification/providers/gamification_provider.dart';
import 'package:griot_ai/features/gamification/screens/gamification_screen.dart';
import 'package:griot_ai/features/gamification/services/gamification_api_service.dart';
import 'package:griot_ai/features/gamification/widgets/badge_card.dart';

/// Regression test for the Rewards screen layout.
///
/// Badge tiles overflowed by ~62px historically (pinned in badge_card_test);
/// this locks the full screen — level card, stats row, badge grid and quiz
/// list — at phone size with a large XP figure, so the XP-to-next-level line
/// stays inside its card on narrow widths.
void main() {
  List<BadgeModel> badges() => [
        const BadgeModel(
          id: 1,
          name: 'Community Storyteller Champion Premium',
          slug: 'champion',
          xpRequired: 2500,
          color: '#C85A32',
        ),
        const BadgeModel(
          id: 2,
          name: 'Keeper of the Oral Tradition',
          slug: 'keeper',
          earned: true,
          color: '#7A4A2B',
        ),
      ];

  final quizzes = [
    const QuizModel(
      id: 1,
      title: 'The Sacred Forest of Foréké-Dschang: Guardian Spirit Quiz',
      storyId: 1,
      questionCount: 12,
      xpReward: 120,
      bestScore: 85,
      passingScore: 70,
    ),
  ];

  Widget app() => ProviderScope(
        overrides: [
          gamificationProfileProvider.overrideWith(
            (ref) async => const GamificationProfileModel(
              username: 'demo',
              totalXp: 125000,
              level: 42,
              storiesRead: 1234,
              quizzesPassed: 56,
              currentStreak: 30,
              xpForNextLevel: 100000,
              xpProgress: 0.73,
              badgesCount: 2,
            ),
          ),
          badgesProvider.overrideWith((ref) async => badges()),
          quizzesProvider.overrideWith((ref) async => quizzes),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: GamificationScreen()),
        ),
      );

  testWidgets('Rewards screen fits a narrow phone at default text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byType(BadgeCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rewards screen fits a narrow phone at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byType(BadgeCard), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}