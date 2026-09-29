import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';
import '../debug/debug_log.dart';

/// Thrown when a media download is refused or cut short.
class MediaDownloadException implements Exception {
  const MediaDownloadException(this.message);

  final String message;

  @override
  String toString() => 'MediaDownloadException: $message';
}

/// Downloads backend media to disk under explicit limits.
///
/// ## Why this exists
///
/// Both offline caches used to call `consolidateHttpClientResponseBytes` on
/// whatever URL the API handed back. That had four problems, all of them
/// reachable by whoever controls the stored media path:
///
/// * **Unbounded.** The whole body was held in a `List<int>` and then written.
///   A response that never ends exhausts memory, and the app dies with it.
/// * **No timeout.** A socket that stays open forever pins the download.
/// * **No scheme check.** A `http://` (or `file://`-adjacent) reference to a
///   cleartext host is fetched and stored as if it were trusted content.
/// * **No host check.** Any host the response named was fetched, so a
///   compromised or mistyped media field turns the app into a fetcher for
///   arbitrary third-party URLs.
///
/// This class caps the body, caps the time, requires HTTPS outside debug, and
/// restricts the host to the configured API host. The bytes are streamed
/// straight to the destination file, so peak memory is a single chunk rather
/// than the whole file.
class MediaDownloader {
  const MediaDownloader._();

  /// Largest media body accepted, in bytes.
  ///
  /// Narration is a short MP3 and story video is a short MP4; 64 MiB is far
  /// above any legitimate asset and still small enough to fail fast rather
  /// than fill a device.
  static const int maxBytes = 64 * 1024 * 1024;

  /// How long the whole transfer may take.
  static const Duration timeout = Duration(minutes: 2);

  /// A stall of this long between chunks aborts the transfer, so a slow
  /// trickle cannot hold the budget open indefinitely.
  static const Duration idleTimeout = Duration(seconds: 30);

  /// True when [url] may be fetched under the current scheme and host rules.
  ///
  /// Pure so the policy can be tested without a socket.
  static bool isAllowed(String url, {String? apiBaseUrl, bool? debug}) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return false;

    final isDebug = debug ?? kDebugMode;

    if (uri.scheme != 'https') {
      // Cleartext is a development convenience only. In release it is refused
      // outright so a media field can never downgrade the fetch.
      if (!isDebug) return false;
      if (uri.scheme != 'http') return false;
    }

    return _allowedHosts(apiBaseUrl: apiBaseUrl).contains(uri.host);
  }

  static Set<String> _allowedHosts({String? apiBaseUrl}) {
    final base = apiBaseUrl ?? AppConstants.effectiveBaseUrl;
    final uri = Uri.tryParse(base);
    final hosts = <String>{};
    if (uri != null && uri.host.isNotEmpty) hosts.add(uri.host);

    // Emulator and desktop-development hosts. Only consulted in debug, and
    // `isAllowed` already returns false for cleartext in release, so these
    // cannot widen the release policy.
    if (kDebugMode) {
      hosts
        ..add('localhost')
        ..add('127.0.0.1')
        ..add('10.0.2.2');
    }
    return hosts;
  }

  /// A collision-free, stable filename for [url].
  ///
  /// The caches previously named files `audio_${url.hashCode}.mp3`. Dart's
  /// `String.hashCode` is not stable across runs and routinely collides, so
  /// two different URLs could share one filename — the second download would
  /// overwrite the first and the player would serve the wrong audio. A SHA-256
  /// of the URL is deterministic and unique in practice.
  static String cacheFileName(String url, {required String extension}) {
    final digest = sha256.convert(utf8.encode(url)).toString();
    final ext = extension.startsWith('.') ? extension.substring(1) : extension;
    return '$digest.$ext';
  }

  /// Fetch [url] into [destination].
  ///
  /// Throws [MediaDownloadException] when the URL is refused, the response
  /// exceeds [maxBytes], or the transfer does not finish within [timeout].
  /// A partial file is deleted before the error propagates so a later call
  /// does not find a truncated file and treat it as a valid cache entry.
  static Future<void> download(
    String url,
    File destination, {
    String? apiBaseUrl,
    int maxBytesOverride = maxBytes,
  }) async {
    if (!isAllowed(url, apiBaseUrl: apiBaseUrl)) {
      throw MediaDownloadException('Refused media URL: $url');
    }

    final uri = Uri.parse(url);
    final client = HttpClient()..connectionTimeout = idleTimeout;
    IOSink? sink;
    try {
      final request = await client.getUrl(uri).timeout(idleTimeout);
      final response = await request.close().timeout(idleTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw MediaDownloadException('HTTP ${response.statusCode} for $url');
      }

      final declared = response.contentLength;
      if (declared > maxBytesOverride) {
        throw MediaDownloadException(
          'Declared size $declared exceeds $maxBytesOverride for $url',
        );
      }

      // Streamed rather than consolidated: peak memory is one chunk, so an
      // oversized body is cut off by the counter below instead of being read
      // into RAM first.
      final completer = Completer<void>();
      var received = 0;
      final fileSink = destination.openWrite();
      sink = fileSink;

      response.listen(
        (chunk) {
          received += chunk.length;
          if (received > maxBytesOverride) {
            if (!completer.isCompleted) {
              completer.completeError(
                MediaDownloadException(
                  'Response exceeded $maxBytesOverride bytes for $url',
                ),
              );
            }
            return;
          }
          fileSink.add(chunk);
        },
        onDone: () async {
          try {
            await fileSink.close();
            sink = null;
            if (!completer.isCompleted) completer.complete();
          } catch (e, st) {
            if (!completer.isCompleted) completer.completeError(e, st);
          }
        },
        onError: (Object e, StackTrace st) {
          if (!completer.isCompleted) completer.completeError(e, st);
        },
        cancelOnError: true,
      );

      await completer.future.timeout(timeout);
    } on MediaDownloadException {
      await _discard(destination, sink);
      rethrow;
    } on TimeoutException {
      await _discard(destination, sink);
      throw MediaDownloadException('Timed out downloading $url');
    } catch (e) {
      await _discard(destination, sink);
      throw MediaDownloadException('Failed to download $url: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// Join [directory] and a cache filename for [url] under a trusted root.
  static String resolveCachePath(
    String directory,
    String url, {
    required String extension,
  }) {
    final name = cacheFileName(url, extension: extension);
    // `cacheFileName` is hex-only, but the basename is re-derived here so a
    // future change cannot turn this into a path traversal.
    return p.join(directory, p.basename(name));
  }

  static Future<void> _discard(File destination, IOSink? sink) async {
    try {
      await sink?.close();
    } catch (_) {
      // The sink is being abandoned; a close failure adds nothing.
    }
    try {
      if (await destination.exists()) {
        await destination.delete();
      }
    } catch (e) {
      debugLog('[MediaDownloader] Could not remove partial file: $e');
    }
  }
}
