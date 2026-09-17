import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry/sentry.dart';

/// The in-memory buffer itself works everywhere; only the disk persistence
/// (dart:io File + path_provider) is mobile-only. On web the buffer simply
/// survives for the current session.

/// Buffers errors when offline and sends them to Sentry when back online.
///
/// This ensures no errors are lost even when the device is offline.
class OfflineErrorBuffer {
  OfflineErrorBuffer._();
  static final OfflineErrorBuffer instance = OfflineErrorBuffer._();

  final List<Map<String, dynamic>> _buffer = [];
  bool _isOnline = true;
  bool _isSending = false;

  /// Set the current online status.
  set isOnline(bool value) {
    _isOnline = value;
    if (_isOnline && _buffer.isNotEmpty) {
      _sendBufferedErrors();
    }
  }

  /// Buffer an error for later reporting.
  void bufferError({
    required String message,
    String? stackTrace,
    Map<String, dynamic>? extra,
    SentryLevel level = SentryLevel.error,
  }) {
    final error = {
      'message': message,
      'stackTrace': stackTrace,
      'extra': extra,
      'level': level.name,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _buffer.add(error);
    debugPrint('[OfflineErrorBuffer] Buffered error: $message');

    // Try to send immediately if online
    if (_isOnline) {
      _sendBufferedErrors();
    }
  }

  /// Buffer a Sentry event for later reporting.
  void bufferSentryEvent(SentryEvent event) {
    final error = {
      'event': event.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    _buffer.add(error);
    debugPrint('[OfflineErrorBuffer] Buffered Sentry event');

    // Try to send immediately if online
    if (_isOnline) {
      _sendBufferedErrors();
    }
  }

  /// Send all buffered errors to Sentry.
  Future<void> _sendBufferedErrors() async {
    if (_isSending || _buffer.isEmpty) return;

    _isSending = true;
    debugPrint('[OfflineErrorBuffer] Sending ${_buffer.length} buffered errors...');

    try {
      for (final error in List.from(_buffer)) {
        try {
          if (error.containsKey('event')) {
            // It's a SentryEvent
            final event = SentryEvent.fromJson(error['event']);
            await Sentry.captureEvent(event);
          } else {
            // It's a simple error
            final message = error['message'] as String;
            final stackTrace = error['stackTrace'] as String?;
            final extra = error['extra'] as Map<String, dynamic>?;
            final levelName = error['level'] as String? ?? 'error';
            SentryLevel level;
            switch (levelName) {
              case 'fatal':
                level = SentryLevel.fatal;
                break;
              case 'warning':
                level = SentryLevel.warning;
                break;
              case 'info':
                level = SentryLevel.info;
                break;
              case 'debug':
                level = SentryLevel.debug;
                break;
              default:
                level = SentryLevel.error;
            }

            await Sentry.captureMessage(
              message,
              level: level,
              hint: Hint.withMap(extra ?? {}),
            );
          }

          _buffer.remove(error);
        } catch (e) {
          debugPrint('[OfflineErrorBuffer] Failed to send error: $e');
        }
      }
    } finally {
      _isSending = false;
      debugPrint('[OfflineErrorBuffer] Finished sending buffered errors');
    }
  }

  /// Save buffer to disk for persistence across app restarts.
  Future<void> saveToDisk() async {
    // path_provider / dart:io are unavailable on web — keep it in memory only.
    if (kIsWeb) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/error_buffer.json');
      await file.writeAsString(jsonEncode(_buffer));
    } catch (e) {
      debugPrint('[OfflineErrorBuffer] Error saving buffer: $e');
    }
  }

  /// Load buffer from disk.
  Future<void> loadFromDisk() async {
    // path_provider / dart:io are unavailable on web — start with an empty
    // in-memory buffer instead.
    if (kIsWeb) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/error_buffer.json');
      if (await file.exists()) {
        final data = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(data);
        _buffer.addAll(jsonList.cast<Map<String, dynamic>>());
        debugPrint('[OfflineErrorBuffer] Loaded ${_buffer.length} errors from disk');
      }
    } catch (e) {
      debugPrint('[OfflineErrorBuffer] Error loading buffer: $e');
    }
  }

  /// Get the number of buffered errors.
  int get bufferedCount => _buffer.length;

  /// Clear all buffered errors.
  void clearBuffer() {
    _buffer.clear();
  }
}
