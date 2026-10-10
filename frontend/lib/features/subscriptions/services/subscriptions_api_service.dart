import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/subscription_status.dart';

/// API service for the premium-subscription surface.
///
/// Talks to `GET /api/subscriptions/status/`, which answers "is this account
/// subscribed?" and "may it use feature X?" in one round trip, so the paywall
/// and every premium gate render from a single payload.
///
/// The endpoint requires a signed-in user, construct this with the
/// authenticated Dio from `authenticatedApiClientProvider` — the bare
/// `ApiClient.instance` fallback has no `AuthInterceptor` and would be
/// rejected with 401.
class SubscriptionsApiService {
  SubscriptionsApiService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static const _path = '/api/subscriptions';

  /// Fetch the account's premium status and feature access.
  Future<SubscriptionStatus> fetchStatus() async {
    final response = await _dio.get('$_path/status/');
    return SubscriptionStatus.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Fetch the purchasable plans for the paywall's plan shelf.
  Future<List<SubscriptionPlan>> fetchPlans() async {
    final response = await _dio.get('$_path/plans/');
    final data = response.data as List<dynamic>? ?? const [];
    return data
        .map((item) => SubscriptionPlan.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}