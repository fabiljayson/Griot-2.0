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

  /// Effective base URL — always the local API base URL.
  static String get effectiveBaseUrl => apiBaseUrl;

  /// Sentry DSN, injected via --dart-define=SENTRY_DSN=... (Phase 10).
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static const String appDeepLinkHost = 'griot-ai.org';

  /// Local database name — sqflite on mobile, IndexedDB-backed on web via
  /// the sqflite_common_ffi_web factory (set in `main()`).
  static const String databaseName = 'griot_ai.db';
  static const int databaseVersion = 5;
}
