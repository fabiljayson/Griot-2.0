/// Constants and the deep-link grammar for the VR handoff.
///
/// The scheme and host here describe a link **we send to** another application,
/// not one we receive — the Unity VR app registers `griotvr://launch` and this
/// app fires it. They must agree with `VR_DEEP_LINK_SCHEME` /
/// `VR_DEEP_LINK_HOST` in the backend (`config/settings/base.py`) and with the
/// intent filter in `vr/Assets/Plugins/Android/AndroidManifest.xml`; the three
/// are compared in code review, which is why the values are named constants in
/// each codebase rather than literals scattered through call sites.
abstract final class VrConstants {
  /// Scheme the Unity application registers.
  static const String scheme = 'griotvr';

  /// Host component of the launch link (`griotvr://launch?...`).
  static const String launchHost = 'launch';

  /// Android package of the Unity build.
  ///
  /// Declared in `AndroidManifest.xml`'s `<queries>` so the "is it installed?"
  /// check can see the package at all under Android 11+ package visibility.
  static const String unityPackageName = 'org.africanteller.griotvr';

  /// Query parameter carrying the single-use launch token.
  static const String tokenParam = 'token';

  /// Query parameter carrying the experience id.
  static const String experienceParam = 'experience';

  /// Query parameter carrying the artifact id, when the reader came from one.
  static const String artifactParam = 'artifact';

  /// Shortest token worth sending.
  ///
  /// The backend mints 32 bytes of `secrets` entropy, URL-safe encoded into 43
  /// characters. The floor here is deliberately looser than that so a future
  /// shortening of the token does not require a client release, while still
  /// refusing the empty and near-empty values a hand-crafted intent would use.
  static const int minTokenLength = 16;

  /// Longest token we will put in an Intent. The backend caps at 200.
  static const int maxTokenLength = 200;
}

/// Builds and validates the `griotvr://launch` link.
///
/// The API response already contains a ready-made link, and this deliberately
/// does not use it verbatim. The response is attacker-influenced in the only
/// way that matters here — it is a string that becomes an Android Intent — so
/// the client parses it, checks the scheme, host and every parameter, and then
/// **rebuilds** the URI from the validated parts. A malformed or unexpected
/// link then fails here, on the phone, instead of being handed to the OS.
abstract final class VrDeepLink {
  /// Characters a launch token may contain: the URL-safe base64 alphabet.
  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Whether [token] is shaped like a token this platform could have minted.
  static bool isPlausibleToken(String token) {
    if (token.length < VrConstants.minTokenLength) return false;
    if (token.length > VrConstants.maxTokenLength) return false;
    return _tokenPattern.hasMatch(token);
  }

  /// Build the launch URI from already-validated parts.
  static Uri build({
    required String token,
    required int experienceId,
    int? artifactId,
  }) {
    return Uri(
      scheme: VrConstants.scheme,
      host: VrConstants.launchHost,
      queryParameters: {
        VrConstants.tokenParam: token,
        VrConstants.experienceParam: '$experienceId',
        if (artifactId != null) VrConstants.artifactParam: '$artifactId',
      },
    );
  }

  /// Parse and validate a link from the API, returning a rebuilt URI or null.
  ///
  /// Returns null for anything that is not *exactly* a launch link with a
  /// usable token and experience id — a wrong scheme, a missing host, a
  /// non-numeric id, a token with characters that do not belong in one.
  static Uri? parseAndValidate(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.scheme != VrConstants.scheme) return null;
    if (uri.host != VrConstants.launchHost) return null;

    final token = uri.queryParameters[VrConstants.tokenParam] ?? '';
    if (!isPlausibleToken(token)) return null;

    final experienceId = int.tryParse(
      uri.queryParameters[VrConstants.experienceParam] ?? '',
    );
    if (experienceId == null || experienceId <= 0) return null;

    final rawArtifact = uri.queryParameters[VrConstants.artifactParam];
    final artifactId = rawArtifact == null ? null : int.tryParse(rawArtifact);
    if (rawArtifact != null && (artifactId == null || artifactId <= 0)) {
      return null;
    }

    return build(
      token: token,
      experienceId: experienceId,
      artifactId: artifactId,
    );
  }

  /// True when [uri] targets the Unity application's launch host.
  static bool isLaunchUri(Uri uri) =>
      uri.scheme == VrConstants.scheme && uri.host == VrConstants.launchHost;
}
