import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'griot_logo.dart';

/// Full-screen branded splash, mirroring the `web/index.html` `#griot-splash`
/// (Kente-drum orbit loader, pulsing emblem, sliding progress track and
/// blinking caption dots).
///
/// Used with [showAndRun] so flows such as sign-out can play the branded
/// "closing" clip before the app switches screen.
class GriotSplashScreen extends StatelessWidget {
  const GriotSplashScreen({
    super.key,
    this.caption = "Preserving Cameroon's living heritage",
    this.tagline = 'A digital heritage platform',
  });

  /// Caption rendered under the progress track, followed by three blinking
  /// dots. Matches the web splash wording for loading, and the closing wording
  /// ("See you soon", …) for sign-out.
  final String caption;

  /// Uppercased label under the wordmark.
  final String tagline;

  /// Play the splash above [context] while [action] runs, then collapse the
  /// navigator back to the root route. The animation stays on screen for at
  /// least [minDuration] so a fast [action] still reads as an animated
  /// transition — used by sign-out, which lands on the login screen.
  static Future<void> showAndRun(
    BuildContext context, {
    required Future<void> Function() action,
    String caption = 'See you soon',
    Duration minDuration = const Duration(milliseconds: 1800),
  }) async {
    final navigator = Navigator.of(context);
    final route = PageRouteBuilder<void>(
      opaque: true,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => GriotSplashScreen(caption: caption),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    navigator.push(route);

    try {
      final started = DateTime.now();
      await action();
      final elapsed = DateTime.now().difference(started);
      if (elapsed < minDuration) {
        await Future<void>.delayed(minDuration - elapsed);
      }
    } finally {
      if (navigator.mounted) {
        navigator.popUntil((r) => r.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            radius: 1.2,
            colors: [
              Colors.white,
              AppColors.ivory,
              Color(0xFFF3EAD4),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _OrbitLoader(),
              const SizedBox(height: AppSpacing.section),
              _Wordmark(),
              const SizedBox(height: AppSpacing.sm),
              _Tagline(text: tagline),
              const SizedBox(height: AppSpacing.xl),
              const _ProgressTrack(),
              const SizedBox(height: AppSpacing.md),
              _Caption(text: caption),
            ],
          ),
        ),
      ),
    );
  }
}

/// Branded inline loader for content areas: the splash's orbit animation
/// (plus wordmark, progress track and caption in full form) so pages loading
/// data never fall back to a blank screen.
///
/// [compact] renders just a small orbit + caption, sized for card/section
/// slots; the full form fills a content area with the whole splash vocabulary.
class GriotSplashLoader extends StatelessWidget {
  const GriotSplashLoader({
    super.key,
    this.compact = false,
    this.caption,
  });

  final bool compact;

  /// Caption under the loader; default wording per mode.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _OrbitLoader(size: 104),
            if (caption != null) ...[
              const SizedBox(height: AppSpacing.md),
              _Caption(text: caption!),
            ],
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      );
    }

    final label = caption ?? "Preserving Cameroon's living heritage";
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _OrbitLoader(),
            const SizedBox(height: AppSpacing.section),
            const _Wordmark(),
            const SizedBox(height: AppSpacing.sm),
            const _Tagline(text: 'A digital heritage platform'),
            const SizedBox(height: AppSpacing.xl),
            const _ProgressTrack(),
            const SizedBox(height: AppSpacing.md),
            _Caption(text: label),
          ],
        ),
      ),
    );
  }
}

/// Kente-drum orbit loader: three concentric rings (dotted bronze, dashed
/// earth, solid bronze progress) with two beads orbiting the outer ring and the
/// emblem pulsing in the centre — a port of the web splash's `.loader`.
class _OrbitLoader extends StatefulWidget {
  const _OrbitLoader({this.size = 190});

  /// Diameter of the whole orbit; all inner elements scale proportionally.
  final double size;

  @override
  State<_OrbitLoader> createState() => _OrbitLoaderState();
}

