import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/debug/debug_log.dart';

/// Service for sharing stories across platforms.
class SharingService {
  SharingService._();
  static final SharingService instance = SharingService._();

  /// Share a story to the device's share sheet.
  Future<void> shareStory({
    required String title,
    required String slug,
    required String summary,
    String? imageUrl,
    ApiClient? apiClient,
  }) async {
    final shareUrl = '${AppConstants.appShareBaseUrl}/story/$slug';
    final shareText = _buildShareText(title, summary, shareUrl);

    await SharePlus.instance.share(
      ShareParams(text: shareText, subject: title),
    );

    // Track the share (fire and forget)
    _trackShare(slug: slug, platform: 'share_sheet', apiClient: apiClient);
  }

  /// Share to a specific platform.
  Future<void> shareToPlatform({
    required String title,
    required String slug,
    required String summary,
    required String platform,
    ApiClient? apiClient,
  }) async {
    final shareUrl = '${AppConstants.appShareBaseUrl}/story/$slug';
    final shareText = _buildShareText(title, summary, shareUrl);

    await SharePlus.instance.share(
      ShareParams(text: shareText, subject: title),
    );

    // Track the share
    _trackShare(slug: slug, platform: platform, apiClient: apiClient);
  }

  /// Copy story link to clipboard.
  Future<void> copyLink({required String slug}) async {
    final shareUrl = '${AppConstants.appShareBaseUrl}/story/$slug';
    await Clipboard.setData(ClipboardData(text: shareUrl));
  }

  /// Shared copy.
  ///
  /// Plain text only — a shared message goes to other people's apps, so it
  /// carries real typography rather than decorative emoji.
  String _buildShareText(String title, String summary, String url) {
    final buffer = StringBuffer();
    buffer.writeln(title);
    buffer.writeln();
    if (summary.isNotEmpty) {
      buffer.writeln(summary);
      buffer.writeln();
    }
    buffer.writeln('Discover this story on Griot AI:');
    buffer.writeln(url);
    buffer.writeln();
    buffer.writeln('#GriotAI #Cameroon #CulturalHeritage');
    return buffer.toString();
  }

  /// Track a share event (fire and forget).
  ///
  /// Pass the authenticated [ApiClient] so a signed-in reader's share is
  /// attributed to them server-side; the endpoint accepts anonymous callers
  /// too, so a missing client degrades to an unattributed share rather than
  /// a failure.
  void _trackShare({
    required String slug,
    required String platform,
    ApiClient? apiClient,
  }) {
    try {
      final api = apiClient ?? ApiClient.instance;
      api.dio.post('/api/stories/$slug/share/', data: {'platform': platform});
    } catch (e) {
      // Non-critical analytics — log but don't surface.
      debugLog('[SharingService] share tracking failed: $e');
    }
  }
}
