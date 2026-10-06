import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/analytics_models.dart';
import '../models/moderation_models.dart';
import '../models/qr_worklist_models.dart';

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
  static const _artifactsBasePath = '/api/artifacts';

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
    final response = await _dio.get('$_storiesBasePath/moderation_queue/');
    return (response.data as List<dynamic>)
        .map((e) => FlaggedStory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch every platform user, newest first (admin only).
  ///
  /// After `sync_local_users` has run, this is the union of the local SQLite
  /// and deployed PostgreSQL accounts.
  Future<List<AdminUser>> getUsers({String? search}) async {
    final params = (search == null || search.trim().isEmpty)
        ? null
        : {'search': search.trim()};
    final response = await _dio.get(
      '$_basePath/users/list/',
      queryParameters: params,
    );
    return (response.data as List<dynamic>)
        .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch the stories still awaiting a moderator's consent decision
  /// (admin only).
  ///
  /// Mirrors `POST /api/stories/{slug}/record_consent/`: what the contributor
  /// declared about the text travels with the row, because the decision is
  /// about the tradition, not about the enum.
  Future<List<ConsentReviewStory>> getConsentQueue() async {
    final response = await _dio.get('$_storiesBasePath/consent_queue/');
    return (response.data as List<dynamic>)
        .map((e) => ConsentReviewStory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Record the community's answer on a story (moderator only).
  ///
  /// [basis] is required by the server: a consent status with nothing behind
  /// it cannot be defended if it is ever challenged. Withdrawing consent on a
  /// published story archives it — the response reports that in `archived`.
  Future<Map<String, dynamic>> recordStoryConsent({
    required String slug,
    required String status,
    required String basis,
    String? rightsHolder,
    String? licence,
  }) async {
    final data = <String, dynamic>{'status': status, 'basis': basis};
    if (rightsHolder != null && rightsHolder.trim().isNotEmpty) {
      data['rights_holder'] = rightsHolder.trim();
    }
    if (licence != null && licence.isNotEmpty) data['licence'] = licence;

    final response = await _dio.post(
      '$_storiesBasePath/$slug/record_consent/',
      data: data,
    );
    return response.data as Map<String, dynamic>;
  }

  /// Fetch the QR code worklist: artifacts still missing a printable code,
  /// already ordered "no code yet first" by the server (manager/admin only).
  ///
  /// The ordering, the limit and the counts are the server's, not this
  /// client's — the web dashboard reads the same list, and two implementations
  /// of "which objects need labelling" is how the two surfaces start telling a
  /// curator different things about the same museum.
  Future<QrWorklist> getQrWorklist() async {
    final response = await _dio.get('$_artifactsBasePath/qr/worklist/');
    return QrWorklist.fromJson(response.data as Map<String, dynamic>);
  }

  /// Generate QR codes for [slugs], or for everything still missing when
  /// [slugs] is empty (manager/admin only).
  ///
  /// An empty list is not the same as "generate the whole catalog": the server
  /// bounds that case, and reports the bound through [QrWorklist.generated].
  Future<QrWorklistGeneration> generateQrCodes({List<String> slugs = const []}) async {
    final response = await _dio.post(
      '$_artifactsBasePath/qr/worklist/generate/',
      data: <String, dynamic>{'slugs': slugs},
    );
    return QrWorklistGeneration.fromJson(
      response.data as Map<String, dynamic>,
    );
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
