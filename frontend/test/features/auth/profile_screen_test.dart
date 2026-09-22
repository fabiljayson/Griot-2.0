import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/auth/providers/auth_provider.dart';
import 'package:griot_ai/features/auth/repositories/auth_repository.dart';
import 'package:griot_ai/features/auth/screens/profile_screen.dart';
import 'package:griot_ai/features/gamification/providers/gamification_provider.dart';
import 'package:griot_ai/features/gamification/services/gamification_api_service.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';
import 'package:griot_ai/features/stories/providers/story_provider.dart';

/// Auth repository stub that bypasses secure storage, so the screen resolves to
/// a signed-in visitor without platform channels.
class _FakeAuthRepository extends AuthRepository {
  @override
  Future<bool> get isAuthenticated async => true;

  @override
  Future<UserModel> getMe() async => const UserModel(
    id: 1,
    username: 'amara',
    firstName: 'Amara',
    role: UserRole.visitor,
  );

  @override
  Future<TokenPair> refreshTokens() async =>
      const TokenPair(accessToken: 'a', refreshToken: 'b');

  @override
  Future<void> logout() async {}
}

void main() {
  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(520, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          gamificationProfileProvider.overrideWith(
            (ref) async => const GamificationProfileModel(
              totalXp: 320,
              level: 3,
              storiesRead: 12,
              quizzesPassed: 4,
              currentStreak: 5,
              longestStreak: 9,
              xpForNextLevel: 400,
              xpProgress: 0.8,
              badgesCount: 6,
            ),
          ),
          categoriesProvider.overrideWith(
            (ref) async => const [
              StoryCategory(id: 1, name: 'Folktales', slug: 'folktales'),
              StoryCategory(id: 2, name: 'Myths', slug: 'myths'),
            ],
          ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The screen is reached as a pushed route from the Home header, where it
  /// previously returned a bare `Column` — no background, no safe insets.
  testWidgets('ProfileScreen supplies its own Scaffold and SafeArea', (
    tester,
  ) async {
    await pumpProfile(tester);

    final scaffoldFinder = find.byType(Scaffold);
    expect(scaffoldFinder, findsOneWidget);
    expect(tester.widget<Scaffold>(scaffoldFinder).body, isA<SafeArea>());
  });

  testWidgets('renders the greeting, journey and explore blocks', (
    tester,
  ) async {
    await pumpProfile(tester);

    // Greeting header.
    expect(find.textContaining('Amara'), findsOneWidget);

    // Journey block, driven by the gamification profile.
    expect(find.text('Your Journey'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Days streak'), findsOneWidget);
    expect(find.textContaining('320/400 XP'), findsOneWidget);

    // Explore rail, driven by the category catalogue.
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Folktales'), findsOneWidget);
    expect(find.text('Myths'), findsOneWidget);

    // Existing account sections are still present below.
    expect(find.text('Account Information'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
  });
}
