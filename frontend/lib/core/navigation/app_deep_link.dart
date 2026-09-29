import 'package:flutter/widgets.dart';

/// Parsed form of an incoming deep link.
///
/// Kept as a plain value object (no Flutter widgets, no routing side effects) so
/// the URL grammar can be unit-tested on its own —
/// `AppRouter.handle` only has to turn a target into a route.
///
/// Recognised links, matching the links the webapp and the printed QR codes
/// emit:
///
///   griot-ai://story/{slug}
///   https://griot-ai.org/story/{slug}
///   https://griot-ai.org/artifact/{slug}
///   https://griot-ai.org/qr/{slug}
///   https://griot-ai.org/stories?region={slug}
///   https://africanteller.org/artifact/{slug}   (legacy QR codes)
@immutable
class AppDeepLink {
  const AppDeepLink({required this.kind, required this.value});

  final DeepLinkKind kind;

  /// Story slug, artifact slug, or region slug depending on [kind].
  final String value;

  /// Query string values, when the link carried any (e.g. `region`).
  static const String regionQueryKey = 'region';

  /// Longest slug accepted, matching the backend's `SlugField(max_length=250)`.
  ///
  /// A deep link is attacker-supplied: any installed app or any web page can
  /// fire one at this app. The slug is then used as a route argument and sent
  /// to the API, so an unbounded or control-character-laden value is worth
  /// refusing at the door rather than passing along.
  static const int maxSlugLength = 250;

  /// Whether [slug] is shaped like a slug the backend could have produced.
  ///
  /// Django's `SlugField` allows Unicode letters and numbers plus `-` and `_`.
  /// Anything else — spaces, `/`, `..`, quotes, control characters, newlines —
  /// is rejected here so a link cannot smuggle a path or log-injection payload
  /// through the slug argument.
  static bool isValidSlug(String slug) {
    if (slug.isEmpty || slug.length > maxSlugLength) return false;
    return _slugPattern.hasMatch(slug);
  }

  static final RegExp _slugPattern = RegExp(r'^[\p{L}\p{N}_\-]+$', unicode: true);

  /// Parse [uri], returning null when it points at nothing the app can open.
  static AppDeepLink? parse(Uri? uri) {
    if (uri == null) return null;

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // Custom scheme: griot-ai://story/{slug} → host is the collection.
    if (uri.scheme == 'griot-ai') {
      final collection = uri.host.toLowerCase();
      final slug = segments.isNotEmpty ? segments.first : '';
      return _fromCollection(collection, slug);
    }

    // http(s) links carry the collection as the first path segment.
    if (segments.isEmpty) {
      final region = uri.queryParameters[regionQueryKey];
      if (region != null && region.isNotEmpty) {
        return _validOrNull(DeepLinkKind.region, region);
      }
      return null;
    }

    final collection = segments.first.toLowerCase();
    final rest = segments.length > 1 ? segments[1] : '';

    if (collection == 'stories') {
      final region = uri.queryParameters[regionQueryKey];
      if (region != null && region.isNotEmpty) {
        return _validOrNull(DeepLinkKind.region, region);
      }
      return null;
    }

    return _fromCollection(collection, rest);
  }

  /// Build a link, or null when [slug] is not a usable slug.
  static AppDeepLink? _validOrNull(DeepLinkKind kind, String slug) {
    if (!isValidSlug(slug)) return null;
    return AppDeepLink(kind: kind, value: slug);
  }

  static AppDeepLink? _fromCollection(String collection, String slug) {
    if (!isValidSlug(slug)) return null;

    return switch (collection) {
      'story' || 'stories' => AppDeepLink(
        kind: DeepLinkKind.story,
        value: slug,
      ),
      // `qr` is what the museum labels encode.
      'artifact' || 'artifacts' || 'qr' => AppDeepLink(
        kind: DeepLinkKind.artifact,
        value: slug,
      ),
      'region' || 'regions' => AppDeepLink(
        kind: DeepLinkKind.region,
        value: slug,
      ),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AppDeepLink && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'AppDeepLink(${kind.name}: $value)';
}

/// What a deep link points at.
enum DeepLinkKind { story, artifact, region }
