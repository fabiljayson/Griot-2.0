/// Global constants for the Griot AI app.
abstract final class AppConstants {
  static const String appName = 'Griot AI';
  static const String appTagline = 'Digital Heritage Platform';

  /// Backend base URL.
  ///
  /// Override at build/run time:
  ///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Ngrok tunnel URL for physical device testing.
  ///
  /// Set via --dart-define=NGROK_URL=https://xxxx-xx-xx-xx-xx.ngrok-free.app
  /// If set, the app will use this URL instead of apiBaseUrl.
  static const String ngrokUrl = String.fromEnvironment('NGROK_URL');

  /// Whether to use ngrok tunneling.
  static bool get useNgrok => ngrokUrl.isNotEmpty;

  /// Get the effective base URL (ngrok if configured, otherwise apiBaseUrl).
  static String get effectiveBaseUrl {
    if (useNgrok) {
      return '$ngrokUrl/api/';
    }
    return apiBaseUrl;
  }

  /// Sentry DSN, injected via --dart-define=SENTRY_DSN=... (Phase 10).
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static const String appDeepLinkHost = 'griot-ai.org';

  /// Local database name — sqflite on mobile, IndexedDB-backed on web via
  /// the sqflite_common_ffi_web factory (set in `main()`).
  static const String databaseName = 'griot_ai.db';
  static const int databaseVersion = 3;
}
