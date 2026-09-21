import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Griot AI brand mark using the official logo image.
///
/// Displays the African mask/emblem logo from the assets.
/// The logo features a circular design with an African face/mask,
/// golden crown points, glowing eyes, and warm earthy tones.
class GriotMark extends StatelessWidget {
  const GriotMark({super.key, this.size = 48, this.borderRadius});

  final double size;

  /// Corner radius; defaults to 50% (circle) for the mask logo.
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: borderRadius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: borderRadius != null
            ? BorderRadius.circular(borderRadius!)
            : null,
        boxShadow: [
          BoxShadow(
            // Bronze glow ring, mirroring the web's ring-cam-bronze/60 logo.
            color: AppColors.bronze.withValues(alpha: 0.28),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: Image.asset(
        'assets/logo/griot_ai_logo.png',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to a styled container if image fails to load
          return Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.indigoDark,
            ),
            child: Center(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: size * 0.35,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                  children: [
                    TextSpan(
                      text: 'G',
                      style: TextStyle(color: AppColors.bronzeLight),
                    ),
                    TextSpan(
                      text: 'A',
                      style: TextStyle(
                        color: AppColors.bronze,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full logo: [GriotMark] + the "Griot AI" wordmark.
///
/// [light] renders the wordmark for use on dark/warm backgrounds (cream
/// text, ochre "AI"); otherwise it uses the deep-earth ink with a terracotta
/// "AI".
class GriotLogo extends StatelessWidget {
  const GriotLogo({
    super.key,
    this.size = 44,
    this.light = false,
    this.tagline,
  });

  final double size;
  final bool light;
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    // Web wordmark: ink "Griot" + bronze "AI" (sidebar), ivory + bronze on
    // dark panels (mobile header).
    final baseColor = light ? AppColors.sand : AppColors.deepEarth;
    final accent = light ? AppColors.bronzeLight : AppColors.bronze;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GriotMark(size: size),
        SizedBox(width: size * 0.30),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: size * 0.50,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  letterSpacing: -0.3,
                ),
                children: [
                  TextSpan(
                    text: 'Griot ',
                    style: TextStyle(color: baseColor),
                  ),
                  TextSpan(
                    text: 'AI',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            if (tagline != null) ...[
              const SizedBox(height: 2),
              Text(
                tagline!,
                style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  fontSize: size * 0.20,
                  fontWeight: FontWeight.w500,
                  color: (light ? AppColors.ochre : AppColors.charcoalMuted)
                      .withValues(alpha: 0.9),
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
