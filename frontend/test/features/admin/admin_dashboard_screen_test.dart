import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_icons.dart';
import 'package:griot_ai/features/admin/models/analytics_models.dart';
import 'package:griot_ai/features/admin/models/moderation_models.dart';
import 'package:griot_ai/features/admin/providers/admin_provider.dart';
import 'package:griot_ai/features/admin/screens/admin_dashboard_screen.dart';

import '../../support/admin_fixtures.dart';

/// Renders the dashboard on a wide, tall surface so every section is laid out
/// without scrolling.
Future<void> pumpDashboard(
  WidgetTester tester, {
  DashboardSummary? summary,
  List<FlaggedStory>? queue,
  List<AdminUser>? users,
  Completer<DashboardSummary>? summaryPending,
  bool failSummary = false,
}) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardSummaryProvider.overrideWith(
          (ref) => failSummary
              ? throw Exception('boom')
              : summaryPending?.future ??
                    Future.value(
                      summary ?? DashboardSummary.fromJson(adminDashboardJson()),
                    ),
        ),
        moderationQueueProvider.overrideWith(
          (ref) async => queue ?? const <FlaggedStory>[],
        ),
        moderationProvider.overrideWith((ref) => ModerationNotifier()),
        adminUsersProvider.overrideWith((ref) async => users ?? const []),
      ],
      child: const MaterialApp(home: AdminDashboardScreen()),
    ),
  );
}

void main() {
  testWidgets('renders the four headline stat cards', (tester) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    expect(find.text('Total Users'), findsOneWidget);
    expect(find.text('142'), findsOneWidget);
    expect(find.text('58 active (30d)'), findsOneWidget);

    expect(find.text('Stories'), findsOneWidget);
    expect(find.text('87'), findsOneWidget);
    expect(find.text('3 pending review'), findsOneWidget);

    expect(find.text('Quiz Attempts'), findsOneWidget);
    expect(find.text('214'), findsOneWidget);

    expect(find.text('QR Scans'), findsOneWidget);
    expect(find.text('987'), findsWidgets);
    expect(find.text('312 unique scanners'), findsOneWidget);
  });

  testWidgets('shows a loading spinner while the summary is in flight', (
    tester,
  ) async {
    final completer = Completer<DashboardSummary>();
    await pumpDashboard(tester, summaryPending: completer);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Total Users'), findsNothing);

    completer.complete(DashboardSummary.fromJson(adminDashboardJson()));
    await tester.pumpAndSettle();
    expect(find.text('Total Users'), findsOneWidget);
  });

  testWidgets('renders Audience, Content library and Gamification sections', (
    tester,
  ) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    expect(find.text('Audience'), findsOneWidget);
    expect(find.text('Content library'), findsOneWidget);
    expect(find.text('Gamification'), findsOneWidget);

    // Story status + language pills come from the count data.
    expect(find.text('Published'), findsWidgets);
    expect(find.text('English'), findsOneWidget);

    expect(find.text('The Wise Spider'), findsOneWidget);
    expect(find.text('3.2K views · 210 likes'), findsOneWidget);
    expect(find.text('kemi'), findsOneWidget);
    expect(find.text('Wise Spider Quiz'), findsOneWidget);
    expect(find.text('1.4K XP'), findsOneWidget);
  });

  testWidgets('renders QR and Engagement metrics', (tester) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    expect(find.text('QR & museum artifacts'), findsOneWidget);
    expect(find.text('40/45'), findsOneWidget);
    expect(find.text('Bamoun Mask'), findsOneWidget);
    expect(find.text('Musée du Cameroun'), findsOneWidget);
    expect(find.text('Engagement'), findsOneWidget);
    expect(find.text('148K'), findsOneWidget);
    expect(find.text('63'), findsOneWidget);
  });

  testWidgets('renders all users from the local and deployed databases', (
    tester,
  ) async {
    final users = [
      AdminUser.fromJson({
        'id': 1,
        'username': 'kemi',
        'email': 'kemi@test.com',
        'first_name': 'Kemi',
        'last_name': '',
        'role': 'admin',
        'role_display': 'Admin',
        'institution': '',
        'date_joined': '2026-01-01T00:00:00Z',
        'is_active': true,
      }),
      AdminUser.fromJson({
        'id': 2,
        'username': 'moussa',
        'email': 'moussa@test.com',
        'first_name': '',
        'last_name': '',
        'role': 'contributor',
        'role_display': 'Contributor',
        'institution': '',
        'date_joined': '2026-02-01T00:00:00Z',
        'is_active': false,
      }),
    ];
    await pumpDashboard(tester, users: users);
    await tester.pumpAndSettle();

    expect(find.text('Platform users'), findsOneWidget);
    expect(find.text('All accounts, local & deployed'), findsOneWidget);
    expect(find.text('Kemi'), findsOneWidget);
    expect(find.text('kemi · kemi@test.com'), findsOneWidget);
    expect(find.text('moussa · moussa@test.com'), findsOneWidget);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('Admin'), findsWidgets);
    expect(find.text('Contributor'), findsWidgets);
  });

  testWidgets('shows a friendly empty state when no users exist', (
    tester,
  ) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    expect(find.text('No accounts registered yet.'), findsOneWidget);
  });

  testWidgets('shows the open-flags badge and an empty moderation queue', (
    tester,
  ) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    expect(find.text('Moderation'), findsOneWidget);
    expect(find.text('1 open'), findsOneWidget);
    expect(find.text('No flagged stories — the library is all clear.'), findsOneWidget);
  });

  testWidgets('lists flagged stories in the moderation queue', (tester) async {
    final queue = adminModerationQueueJson()
        .map(FlaggedStory.fromJson)
        .toList();
    await pumpDashboard(tester, queue: queue);
    await tester.pumpAndSettle();

    expect(find.text('The Wrong Spider'), findsOneWidget);
    expect(find.text('by author1 · 2 flags'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Remove story'), findsOneWidget);
  });

  testWidgets('shows a friendly error state when the summary fails', (
    tester,
  ) async {
    await pumpDashboard(tester, failSummary: true);
    await tester.pumpAndSettle();

    expect(find.text('Dashboard unavailable'), findsOneWidget);
    expect(
      find.text('Something went wrong while loading analytics.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('exposes a refresh action in the app bar', (tester) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    expect(find.byIcon(AppIcons.refresh), findsOneWidget);
  });
}