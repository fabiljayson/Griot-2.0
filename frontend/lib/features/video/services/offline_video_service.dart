import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/network/http_utils.dart';
import '../../../core/debug/debug_log.dart';

/// Service for playing video files offline.
///
/// Handles:
/// - Local file playback
/// - Caching network video files for offline use
/// - Resume from last position
class OfflineVideoService {
  OfflineVideoService._();
  static final OfflineVideoService instance = OfflineVideoService._();

  final Map<String, VideoPlayerController> _controllers = {};
  final Map<String, String> _cachedFiles = {};

  /// Get the cache directory for video files.
  Future<Directory> get _cacheDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/video_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Get or create a video player controller for the given URL.
  Future<VideoPlayerController> getController(String url) async {
    if (_controllers.containsKey(url)) {
      return _controllers[url]!;
    }

    String source;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      // Check if already cached
      final cachedPath = _cachedFiles[url];
      if (cachedPath != null && await File(cachedPath).exists()) {
        source = cachedPath;
        debugLog('[OfflineVideo] Using cached file: $cachedPath');
      } else {
        // Cache the file first
        source = await _cacheVideoFile(url);
        debugLog('[OfflineVideo] Cached and using: $source');
      }
    } else {
      // Local file path
      source = url;
      debugLog('[OfflineVideo] Using local file: $url');
    }

    final controller = VideoPlayerController.file(File(source));
    await controller.initialize();

    _controllers[url] = controller;
    return controller;
  }

  /// Cache a network video file for offline playback.
  Future<String> _cacheVideoFile(String url) async {
    try {
      final cacheDir = await _cacheDirectory;
      final fileName = 'video_${url.hashCode}.mp4';
      final filePath = '${cacheDir.path}/$fileName';

      // Check if already cached
      final file = File(filePath);
      if (await file.exists()) {
        _cachedFiles[url] = filePath;
        return filePath;
      }

      // Download the file
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes = await consolidateHttpClientResponseBytes(response);
      await file.writeAsBytes(bytes);

      _cachedFiles[url] = filePath;
      return filePath;
    } catch (e) {
      debugLog('[OfflineVideo] Error caching video: $e');
      rethrow;
    }
  }

  /// Check if video is cached for offline use.
  Future<bool> isCached(String url) async {
    final cachedPath = _cachedFiles[url];
    if (cachedPath != null) {
      return File(cachedPath).exists();
    }
    return false;
  }

  /// Get the local path of a cached video file.
  Future<String?> getCachedPath(String url) async {
    final cachedPath = _cachedFiles[url];
    if (cachedPath != null && await File(cachedPath).exists()) {
      return cachedPath;
    }
    return null;
  }

  /// Clear all cached video files.
  Future<void> clearCache() async {
    try {
      final cacheDir = await _cacheDirectory;
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      _cachedFiles.clear();
    } catch (e) {
      debugLog('[OfflineVideo] Error clearing cache: $e');
    }
  }

  /// Dispose all controllers.
  void disposeAll() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }
}
