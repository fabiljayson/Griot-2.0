import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Displays a small animated equalizer while narration is playing.
class AudioPlaybackIndicator extends StatefulWidget {
  const AudioPlaybackIndicator({
    super.key,
    required this.isPlaying,
    this.color = AppColors.bronze,
  });

  static const double _barWidth = 3;
  static const double _barHeight = 18;
  static const double _width = 20;

  final bool isPlaying;
  final Color color;

  @override
  State<AudioPlaybackIndicator> createState() => _AudioPlaybackIndicatorState();
}

class _AudioPlaybackIndicatorState extends State<AudioPlaybackIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(AudioPlaybackIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) _syncAnimation();
  }

  void _syncAnimation() {
    final shouldAnimate =
        widget.isPlaying && !MediaQuery.of(context).disableAnimations;
    if (shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shouldAnimate =
        widget.isPlaying && !MediaQuery.of(context).disableAnimations;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = shouldAnimate
            ? Curves.easeInOutCubic.transform(_controller.value)
            : 0.5;
        final scales = widget.isPlaying
            ? [
                0.25 + progress * 0.65,
                0.8 - progress * 0.45,
                0.3 + progress * 0.55,
              ]
            : const [0.35, 0.35, 0.35];

        return SizedBox(
          width: AudioPlaybackIndicator._width,
          height: AudioPlaybackIndicator._barHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final scale in scales)
                Transform.scale(
                  scaleY: scale,
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(AppSpacing.unit / 2),
                    ),
                    child: const SizedBox(
                      width: AudioPlaybackIndicator._barWidth,
                      height: AudioPlaybackIndicator._barHeight,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
