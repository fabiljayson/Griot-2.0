import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Branded replacement for the default [CircularProgressIndicator].
///
/// The `UI model/font.jpeg` sample defines the loading vocabulary (gold rings,
/// dots and bars); this widget is the single Flutter implementation of it, so
/// screens stop dropping raw Material spinners onto brand surfaces.
class GriotLoader extends StatelessWidget {
  const GriotLoader({
    super.key,
    this.size = 28,
    this.strokeWidth = 2.5,
    this.color,
    this.label,
  });

  /// Small inline loader for buttons and list footers.
  const GriotLoader.inline({super.key, this.color, this.label})
      : size = 18,
        strokeWidth = 2;

  final double size;
  final double strokeWidth;
  final Color? color;

  /// Optional caption rendered beneath the ring.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = color ?? scheme.primary;

    final indicator = SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        strokeCap: StrokeCap.round,
        valueColor: AlwaysStoppedAnimation<Color>(ring),
        backgroundColor: ring.withValues(alpha: 0.18),
      ),
    );

    if (label == null) return indicator;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const SizedBox(height: AppSpacing.md),
        Text(label!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Centered loader with optional caption, sized for a full content area.
class GriotLoadingState extends StatelessWidget {
  const GriotLoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: GriotLoader(size: 34, label: label),
      ),
    );
  }
}

/// Four-dot loader matching the "DOTS" row of the UI-model sample sheet.
///
/// Useful for inline "syncing"/"generating" states where a ring is too heavy.
class GriotDotLoader extends StatefulWidget {
  const GriotDotLoader({super.key, this.color, this.dotSize = 7, this.count = 4});

  final Color? color;
  final double dotSize;
  final int count;

  @override
  State<GriotDotLoader> createState() => _GriotDotLoaderState();
}

class _GriotDotLoaderState extends State<GriotDotLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.count, (index) {
            final phase = (_controller.value - index * 0.18) % 1.0;
            final wave = (1 - (phase * 2 - 1).abs()).clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.dotSize * 0.28),
              child: Container(
                width: widget.dotSize,
                height: widget.dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.25 + wave * 0.75),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
