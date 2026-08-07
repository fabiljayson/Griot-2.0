/// Global constants for the African Teller app.
abstract final class AppConstants {
  static const String appName = 'African Teller';
  static const String appTagline = 'Stories of the Motherland';

  /// Backend base URL.
  ///
  /// Override at build/run time:
  ///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Sentry DSN, injected via --dart-define=SENTRY_DSN=... (Phase 10).
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static const String appDeepLinkHost = 'africanteller.org';

  /// Local sqflite database name (mobile). Web uses IndexedDB (Phase 9).
  static const String databaseName = 'african_teller.db';
  static const int databaseVersion = 1;
}
