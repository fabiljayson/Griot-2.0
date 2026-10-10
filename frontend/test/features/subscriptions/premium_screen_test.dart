import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/features/subscriptions/models/subscription_status.dart';
import 'package:griot_ai/features/subscriptions/providers/subscription_provider.dart';
import 'package:griot_ai/features/subscriptions/screens/premium_screen.dart';

/// A status frozen at build time: the screen only reads the payload, so the
/// test pins the server's answer instead of talking to a client.
class _FixedStatusNotifier extends SubscriptionNotifier {
  _FixedStatusNotifier(this._status);

  final SubscriptionStatus _status;

  @override
  Future<SubscriptionStatus> build() async => _status;
}

const _videoFeature = FeatureAccess(
  key: 'ai_video_generation',
  label: 'AI video generation',
  enabled: true,
  hasAccess: false,
);

final _freeStatus = SubscriptionStatus(
  subscribed: false,
  entitled: false,
  features: const [_videoFeature],
);

final _premiumStatus = SubscriptionStatus(
  subscribed: true,
  entitled: true,
  status: 'active',
  provider: 'revenuecat',
  plan: 'premium_monthly',
  planName: 'Premium Monthly',
  currentPeriodEnd: DateTime.utc(2026, 11, 1),
  features: const [
    FeatureAccess(
      key: 'ai_video_generation',
      label: 'AI video generation',
      enabled: true,
      hasAccess: true,
    ),
  ],
);

Future<void> pumpPremium(
  WidgetTester tester, {
  SubscriptionStatus? status,
  List<SubscriptionPlan> plans = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionProvider.overrideWith(
          () => _FixedStatusNotifier(status ?? _freeStatus),
        ),
        plansProvider.overrideWith((ref) async => plans),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const PremiumScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a free reader sees Free, the comparison and a paywall CTA',
      (tester) async {
    await pumpPremium(tester, plans: const [
      SubscriptionPlan(
        key: 'premium_monthly',
        name: 'Premium Monthly',
        price: '4.99',
        currency: 'USD',
        interval: 'month',
        durationDays: 30,
        description: 'Full premium access, billed monthly.',
      ),
    ]);

    // 'Free' appears as the status title and the comparison column heading.
    expect(find.text('Free'), findsWidgets);
    expect(find.text('Go Premium'), findsOneWidget);
    // The premium column is the server's gated list, not local copy.
    expect(find.text('AI video generation'), findsWidgets);
    expect(find.text('Premium Monthly'), findsOneWidget);
    expect(find.text('\$4.99 / month'), findsOneWidget);
    // No entitlement, so there is no "active until" line.
    expect(find.textContaining('Active until'), findsNothing);
  });

  testWidgets('an entitled reader sees their plan and subscription details',
      (tester) async {
    await pumpPremium(tester, status: _premiumStatus);

    // 'Premium' appears as the status title and the comparison column heading.
    expect(find.text('Premium'), findsWidgets);
    // The plan name is both the status headline and the "Plan" detail row.
    expect(find.text('Premium Monthly'), findsWidgets);
    expect(find.textContaining('Active until 01 Nov 2026'), findsOneWidget);
    // Already subscribed: the buy CTA makes no sense.
    expect(find.text('Go Premium'), findsNothing);
    // The raw record is shown verbatim from the payload.
    expect(find.text('Your subscription'), findsOneWidget);
    expect(find.text('revenuecat'), findsOneWidget);
  });

  testWidgets('an empty plan shelf explains how premium is granted',
      (tester) async {
    await pumpPremium(tester);

    expect(
      find.textContaining('No plans are on sale yet'),
      findsOneWidget,
    );
  });
}
