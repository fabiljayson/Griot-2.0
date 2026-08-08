import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Animated progress bar showing XP towards next level.
///
/// Displays current level, XP progress, and streak info.
class LevelProgressBar extends StatefulWidget {
  const LevelProgressBar({
    super.key,
    required this.level,
    required this.totalXp,
    required this.xpProgress,
    required this.xpForNextLevel,
    this.currentStreak = 0,
    this.showStreak = true,
  });

  final int level;
  final int totalXp;
  final double xpProgress;
  final int xpForNextLevel;
  final int currentStreak;
  final bool showStreak;

  @override
  State<LevelProgressBar> createState() => _LevelProgressBarState();
}

class _LevelProgressBarState extends State<LevelProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _progressAnimation = Tween<double>(
      begin: 0,
      end: widget.xpProgress,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(LevelProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.xpProgress != widget.xpProgress) {
      _progressAnimation =
          Tween<double>(
            begin: oldWidget.xpProgress,
            end: widget.xpProgress,
          ).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          );
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.terracotta.withValues(alpha: 0.05),
            AppColors.ochreTint.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.terracotta.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Level and XP info
          Row(
            children: [
              // Level badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.terracotta,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Level ${widget.level}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),

              // XP display
              Text(
                '${widget.totalXp} XP',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.ochre,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress bar
          AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, child) {
              return Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progressAnimation.value,
                      backgroundColor: AppColors.parchmentDark,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.terracotta,
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(widget.xpProgress * widget.xpForNextLevel).round()} / ${widget.xpForNextLevel} XP',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.charcoalMuted,
                        ),
                      ),
                      Text(
                        '${((1 - widget.xpProgress) * widget.xpForNextLevel).round()} XP to Level ${widget.level + 1}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.charcoalMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),

          // Streak
          if (widget.showStreak && widget.currentStreak > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  '${widget.currentStreak} day streak',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.ochre,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
