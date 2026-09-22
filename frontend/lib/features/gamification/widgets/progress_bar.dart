import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_components.dart';

/// Animated XP progress towards the next level.
///
/// Displays the current level, XP progress and streak. Previously this was
/// painted with a bespoke terracotta→ochre gradient and `parchmentDark` track,
/// neither of which is part of the webapp's design language and both of which
/// broke in dark mode (a light wash over a dark surface). It now uses the same
/// card recipe as every other surface plus the shared [ProgressRow].
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
      end: widget.xpProgress.clamp(0.0, 1.0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void didUpdateWidget(LevelProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.xpProgress != widget.xpProgress) {
      _progressAnimation =
          Tween<double>(
            begin: oldWidget.xpProgress.clamp(0.0, 1.0),
            end: widget.xpProgress.clamp(0.0, 1.0),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Level pill. Bronze with dark ink reads on both themes because
              // the pill supplies its own background.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.star,
                      color: scheme.onSecondary,
                      size: 14,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Level ${widget.level}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  '${widget.totalXp} XP',
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, child) => ProgressRow(
              fraction: _progressAnimation.value,
              thickness: 8,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${(widget.xpProgress * widget.xpForNextLevel).round()} / '
                  '${widget.xpForNextLevel} XP',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  '${((1 - widget.xpProgress.clamp(0.0, 1.0)) * widget.xpForNextLevel).round()} XP '
                  'to Level ${widget.level + 1}',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),

          if (widget.showStreak && widget.currentStreak > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(
                  AppIcons.bolt_outlined,
                  size: 14,
                  color: scheme.secondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${widget.currentStreak} day streak',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.secondary,
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
