import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_client.dart';

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
  }) async {
    final shareUrl = 'https://africanteller.org/story/$slug';
    final shareText = _buildShareText(title, summary, shareUrl);

    await SharePlus.instance.share(
      ShareParams(text: shareText, subject: title),
    );

    // Track the share (fire and forget)
    _trackShare(slug: slug, platform: 'share_sheet');
  }

  /// Share to a specific platform.
  Future<void> shareToPlatform({
    required String title,
    required String slug,
    required String summary,
    required String platform,
  }) async {
    final shareUrl = 'https://africanteller.org/story/$slug';
    final shareText = _buildShareText(title, summary, shareUrl);

    await SharePlus.instance.share(
      ShareParams(text: shareText, subject: title),
    );

    // Track the share
    _trackShare(slug: slug, platform: platform);
  }

  /// Copy story link to clipboard.
  Future<void> copyLink({required String slug}) async {
    final shareUrl = 'https://africanteller.org/story/$slug';
    await Clipboard.setData(ClipboardData(text: shareUrl));
  }

  String _buildShareText(String title, String summary, String url) {
    final buffer = StringBuffer();
    buffer.writeln('🌍📖 $title');
    buffer.writeln();
    if (summary.isNotEmpty) {
      buffer.writeln(summary);
      buffer.writeln();
    }
    buffer.writeln('Discover this story on African Teller:');
    buffer.writeln(url);
    buffer.writeln();
    buffer.writeln('#AfricanTeller #Cameroon #CulturalHeritage');
    return buffer.toString();
  }

  /// Track a share event (fire and forget).
  void _trackShare({required String slug, required String platform}) {
    try {
      final api = ApiClient.instance;
      api.dio.post('/api/stories/$slug/share/', data: {'platform': platform});
    } catch (_) {
      // Silently fail - share tracking is non-critical
    }
  }
}
