import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A single shimmering placeholder block.
///
/// The app had twenty-six raw `CircularProgressIndicator`s and no skeleton at
/// all, so every list, grid and dashboard waited behind a centred ring. A ring
/// says "something is happening"; a skeleton says "here is the shape of what is
/// arriving", which is why the perceived wait is shorter and why the layout
/// does not jump when the data lands.
///
/// Pairs with [GriotLoader]: use a skeleton for a whole region of content, and
/// the loader for something smaller — a button, a badge, an inline action.
class GriotSkeleton extends StatefulWidget {
  const GriotSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 8,
    this.shape,
  });

  /// A circular placeholder, sized by [height]. Overrides [radius].
  const GriotSkeleton.circle({super.key, required double size, this.width})
    : height = size,
      radius = 0,
      shape = BoxShape.circle;

  final double? width;
  final double height;
  final double radius;
  final BoxShape? shape;

  @override
  State<GriotSkeleton> createState() => _GriotSkeletonState();
}

class _GriotSkeletonState extends State<GriotSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _fade = Tween<double>(begin: 0.32, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Drive the controller from the motion preference rather than only
    // choosing not to *show* the fade. Hiding the FadeTransition while leaving
    // a repeating controller running looks correct and is not: it keeps
    // requesting frames for a value nothing reads, for as long as the
    // placeholder is on screen.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 1.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final block = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: scheme.onSurfaceVariant,
        shape: widget.shape ?? BoxShape.rectangle,
        borderRadius: widget.shape == null
            ? BorderRadius.circular(widget.radius)
            : null,
      ),
    );

    // `disableAnimations` is what the platform reports for
    // `prefers-reduced-motion`. Honour it by holding the block at a single
    // mid-tone instead of pulsing: the placeholder still communicates "not
    // content", and nothing moves.
    if (MediaQuery.disableAnimationsOf(context)) {
      return block;
    }

    return FadeTransition(opacity: _fade, child: block);
  }
}

/// A column of skeleton rows shaped like a list item: a leading circle, a
/// leading line, a shorter trailing line, then text under it.
///
/// Used for the admin dashboard's list sections (users, moderation queue,
/// consent queue, QR worklist) and the notifications inbox, which all render
/// the same kind of row once loaded.
class GriotSkeletonList extends StatelessWidget {
  const GriotSkeletonList({
    super.key,
    this.itemCount = 4,
    this.itemSpacing = AppSpacing.md,
    this.showLeading = true,
  });

  final int itemCount;
  final double itemSpacing;

  /// Whether to draw the circular leading element. Set false for sections whose
  /// rows have no avatar.
  final bool showLeading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < itemCount; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == itemCount - 1 ? 0 : itemSpacing),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showLeading) ...[
                  const GriotSkeleton.circle(size: 28),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vary the trailing line's width per row so the block
                      // does not read as a repeating pattern.
                      GriotSkeleton(
                        width: _leadingWidth(i),
                        height: 13,
                        radius: 6,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      GriotSkeleton(
                        width: _trailingWidth(i),
                        height: 11,
                        radius: 6,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static double _leadingWidth(int index) => switch (index % 3) {
    0 => 180,
    1 => 140,
    _ => 210,
  };

  static double _trailingWidth(int index) => switch (index % 3) {
    0 => 96,
    1 => 130,
    _ => 70,
  };
}

/// A block of skeleton cards, for the dashboard's stat tiles.
class GriotSkeletonCards extends StatelessWidget {
  const GriotSkeletonCards({
    super.key,
    this.itemCount = 4,
    this.height = 96,
    this.spacing = AppSpacing.md,
  });

  final int itemCount;
  final double height;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          Expanded(child: GriotSkeleton(height: height, radius: 16)),
        ],
      ],
    );
  }
}