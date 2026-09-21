import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/app.dart';
import 'package:griot_ai/core/network/connectivity_service.dart';
import 'package:griot_ai/core/network/offline_sync_manager.dart';
import 'package:griot_ai/core/theme/app_colors.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/auth/providers/auth_provider.dart';
import 'package:griot_ai/features/auth/repositories/auth_repository.dart';
import 'package:griot_ai/features/discover/models/region_model.dart';
import 'package:griot_ai/features/discover/providers/region_provider.dart';

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

/// No-op connectivity service for tests (no platform channels).
///
/// Overrides the real [ConnectivityService] which depends on
/// `connectivity_plus` platform channels unavailable in tests.
class _FakeConnectivityService implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();

  @override
  Stream<bool> get connectivityStream => _controller.stream;

  @override
  bool get isOnline => true;

  @override
  void initialize() {} // no-op in tests

  @override
  void dispose() {
    _controller.close();
  }
}

/// No-op offline sync manager for tests.
class _FakeOfflineSyncManager implements OfflineSyncManager {
  @override
  void initialize() {} // no-op in tests

  @override
  void dispose() {} // no-op in tests

  @override
  Future<void> triggerSync() async {} // no-op in tests
}

void main() {
  testWidgets('App shell renders the landing screen', (tester) async {
    // Use a wider viewport to avoid RenderFlex overflows in the test.
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          connectivityServiceProvider.overrideWithValue(
            _FakeConnectivityService(),
          ),
          offlineSyncManagerProvider.overrideWithValue(
            _FakeOfflineSyncManager(),
          ),
          // Home's region strip is data-driven: it lists the curated regions
          // that resolve to at least one story in the local database. This
          // test runs with no database, so feed it the four web-matching
          // regions directly instead of asserting on an empty cache.
          regionListProvider.overrideWith(
            (ref) async => [
              for (final region in Regions.primary)
                region.copyWith(storyCount: 2),
            ],
          ),
        ],
        child: const GriotAiApp(),
      ),
    );

    // Let the (mocked) auth check resolve so the home screen renders.
    await tester.pumpAndSettle();

    // Landing branding is visible — the GriotLogo renders "Griot " and
    // "AI" as separate TextSpans inside a single RichText.
    expect(find.textContaining('Griot', findRichText: true), findsWidgets);

    // The hero copy is part of the landing screen (English is the default).
    expect(
      find.textContaining('living heritage'),
      findsOneWidget,
    );

    // Brand primaries match the webapp's heritage palette.
    expect(AppColors.indigo.toARGB32(), 0xFF1E2B58); // Ndop indigo
    expect(AppColors.bronze.toARGB32(), 0xFFC68B29); // Foumban bronze
    expect(
      AppColors.equatorialGreen.toARGB32(),
      0xFF1B4332,
    ); // Equatorial green
    expect(AppColors.ivory.toARGB32(), 0xFFFBF9F4); // Raffia ivory
    expect(AppColors.charcoal.toARGB32(), 0xFF1C1C1E); // Slate charcoal

    // Legacy alias names must resolve to the *same* colours as the webapp's
    // Tailwind theme (backend/static/web/js/tailwind-theme.js), so a call site
    // keeps its colour on both platforms: terracotta/ochre → cam-bronze,
    // savannah → cam-green, sand → cam-ivory, deep-earth → cam-dark.
    expect(AppColors.terracotta.toARGB32(), 0xFFC68B29);
    expect(AppColors.terracottaDark.toARGB32(), 0xFFA67420);
    expect(AppColors.terracottaTint.toARGB32(), 0xFFF5ECD6);
    expect(AppColors.ochre.toARGB32(), AppColors.bronze.toARGB32());
    expect(AppColors.ochreTint.toARGB32(), 0xFFF5ECD6);
    expect(AppColors.savannahGreen.toARGB32(), 0xFF1B4332);
    expect(AppColors.savannahGreenTint.toARGB32(), 0xFFD8E8E0);
    expect(AppColors.sand.toARGB32(), 0xFFFBF9F4);
    expect(AppColors.deepEarth.toARGB32(), 0xFF1C1C1E);

    // Region cards from the Discover Regions strip render (below the fold in
    // the test viewport, so scroll the outer list to reveal them).
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
