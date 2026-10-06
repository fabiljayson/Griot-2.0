import '../vr_constants.dart';

/// A summary of the experience a reader is about to enter.
///
/// Deliberately a summary: the phone never needs the scene manifest (that is
/// Unity's payload, fetched after the handoff), only enough to tell the reader
/// what they are opening and to log which one it was.
class VrExperience {
  const VrExperience({
    required this.id,
    this.slug = '',
    this.title = '',
    this.description = '',
    this.sceneIdentifier = '',
    this.language = 'en',
  });

  final int id;
  final String slug;
  final String title;
  final String description;
  final String sceneIdentifier;
  final String language;

  factory VrExperience.fromJson(Map<String, dynamic> json) {
    return VrExperience(
      id: json['id'] as int? ?? 0,
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sceneIdentifier: json['scene_identifier'] as String? ?? '',
      language: json['language'] as String? ?? 'en',
    );
  }
}

/// The artifact the launch was requested for, when there was one.
class VrArtifactRef {
  const VrArtifactRef({required this.id, this.slug = '', this.name = ''});

  final int id;
  final String slug;
  final String name;

  factory VrArtifactRef.fromJson(Map<String, dynamic> json) {
    return VrArtifactRef(
      id: json['id'] as int? ?? 0,
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

/// One issued launch token and everything needed to describe it.
///
/// The token is a bearer credential that lives for seconds and works once. It
/// is held in memory only — never written to the database, secure storage or
/// logs — because a token at rest on the device is a token that outlives its
/// own expiry.
class VrLaunchTicket {
  const VrLaunchTicket({
    required this.token,
    required this.deepLink,
    required this.expiresAt,
    required this.expiresInSeconds,
    required this.experience,
    this.artifact,
  });

  final String token;

  /// The link as the server built it. Validated and rebuilt before use by
  /// [VrDeepLink.parseAndValidate] — never fired as-is.
  final String deepLink;

  final DateTime? expiresAt;
  final int expiresInSeconds;
  final VrExperience experience;
  final VrArtifactRef? artifact;

  factory VrLaunchTicket.fromJson(Map<String, dynamic> json) {
    final experience = json['experience'];
    final artifact = json['artifact'];

    return VrLaunchTicket(
      token: json['token'] as String? ?? '',
      deepLink: json['deep_link'] as String? ?? '',
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
      expiresInSeconds: json['expires_in'] as int? ?? 0,
      experience: VrExperience.fromJson(
        experience is Map<String, dynamic> ? experience : const {},
      ),
      artifact: artifact is Map<String, dynamic>
          ? VrArtifactRef.fromJson(artifact)
          : null,
    );
  }

  /// Whether the ticket has lapsed, allowing a small clock skew.
  ///
  /// Devices are not perfectly in step with the server, and a ticket that is
  /// valid server-side must not be discarded because the phone's clock runs a
  /// few seconds fast.
  bool get isExpired {
    final expiry = expiresAt;
    if (expiry == null) {
      return expiresInSeconds <= 0;
    }
    return DateTime.now().toUtc().isAfter(expiry.toUtc());
  }

  /// Whether this ticket is complete enough to attempt a launch.
  bool get isUsable =>
      token.isNotEmpty &&
      deepLink.isNotEmpty &&
      experience.id > 0 &&
      !isExpired;
}
