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
        return AppDeepLink(kind: DeepLinkKind.region, value: region);
      }
      return null;
    }

    final collection = segments.first.toLowerCase();
    final rest = segments.length > 1 ? segments[1] : '';

    if (collection == 'stories') {
      final region = uri.queryParameters[regionQueryKey];
      if (region != null && region.isNotEmpty) {
        return AppDeepLink(kind: DeepLinkKind.region, value: region);
      }
      return null;
    }

    return _fromCollection(collection, rest);
  }

  static AppDeepLink? _fromCollection(String collection, String slug) {
    if (slug.isEmpty) return null;

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
