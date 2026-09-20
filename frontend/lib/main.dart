import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/offline/offline_error_buffer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 9 — Web offline support. On the web the sqflite plugin has no
  // native implementation, so swap in the sqflite_common_ffi_web factory,
  // which runs SQLite compiled to wasm inside a (shared) web worker and
  // persists databases in the browser's IndexedDB. Must happen before any
  // repository opens the database.
  if (kIsWeb) {
    sqflite.databaseFactory = databaseFactoryFfiWeb;
  }

  // Initialize offline error buffer (in-memory on web, disk-backed on mobile)
  await OfflineErrorBuffer.instance.loadFromDisk();

  // Note: Offline auth sync is handled by OfflineSyncManager
  // which is initialized in the OfflineProvider widget.

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
