import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

import '../constants/app_constants.dart';
import '../theme/app_icons.dart';
import '../theme/app_spacing.dart';

/// Where an image reference is coming from.
enum GriotImageSource {
  /// A bundled Flutter asset (`assets/...`).
  asset,

  /// A network URL (absolute, or media-relative).
  network,

  /// Nothing usable — render the placeholder.
  none,
}

/// Classifies an image reference so the widget is unit-testable without a
/// widget tree.
abstract final class GriotImageResolver {
  /// Decide how [source] should be loaded.
  static GriotImageSource classify(String? source) {
    if (source == null || source.trim().isEmpty) return GriotImageSource.none;
    if (AppConstants.isAssetPath(source.trim())) return GriotImageSource.asset;
    return GriotImageSource.network;
  }

  /// The URL to load for a network reference, or null when unusable.
  static String? networkUrl(String? source) =>
      AppConstants.resolveMediaUrl(source, baseUrl: AppConstants.effectiveBaseUrl);
}

/// The app's single image widget.
///
/// Replaces the five ad-hoc image call sites that previously existed
/// (`Image.network` in story cards, `CachedNetworkImage` in the library, the
/// asset-only branch in the trending strip, ...), each of which handled a
/// different subset of the formats the API returns. Every image in the app now
/// resolves the same way and gets the same loading/error/placeholder treatment.
///
/// Never renders a decorative emoji and never renders a gradient: placeholders
/// are a solid surface with a real icon, matching the webapp's behaviour.
class GriotImage extends StatelessWidget {
  const GriotImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.blurhash,
    this.placeholderIcon,
    this.semanticLabel,
    this.alignment = Alignment.center,
  });

  /// Asset path, absolute URL, or backend media path.
  final String? source;

  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Optional blurhash string (the API provides `cover_image_blurhash` /
  /// `image_blurhash`) used as the loading state.
  final String? blurhash;

  /// Icon shown in the placeholder/error state. Defaults to a book icon.
  final IconData? placeholderIcon;

  /// Accessibility label for the image.
  final String? semanticLabel;

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final clipped = borderRadius == null
        ? _buildContent(context)
        : ClipRRect(borderRadius: borderRadius!, child: _buildContent(context));

    if (semanticLabel == null) return clipped;
    return Semantics(label: semanticLabel, image: true, child: clipped);
  }

  Widget _buildContent(BuildContext context) {
    switch (GriotImageResolver.classify(source)) {
      case GriotImageSource.asset:
        return Image.asset(
          source!,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          semanticLabel: semanticLabel,
          errorBuilder: (context, error, stackTrace) => _placeholder(context),
        );
      case GriotImageSource.network:
        final url = GriotImageResolver.networkUrl(source);
        if (url == null) return _placeholder(context);
        return CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (context, _) => _loading(context),
          errorWidget: (context, _, _) => _placeholder(context),
        );
      case GriotImageSource.none:
        return _placeholder(context);
    }
  }

  Widget _loading(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hash = blurhash?.trim();
    if (hash != null && hash.isNotEmpty) {
      try {
        final blur = BlurHash(
          hash: hash,
          imageFit: fit,
          color: scheme.surfaceContainerHighest,
        );
        if (width != null || height != null) {
          return SizedBox(width: width, height: height, child: blur);
        }
        return blur;
      } catch (_) {
        // Malformed blurhash — fall through to the plain surface.
      }
    }
    return _surface(
      context,
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            scheme.primary.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _surface(
      context,
      child: Icon(
        placeholderIcon ?? AppIcons.auto_stories,
        size: _placeholderIconSize,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );
  }

  Widget _surface(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: scheme.surfaceContainerHighest,
      child: child,
    );
  }

  double get _placeholderIconSize {
    final basis = height ?? width ?? 48;
    return (basis * 0.34).clamp(18, 56);
  }
}

/// Square avatar-like image used for authors and small thumbnails.
class GriotThumbnail extends StatelessWidget {
  const GriotThumbnail({
    super.key,
    required this.source,
    this.size = AppSizes.thumb,
    this.blurhash,
    this.semanticLabel,
  });

  final String? source;
  final double size;
  final String? blurhash;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return GriotImage(
      source: source,
      width: size,
      height: size,
      blurhash: blurhash,
      semanticLabel: semanticLabel,
      placeholderIcon: AppIcons.auto_stories_outlined,
      borderRadius: BorderRadius.circular(AppRadius.chip),
    );
  }
}

/// Consistently-shaped image for cards: fixed aspect ratio cover.
class GriotCoverImage extends StatelessWidget {
  const GriotCoverImage({
    super.key,
    required this.source,
    this.aspectRatio = AppSizes.coverAspect,
    this.blurhash,
    this.borderRadius,
    this.semanticLabel,
    this.overlay,
  });

  final String? source;
  final double aspectRatio;
  final String? blurhash;
  final BorderRadius? borderRadius;
  final String? semanticLabel;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final image = AspectRatio(
      aspectRatio: aspectRatio,
      child: GriotImage(
        source: source,
        blurhash: blurhash,
        semanticLabel: semanticLabel,
        width: double.infinity,
        placeholderIcon: AppIcons.image_outlined,
      ),
    );

    if (overlay == null) return image;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        image,
        Positioned.fill(child: overlay!),
      ],
    );
  }
}
