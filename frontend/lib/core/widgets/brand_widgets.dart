import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'brand_metrics.dart';
import 'brand_pattern_painter.dart';
import 'griot_logo.dart';

/// Breakpoint (px) above which the auth screens show a wide split layout.
const kAuthBreakpointWide = 720;

/// Default brand name for the auth screens.
const kBrandName = 'Griot AI';

/// Default tagline for the auth screens.
const kBrandTagline = 'Digital Heritage Platform';

/// Standard African proverb displayed in branding panels.
const kBrandProverb =
    '"Until the lion learns to write, every story will glorify the hunter."';

// ═══════════════════════════════════════════════════════════════════════
//  BrandScaffold — responsive split-screen layout for auth screens
// ═══════════════════════════════════════════════════════════════════════

/// Responsive scaffold that renders the brand identity on the left
/// (or top on narrow screens) and [child] (typically a form panel) on the
/// right (or bottom).
///
/// Used by [LoginScreen], [RegisterScreen], and the auth loading screen
/// to eliminate triple-duplicated branding code.
class BrandScaffold extends StatelessWidget {
  const BrandScaffold({
    super.key,
    required this.child,
    this.animController,
    this.backgroundColor,
  });

  /// The content panel (form, spinner, etc.) displayed on the right side
  /// (wide) or below the header (compact).
  final Widget child;

  /// Optional [AnimationController] for fade/slide-in on the branding panel.
  /// If null, the branding renders without animation.
  final AnimationController? animController;

  /// Background color for the scaffold. Defaults to
  /// [AppColors.mudCharcoal] on wide screens and the theme surface on
  /// compact screens.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= kAuthBreakpointWide;

    return Scaffold(
      backgroundColor: isWide
          ? (backgroundColor ?? AppColors.mudCharcoal)
          : Theme.of(context).colorScheme.surface,
      body: isWide
          ? _WideLayout(animController: animController, child: child)
          : _CompactLayout(animController: animController, child: child),
    );
  }
}

// --- Wide layout (>= 720 px) ---

class _WideLayout extends StatelessWidget {
  const _WideLayout({this.animController, required this.child});

  final AnimationController? animController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: BrandPanel(animController: animController),
        ),
        Expanded(
          flex: 4,
          child: child,
        ),
      ],
    );
  }
}

// --- Compact layout (< 720 px) ---

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({this.animController, required this.child});

  final AnimationController? animController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            BrandHeader(animController: animController),
            child,
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  BrandPanel — full-height branding panel (left side on wide screens)
// ═══════════════════════════════════════════════════════════════════════

/// Full-height dark branding panel shown on the left side of wide screens.
///
/// Contains the logo, brand name, tagline, proverb, and metrics row.
class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key, this.animController});

  final AnimationController? animController;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.brandGradientWide),
      child: Stack(
        children: [
          // Decorative pattern overlay
          Positioned.fill(
            child: CustomPaint(painter: BrandPatternPainter()),
          ),
          // Warm glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.3, 0.2),
                  radius: 1.2,
                  colors: [
                    AppColors.terracotta.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Content
          Center(
            child: _buildContent(screenWidth),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(double screenWidth) {
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GriotMark(size: 80),
          const SizedBox(height: 32),
          const _BrandNameText(fontSize: 36, letterSpacing: -0.5),
          const SizedBox(height: 8),
          const _BrandTaglineText(fontSize: 14, letterSpacing: 1.5),
          const SizedBox(height: 40),
          _buildProverbCard(),
          const SizedBox(height: 40),
          const BrandMetricsRow(),
        ],
      ),
    );

    if (animController == null) return content;

    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animController!,
        curve: const Interval(0.0, 0.6),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animController!,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
        )),
        child: content,
      ),
    );
  }

  static Widget _buildProverbCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.terracotta.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.terracotta.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          FaIcon(
            AppIcons.auto_stories_outlined,
            color: AppColors.ochreDark.withValues(alpha: 0.8),
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            kBrandProverb,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: AppColors.sand.withValues(alpha: 0.9),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '— African Proverb',
            style: TextStyle(
              fontFamily: 'PlusJakartaSans',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.ochreDark.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  BrandHeader — compact branding header (mobile top section)
// ═══════════════════════════════════════════════════════════════════════

/// Compact branding header shown at the top on narrow screens.
///
/// Contains the logo, brand name, and tagline in a condensed layout.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.animController});

  final AnimationController? animController;

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
      decoration:
          const BoxDecoration(gradient: AppColors.brandGradientCompact),
      child: Column(
        children: [
          const GriotMark(size: 64),
          const SizedBox(height: 20),
          const _BrandNameText(fontSize: 28, letterSpacing: -0.3),
          const SizedBox(height: 6),
          const _BrandTaglineText(fontSize: 12, letterSpacing: 1.2),
        ],
      ),
    );

    if (animController != null) {
      content = FadeTransition(
        opacity: CurvedAnimation(
          parent: animController!,
          curve: const Interval(0.0, 0.5),
        ),
        child: content,
      );
    }

    return content;
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Shared text components
// ═══════════════════════════════════════════════════════════════════════

/// Brand name text: "Griot" in sand + "AI" in ochre dark.
class _BrandNameText extends StatelessWidget {
  const _BrandNameText({this.fontSize = 36, this.letterSpacing = -0.5});

  final double fontSize;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontFamily: 'Fraunces',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.1,
          letterSpacing: letterSpacing,
        ),
        children: [
          TextSpan(
            text: 'Griot ',
            style: TextStyle(color: AppColors.sand),
          ),
          TextSpan(
            text: 'AI',
            style: TextStyle(
              color: AppColors.ochreDark,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Digital Heritage Platform" tagline text.
class _BrandTaglineText extends StatelessWidget {
  const _BrandTaglineText({this.fontSize = 14, this.letterSpacing = 1.5});

  final double fontSize;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    return Text(
      kBrandTagline,
      style: TextStyle(
        fontFamily: 'PlusJakartaSans',
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: AppColors.ochreTint.withValues(alpha: 0.7),
        letterSpacing: letterSpacing,
      ),
    );
  }
}
