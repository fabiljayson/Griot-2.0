import 'dart:io';

import 'package:flutter/foundation.dart' hide consolidateHttpClientResponseBytes;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/http_utils.dart';

/// Service for playing audio files offline.
///
/// Handles:
/// - Local file playback
/// - Caching network audio files for offline use
/// - Resume from last position
class OfflineAudioService {
  OfflineAudioService._();
  static final OfflineAudioService instance = OfflineAudioService._();

  final AudioPlayer _player = AudioPlayer();
  final Map<String, String> _cachedFiles = {};

  /// Get the audio player instance.
  AudioPlayer get player => _player;

  /// Get the cache directory for audio files.
  Future<Directory> get _cacheDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/audio_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Play audio from a URL or local file path.
  ///
  /// If [url] is a network URL, the file will be cached for offline use.
  /// If [url] is already a local file path, it will be played directly.
  Future<void> play(String url, {int resumePosition = 0}) async {
    try {
      String source;

      if (url.startsWith('http://') || url.startsWith('https://')) {
        // Check if already cached
        final cachedPath = _cachedFiles[url];
        if (cachedPath != null && await File(cachedPath).exists()) {
          source = cachedPath;
          debugPrint('[OfflineAudio] Playing cached file: $cachedPath');
        } else {
          // Cache the file first
          source = await _cacheAudioFile(url);
          debugPrint('[OfflineAudio] Cached and playing: $source');
        }
      } else {
        // Local file path
        source = url;
        debugPrint('[OfflineAudio] Playing local file: $url');
      }

      // Set the source and seek to resume position
      await _player.setFilePath(source);
      if (resumePosition > 0) {
        await _player.seek(Duration(seconds: resumePosition));
      }
      await _player.play();
    } catch (e) {
      debugPrint('[OfflineAudio] Error playing audio: $e');
      rethrow;
    }
  }

  /// Cache a network audio file for offline playback.
  Future<String> _cacheAudioFile(String url) async {
    try {
      final cacheDir = await _cacheDirectory;
      final fileName = 'audio_${url.hashCode}.mp3';
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
      debugPrint('[OfflineAudio] Error caching audio: $e');
      rethrow;
    }
  }

  /// Pause playback.
  Future<void> pause() async {
    await _player.pause();
  }

  /// Resume playback.
  Future<void> resume() async {
    await _player.play();
  }

  /// Stop playback.
  Future<void> stop() async {
    await _player.stop();
  }

  /// Seek to a specific position.
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Get current position.
  Duration get position => _player.position;

  /// Get total duration.
  Duration? get duration => _player.duration;

  /// Check if audio is cached for offline use.
  Future<bool> isCached(String url) async {
    final cachedPath = _cachedFiles[url];
    if (cachedPath != null) {
      return File(cachedPath).exists();
    }
    return false;
  }

  /// Get the local path of a cached audio file.
  Future<String?> getCachedPath(String url) async {
    final cachedPath = _cachedFiles[url];
    if (cachedPath != null && await File(cachedPath).exists()) {
      return cachedPath;
    }
    return null;
  }

  /// Clear all cached audio files.
  Future<void> clearCache() async {
    try {
      final cacheDir = await _cacheDirectory;
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      _cachedFiles.clear();
    } catch (e) {
      debugPrint('[OfflineAudio] Error clearing cache: $e');
    }
  }

  /// Dispose resources.
  void dispose() {
    _player.dispose();
  }
}


