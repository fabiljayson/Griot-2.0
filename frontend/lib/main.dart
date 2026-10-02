import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/debug/debug_log.dart';
import 'core/navigation/app_router.dart';
import 'core/offline/offline_error_buffer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'org.africanteller.griot_ai.audio',
      androidNotificationChannelName: 'Griot AI Audio',
      androidNotificationOngoing: true,
    );
  }

  // Fail fast on a misconfigured release build rather than at the first
  // request. A release compiled without `--dart-define=API_BASE_URL=https://…`
  // keeps the emulator loopback default; Android blocks that at the network
  // layer and iOS blocks it via ATS, so either way the app would ship with no
  // working API origin. Throwing here makes the mistake a build-time failure
  // instead of a support ticket.
  AppConstants.assertCleartextBaseUrlIsSafe();

  // Phase 9 — Web offline support. On the web the sqflite plugin has no
  // native implementation, so swap in the sqflite_common_ffi_web factory,
  // which runs SQLite compiled to wasm inside a (shared) web worker and
  // persists databases in the browser's IndexedDB. Must happen before any
  // repository opens the database.
  //
  // Desktop targets (Linux/Windows/macOS) have no sqflite platform plugin
  // either, so they need the FFI factory backed by the system sqlite3
  // library.
  if (kIsWeb) {
    sqflite.databaseFactory = databaseFactoryFfiWeb;
  } else if (defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    sqflite.databaseFactory = databaseFactoryFfi;
  }

  // Initialize offline error buffer (in-memory on web, disk-backed on mobile)
  await OfflineErrorBuffer.instance.loadFromDisk();

  // Note: Offline auth sync is handled by OfflineSyncManager
  // which is initialized in the OfflineProvider widget.

  // Initialize deep linking (awaits the platform's initial link, if any, so the
  // first frame can route straight to the linked screen).
  await _initDeepLinks();

  // Sentry monitoring (Phase 10.1) — only when a DSN is provided.
  //   flutter run --dart-define=SENTRY_DSN=https://xxx@sentry.io/yyy
  if (AppConstants.sentryDsn.isNotEmpty) {
    await SentryFlutter.init((options) {
      options.dsn = AppConstants.sentryDsn;
      options.tracesSampleRate = 0.2;
      options.environment = const String.fromEnvironment(
        'ENVIRONMENT',
        defaultValue: 'dev',
      );
    }, appRunner: () => runApp(const ProviderScope(child: GriotAiApp())));
    return;
  }

  runApp(const ProviderScope(child: GriotAiApp()));
}

/// Initialize deep linking via app_links.
///
/// Handles both initial link (app opened from link) and subsequent links
/// (app already running when link is tapped). A link received before the first
/// frame is queued by [AppRouter] and routed once the navigator exists.
Future<void> _initDeepLinks() async {
  final appLinks = AppLinks();

  // Handle subsequent links (app already running).
  appLinks.uriLinkStream.listen(
    _handleDeepLink,
    onError: (Object e) {
      debugLog('Deep link stream error: $e');
    },
  );

  // Handle the initial link (app cold-started from a deep link).
  try {
    final initial = await appLinks.getInitialLink();
    if (initial != null) _handleDeepLink(initial);
  } catch (e) {
    debugLog('Failed to get initial link: $e');
  }
}

/// Handle a deep link URI.
///
/// Supports (see [AppDeepLink] for the full grammar):
/// - griot-ai://story/{slug} — opens a story
/// - https://griot-ai.org/story/{slug} — opens a story
/// - https://griot-ai.org/artifact/{slug} — opens a museum artifact
/// - https://griot-ai.org/qr/{slug} — the link printed on museum QR labels
/// - https://griot-ai.org/stories?region={slug} — opens a region
void _handleDeepLink(Uri uri) {
  // `developer.log` is not stripped from release builds the way `debugLog` is.
  // A deep link is attacker-supplied — any app or web page can fire one at this
  // app — so logging the raw URI shipped user-controlled text straight into
  // release device logs, which are readable by anyone with file access and are
  // frequently attached to bug reports. Nothing actionable in the URI is lost:
  // `AppRouter.handle` still parses it, and debug builds still log it.
  debugLog('Deep link received: $uri');
  AppRouter.handle(uri);
}
