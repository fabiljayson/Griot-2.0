import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/app.dart';
import 'package:griot_ai/core/theme/app_colors.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/auth/providers/auth_provider.dart';
import 'package:griot_ai/features/auth/repositories/auth_repository.dart';

/// Auth repository stub that bypasses secure storage.
///
/// Widget tests have no platform channels, so the real repository would
/// throw while reading tokens. This stub reports an authenticated session
/// so the test can reach the home screen through the real auth flow.
class _FakeAuthRepository extends AuthRepository {
  @override
  Future<bool> get isAuthenticated async => true;

  @override
  Future<UserModel> getMe() async =>
      const UserModel(id: 1, username: 'tester', role: UserRole.visitor);

  @override
  Future<TokenPair> refreshTokens() async =>
      const TokenPair(accessToken: 'test-access', refreshToken: 'test-refresh');

  @override
  Future<void> logout() async {}
}

void main() {
  testWidgets('App shell renders the landing screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
        child: const AfricanTellerApp(),
      ),
    );

    // Let the (mocked) auth check resolve so the home screen renders.
    await tester.pumpAndSettle();

    // Landing branding is visible.
    expect(find.text('GRIOT AI'), findsOneWidget);

    // Design tokens match the webapp's Cameroonian heritage palette.
    expect(AppColors.terracotta.toARGB32(), 0xFF1E2B58); // Ndop indigo
    expect(AppColors.ochre.toARGB32(), 0xFFC68B29); // Foumban bronze
    expect(AppColors.savannahGreen.toARGB32(), 0xFF1B4332); // Equatorial green
    expect(AppColors.parchment.toARGB32(), 0xFFFBF9F4); // Raffia ivory
    expect(AppColors.charcoal.toARGB32(), 0xFF1C1C1E); // Slate charcoal

    // Region cards from the landing grid render (below the fold in the
    // 800x600 test viewport, so scroll the outer list to reveal them).
    // The outer vertical scrollable is the first Scrollable inside the
    // keyed home CustomScrollView (the carousels are nested beneath it).
    final verticalScroll = find
        .descendant(
          of: find.byKey(const ValueKey('homeScroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Bamoun'),
      200,
      scrollable: verticalScroll,
    );
    expect(find.text('Bamoun'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Grassfields'),
      200,
      scrollable: verticalScroll,
    );
    expect(find.text('Grassfields'), findsOneWidget);
  });
}
