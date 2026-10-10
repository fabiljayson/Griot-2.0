/// Models for the premium-subscription surface.
///
/// The payload comes from `GET /api/subscriptions/status/`, which is the
/// paywall's single source of truth: it answers both "is this account
/// subscribed?" and "may this account use feature X?" at once.
library;

/// One configured premium feature, with the account's current access to it.
class FeatureAccess {
  const FeatureAccess({
    required this.key,
    required this.label,
    required this.enabled,
    required this.hasAccess,
  });

  final String key;
  final String label;

  /// Operator kill switch on the server. False means the feature is offline
  /// for everyone, subscribed or not.
  final bool enabled;

  /// Whether this account may use the feature right now (already the final
  /// verdict — entitlement, kill-switch and staff rules are all folded in).
  final bool hasAccess;

  factory FeatureAccess.fromJson(Map<String, dynamic> json) {
    return FeatureAccess(
      key: json['key'] as String,
      label: json['label'] as String? ?? json['key'] as String,
      enabled: json['enabled'] as bool? ?? true,
      hasAccess: json['has_access'] as bool? ?? false,
    );
  }
}

/// One purchasable plan from `GET /api/subscriptions/plans/`.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.key,
    required this.name,
    required this.price,
    required this.currency,
    required this.interval,
    required this.durationDays,
    this.description = '',
  });

  final String key;
  final String name;
  final String description;

  /// Price as the server sent it (a decimal string like `4.99`) — never
  /// parsed into a double, so a price never rounds in the display.
  final String price;
  final String currency;
  final String interval;
  final int durationDays;

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      key: json['key'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: json['price'] as String? ?? '0.00',
      currency: json['currency'] as String? ?? 'USD',
      interval: json['interval'] as String? ?? 'month',
      durationDays: (json['duration_days'] as num?)?.toInt() ?? 30,
    );
  }

  /// `$4.99 / month` style label for the plan card.
  String get priceLabel {
    final period = switch (interval) {
      'week' => 'week',
      'year' => 'year',
      _ => 'month',
    };
    return '\$$price / $period';
  }
}

/// The reader's premium status and every premium feature they interact with.
class SubscriptionStatus {
  const SubscriptionStatus({
    required this.subscribed,
    required this.entitled,
    this.status,
    this.provider,
    this.plan,
    this.planName,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.features = const [],
  });

  final bool subscribed;
  final bool entitled;
  final String? status;
  final String? provider;

  /// The plan behind the current period (`premium_monthly`), when the server
  /// knows it — null for legacy rows granted before plans existed.
  final String? plan;
  final String? planName;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final List<FeatureAccess> features;

  factory SubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return SubscriptionStatus(
      subscribed: json['subscribed'] as bool? ?? false,
      entitled: json['entitled'] as bool? ?? false,
      status: json['status'] as String?,
      provider: json['provider'] as String?,
      plan: json['plan'] as String?,
      planName: json['plan_name'] as String?,
      currentPeriodStart: DateTime.tryParse(
        json['current_period_start'] as String? ?? '',
      ),
      currentPeriodEnd: DateTime.tryParse(
        json['current_period_end'] as String? ?? '',
      ),
      features: (json['features'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                FeatureAccess.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  /// Whether this account may use `key`.
  ///
  /// A key absent from the payload is not a paid feature at all — the server
  /// only lists configured premium features — so it is free by definition.
  bool hasAccess(String key) {
    return features
        .where((f) => f.key == key)
        .map((f) => f.hasAccess)
        .firstOrNull ??
        true;
  }

  FeatureAccess? feature(String key) =>
      features.where((f) => f.key == key).firstOrNull;
}