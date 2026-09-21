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

  /// Django `MEDIA_URL`.
  static const String mediaPath = '/media/';

  /// Resolve an image reference coming from the backend into a loadable URL.
  ///
  /// Handles every shape the API actually returns:
  ///   - absolute URLs  (`http://host/media/x.jpg`) → unchanged
  ///   - root-relative  (`/media/x.jpg`)           → host + path
  ///   - media-relative (`stories/covers/x.jpg`)   → host + `/media/` + path
  ///
  /// Returns `null` for null/blank input so callers can fall back to a
  /// placeholder instead of requesting an invalid URL.
  static String? mediaUrl(String? path) {
    return resolveMediaUrl(path, baseUrl: effectiveBaseUrl);
  }

  /// Pure, testable form of [mediaUrl].
  static String? resolveMediaUrl(String? path, {required String baseUrl}) {
    if (path == null) return null;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    if (trimmed.startsWith('/')) return '$base$trimmed';
    return '$base$mediaPath$trimmed';
  }

  /// True when the reference points at a bundled Flutter asset.
  static bool isAssetPath(String? path) =>
      path != null && path.startsWith('assets/');

  /// Sentry DSN, injected via --dart-define=SENTRY_DSN=... (Phase 10).
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static const String appDeepLinkHost = 'griot-ai.org';

  /// Local database name — sqflite on mobile, IndexedDB-backed on web via
  /// the sqflite_common_ffi_web factory (set in `main()`).
  static const String databaseName = 'griot_ai.db';

  /// v6 added the cover-image backfill for seeded stories.
  /// v7 repairs installs that were created without the `local_*` content
  /// schema and links seeded quizzes to their story.
  static const int databaseVersion = 7;
}
