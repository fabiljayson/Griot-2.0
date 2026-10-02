import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Global constants for the Griot AI app.
abstract final class AppConstants {
  static const String appName = 'Griot AI';
  static const String appTagline = 'Digital Heritage Platform';

  /// Default backend base URL inside the Android emulator.
  static const String _defaultApiBaseUrl = 'http://10.0.2.2:8000';

  /// Backend base URL when running on Flutter web (the emulator loopback is
  /// unreachable from a browser).
  static const String _webApiBaseUrl = 'http://localhost:8000';

  /// Backend base URL when running as a desktop application.
  static const String _desktopApiBaseUrl = 'http://127.0.0.1:8000';

  /// Backend base URL.
  ///
  /// Override at build/run time:
  ///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
  ///
  /// ## Shipping a release build
  ///
  /// The compiled-in default is `http://10.0.2.2:8000`, a loopback address
  /// that is unreachable outside an emulator. A release build must therefore
  /// pass the real origin:
  ///
  ///   flutter build apk --release \
  ///     --dart-define=API_BASE_URL=https://api.example.org \
  ///     --dart-define=RELEASE_BUILD=true
  ///
  /// `RELEASE_BUILD` additionally refuses to start on a cleartext origin.
  /// [assertCleartextBaseUrlIsSafe] is the enforcement point, and
  /// `assertProductionConfiguration` in `main.dart` calls it at startup. Do not
  /// ship a build without it: iOS has no ATS exception for this host, so a
  /// cleartext default is blocked by the platform and a release build reaches
  /// the network with no working URL.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultApiBaseUrl,
  );

  /// Whether this build was compiled with `--dart-define=RELEASE_BUILD=true`.
  static const bool isReleaseBuild = bool.fromEnvironment('RELEASE_BUILD');

  /// Effective base URL.
  ///
  /// `10.0.2.2` only resolves inside the Android emulator; a browser cannot
  /// reach it, so web falls back to localhost unless an explicit base URL was
  /// compiled in via --dart-define.
  static String get effectiveBaseUrl => resolveApiBaseUrl(
    configuredBaseUrl: apiBaseUrl,
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  /// Resolves the default development host for the current Flutter target.
  ///
  /// Explicitly configured API URLs always take precedence.
  static String resolveApiBaseUrl({
    required String configuredBaseUrl,
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (configuredBaseUrl != _defaultApiBaseUrl) return configuredBaseUrl;
    if (isWeb) return _webApiBaseUrl;
    if (platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows) {
      return _desktopApiBaseUrl;
    }
    return configuredBaseUrl;
  }

  /// True when [url] is a cleartext origin.
  static bool isCleartextUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'http';
  }

  /// Fail fast when a release build is configured to talk to a cleartext API.
  ///
  /// Android fails closed on its own — `network_security_config.xml` already
  /// rejects cleartext — but iOS has no equivalent exception, so on that
  /// platform this is the only signal that the build is misconfigured. It also
  /// catches the case where a release build was compiled without
  /// `API_BASE_URL` and is about to run against the emulator loopback.
  static void assertCleartextBaseUrlIsSafe() {
    if (!isReleaseBuild) return;
    final url = effectiveBaseUrl;
    if (isCleartextUrl(url)) {
      throw StateError(
        'Refusing to start: release build compiled with a cleartext API base '
        'URL ($url). Rebuild with '
        '--dart-define=API_BASE_URL=https://<origin> '
        '--dart-define=RELEASE_BUILD=true',
      );
    }
  }

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

  /// Public web app origin used when sharing story links (copy/share text).
  static const String appShareBaseUrl = 'https://griot-2-0.vercel.app';

  /// `appShareBaseUrl` without the scheme, for on-brand surfaces such as the
  /// quote-card watermark.
  static String get appShareHost =>
      appShareBaseUrl.replaceAll(RegExp(r'^https?://'), '');

  /// Local database name — sqflite on mobile, IndexedDB-backed on web via
  /// the sqflite_common_ffi_web factory (set in `main()`).
  static const String databaseName = 'griot_ai.db';

  /// v6 added the cover-image backfill for seeded stories.
  /// v7 repairs installs that were created without the `local_*` content
  /// schema and links seeded quizzes to their story.
  static const int databaseVersion = 9;

  /// Developer shown in the WhatsApp feedback prefilled draft.
  static const String developerName = 'Fabil Jayson';

  /// Public WhatsApp number the feedback deep link opens.
  ///
  /// Injectable at build time so the value is not welded into the source and a
  /// future maintainer does not have to edit and rebuild a release to point
  /// feedback at a different address:
  ///
  ///   flutter build apk --dart-define=FEEDBACK_WHATSAPP_NUMBER=237692996791
  ///
  /// The default is the current public number. This is contact information, not
  /// a secret — it is validated for shape by [isValidWhatsAppNumber] before it
  /// reaches a URL, because the value is interpolated straight into a
  /// `wa.me` link and an unvalidated string containing `?`, `#` or `/` would
  /// change the URL's structure rather than its path.
  static const String feedbackWhatsAppNumber = String.fromEnvironment(
    'FEEDBACK_WHATSAPP_NUMBER',
    defaultValue: '237692996791',
  );

  /// True when [number] is a plausible E.164 WhatsApp number.
  static bool isValidWhatsAppNumber(String number) {
    final trimmed = number.trim();
    // E.164: a leading '+' is optional in practice, then 8–15 digits. No
    // spaces, separators or other punctuation, which is what would let a
    // malformed value rewrite the surrounding URL.
    return RegExp(r'^\+?\d{8,15}$').hasMatch(trimmed);
  }

  /// Message pre-filled in WhatsApp when feedback is requested.
  ///
  /// Ends with blank lines so the user's own message starts on a new line.
  static String get feedbackWhatsAppDraft =>
      'Hi $developerName,\n\nI have some feedback about Griot AI:\n\n';
}
