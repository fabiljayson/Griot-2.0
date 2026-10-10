import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/subscriptions/models/subscription_status.dart';

void main() {
  group('SubscriptionStatus', () {
    test('parses the entitlement, plan and period the server sends', () {
      final status = SubscriptionStatus.fromJson(const {
        'subscribed': true,
        'entitled': true,
        'status': 'active',
        'provider': 'revenuecat',
        'plan': 'premium_monthly',
        'plan_name': 'Premium Monthly',
        'current_period_start': '2026-10-01T00:00:00Z',
        'current_period_end': '2026-11-01T00:00:00Z',
        'features': [
          {
            'key': 'ai_video_generation',
            'label': 'AI video generation',
            'enabled': true,
            'has_access': true,
          },
        ],
      });

      expect(status.entitled, isTrue);
      expect(status.plan, 'premium_monthly');
      expect(status.planName, 'Premium Monthly');
      expect(status.currentPeriodEnd, isNotNull);
      expect(status.hasAccess('ai_video_generation'), isTrue);
    });

    test('a free account has no plan and defaults unknown keys to free', () {
      final status = SubscriptionStatus.fromJson(const {
        'subscribed': false,
        'entitled': false,
        'status': null,
        'provider': null,
        'features': [],
      });

      expect(status.entitled, isFalse);
      expect(status.plan, isNull);
      // A key the payload never mentions is not a paid feature at all.
      expect(status.hasAccess('qr_access'), isTrue);
      expect(status.feature('ai_video_generation'), isNull);
    });

    test('a kill-switched feature reports no access', () {
      final status = SubscriptionStatus.fromJson(const {
        'subscribed': true,
        'entitled': true,
        'status': 'active',
        'features': [
          {
            'key': 'ai_video_generation',
            'label': 'AI video generation',
            'enabled': false,
            'has_access': false,
          },
        ],
      });

      expect(status.hasAccess('ai_video_generation'), isFalse);
    });
  });

  group('SubscriptionPlan', () {
    test('parses a plan row without touching the price as a double', () {
      final plan = SubscriptionPlan.fromJson(const {
        'key': 'premium_monthly',
        'name': 'Premium Monthly',
        'description': 'Full premium access, billed monthly.',
        'price': '4.99',
        'currency': 'USD',
        'interval': 'month',
        'duration_days': 30,
      });

      expect(plan.key, 'premium_monthly');
      expect(plan.price, '4.99');
      expect(plan.priceLabel, '\$4.99 / month');
      expect(plan.durationDays, 30);
    });

    test('price label follows the interval', () {
      const yearly = SubscriptionPlan(
        key: 'premium_yearly',
        name: 'Premium Yearly',
        price: '39.99',
        currency: 'USD',
        interval: 'year',
        durationDays: 365,
      );

      expect(yearly.priceLabel, '\$39.99 / year');
    });
  });
}