class _OrbitLoaderState extends State<_OrbitLoader>
    with TickerProviderStateMixin {
  late final AnimationController _orbit;
  late final AnimationController _dash;
  late final AnimationController _progress;
  late final AnimationController _pulse;

  double get _scale => widget.size / 190;

  @override
  void initState() {
    super.initState();
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
    _dash = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 11),
    )..repeat();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
      lowerBound: 0.94,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _orbit.dispose();
    _dash.dispose();
    _progress.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    final dashInset = 14 * scale;
    final progressInset = 28 * scale;
    final logoSize = 92 * scale;
    final logoPadding = 10 * scale;
    final beadEarth = 12 * scale;
    final beadGold = 9 * scale;
    final stroke = (3 * scale).clamp(1.5, 3.0);
    final lightStroke = (2 * scale).clamp(1.0, 2.0);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer dashed bronze ring, slowly spinning, with two beads.
          RotationTransition(
            turns: _orbit,
            child: SizedBox.expand(
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: _DashedRing(
                      color: AppColors.bronze.withValues(alpha: 0.30),
                      strokeWidth: lightStroke,
                    ),
                  ),
                  Positioned(
                    top: -beadEarth * 0.5,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _Bead(color: AppColors.earth, size: beadEarth),
                    ),
                  ),
                  Positioned(
                    top: -beadGold * 0.5,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _Bead(color: AppColors.bronze, size: beadGold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Inner dashed earth ring spinning in reverse.
          RotationTransition(
            turns: _dash,
            child: Padding(
              padding: EdgeInsets.all(dashInset),
              child: SizedBox.expand(
                child: _DashedRing(
                  color: AppColors.earth.withValues(alpha: 0.28),
                  strokeWidth: lightStroke,
                ),
              ),
            ),
          ),
          // Bronze progress ring.
          RotationTransition(
            turns: _progress,
            child: Padding(
              padding: EdgeInsets.all(progressInset),
              child: SizedBox.expand(
                child: CircularProgressIndicator(
                  strokeWidth: stroke,
                  strokeCap: StrokeCap.round,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.bronze,
                  ),
                  backgroundColor: AppColors.bronze.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
          // Pulsing emblem.
          ScaleTransition(
            scale: _pulse,
            child: Container(
              width: logoSize,
              height: logoSize,
              padding: EdgeInsets.all(logoPadding),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.indigo.withValues(alpha: 0.22),
                    blurRadius: 30 * scale,
                    spreadRadius: 2 * scale,
                  ),
                ],
              ),
              child: const ClipOval(child: GriotMark()),
            ),
          ),
        ],
      ),
    );
  }
}

/// A circular ring made of evenly spaced dashes, so the full-circle border
/// reads as a dotted orbit even though Flutter's `BoxDecoration` offers no
/// dashed border.
class _DashedRing extends StatelessWidget {
  const _DashedRing({required this.color, this.strokeWidth = 2});

  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DashRingPainter(color, strokeWidth));
  }
}

class _DashRingPainter extends CustomPainter {
  const _DashRingPainter(this.color, this.strokeWidth);

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 10.0;
    const gap = 8.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rect = Offset.zero & size;
    final radius = (size.shortestSide - dash) / 2;
    final circumference = 2 * _pi * radius;
    final steps = circumference / (dash + gap);
    for (var i = 0; i < steps; i++) {
      final start = i * (dash + gap) / radius;
      canvas.drawArc(
        rect.deflate(dash / 2),
        start,
        dash / radius,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

const double _pi = 3.141592653589793;

/// Orbiting "kente bead" on the loader rings.
class _Bead extends StatelessWidget {
  const _Bead({required this.color, this.size = 12});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: AppColors.ivory, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

/// "Griot AI" wordmark with the bronze "AI" accent, matching the web splash.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.headlineMedium;
    return Text.rich(
      TextSpan(
        style: base?.copyWith(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w700,
          color: AppColors.indigo,
          letterSpacing: -0.5,
        ),
        children: [
          const TextSpan(text: 'Griot '),
          TextSpan(
            text: 'AI',
            style: const TextStyle(
              fontFamily: 'Fraunces',
              color: AppColors.bronze,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      maxLines: 1,
    );
  }
}

/// Uppercased, letter-spaced tagline.
class _Tagline extends StatelessWidget {
  const _Tagline({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w600,
            letterSpacing: 2.8,
            color: AppColors.accentTextStrong,
          ),
      maxLines: 1,
    );
  }
}

/// Sliding gradient fill on a rounded track — the web splash's `.track/.fill`.
class _ProgressTrack extends StatefulWidget {
  const _ProgressTrack();

  @override
  State<_ProgressTrack> createState() => _ProgressTrackState();
}

class _ProgressTrackState extends State<_ProgressTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(-0.12, 0),
      end: const Offset(1.85, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    return Container(
      width: 176,
      height: 5,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        color: AppColors.bronze.withValues(alpha: 0.16),
      ),
      child: SlideTransition(
        position: slide,
        child: FractionallySizedBox(
          widthFactor: 0.38,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.bronze, AppColors.earth],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Caption line whose three trailing dots blink in sequence.
class _Caption extends StatefulWidget {
  const _Caption({required this.text});

  final String text;

  @override
  State<_Caption> createState() => _CaptionState();
}

class _CaptionState extends State<_Caption> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'PlusJakartaSans',
                color: AppColors.muted,
              ),
        ),
        for (var i = 0; i < 3; i++)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final phase = (_controller.value - i * 0.16) % 1.0;
              final visible = phase < 0.5;
              return AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 90),
                child: const Text('.'),
              );
            },
          ),
      ],
    );
  }
}