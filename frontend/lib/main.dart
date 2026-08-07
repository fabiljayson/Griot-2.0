import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sentry monitoring (Phase 10.1) — only when a DSN is provided.
  //   flutter run --dart-define=SENTRY_DSN=https://xxx@sentry.io/yyy
  if (AppConstants.sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConstants.sentryDsn;
        options.tracesSampleRate = 0.2;
        options.environment =
            const String.fromEnvironment('ENVIRONMENT', defaultValue: 'dev');
      },
      appRunner: () => runApp(const ProviderScope(child: AfricanTellerApp())),
    );
    return;
  }

  runApp(const ProviderScope(child: AfricanTellerApp()));
}
