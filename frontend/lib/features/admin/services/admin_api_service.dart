import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/analytics_models.dart';
import '../models/moderation_models.dart';

/// API service for the admin analytics endpoints.
///
/// All endpoints are restricted to `admin` and `institution_manager` roles
/// on the backend (401/403 otherwise).
class AdminApiService {
  /// Create a service instance. Tests may inject a custom [Dio]; the
  /// production singleton uses the shared [ApiClient].
  AdminApiService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static final AdminApiService instance = AdminApiService();

  static const _basePath = '/api/analytics';
  static const _storiesBasePath = '/api/stories';

  /// Fetch the complete dashboard summary.
  Future<DashboardSummary> getDashboardSummary() async {
    final response = await _dio.get('$_basePath/dashboard/');
    return DashboardSummary.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetch user statistics.
  Future<UserStats> getUserStats() async {
    final response = await _dio.get('$_basePath/users/');
    return UserStats.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetch story statistics.
  Future<StoryStats> getStoryStats() async {
    final response = await _dio.get('$_basePath/stories/');
    return StoryStats.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetch gamification statistics.
  Future<GamificationStats> getGamificationStats() async {
    final response = await _dio.get('$_basePath/gamification/');
    return GamificationStats.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetch QR code / artifact statistics.
  Future<QRStats> getQRStats() async {
    final response = await _dio.get('$_basePath/qr-codes/');
    return QRStats.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetch the engagement summary.
  Future<EngagementSummary> getEngagementSummary() async {
    final response = await _dio.get('$_basePath/engagement/');
    return EngagementSummary.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetch the unresolved moderation queue (admin only).
  Future<List<FlaggedStory>> getModerationQueue() async {
    final response = await _dio.get('$_storiesBasePath/moderation-queue/');
    return (response.data as List<dynamic>)
        .map((e) => FlaggedStory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Resolve flags on a story.
  ///
  /// [action] is either `remove` (archives the story) or `dismiss` (keeps it).
  Future<Map<String, dynamic>> moderateStory({
    required String slug,
    required String action,
    String notes = '',
  }) async {
    final response = await _dio.post(
      '$_storiesBasePath/$slug/moderate/',
      data: {'action': action, 'notes': notes},
    );
    return response.data as Map<String, dynamic>;
  }
}
