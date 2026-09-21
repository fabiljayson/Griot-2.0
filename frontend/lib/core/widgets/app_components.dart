import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_spacing.dart';
import 'griot_loader.dart';

/// The app's single card surface.
///
/// Matches the webapp's card recipe (`rounded-2xl border border-brand-border
/// bg-white shadow-sm`, see `story_card.html`): solid surface, 1 px outline,
/// radius 16, no gradient, no decorative overlay. Elevation is opt-in so list
/// cards stay flat and only raised surfaces lift.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = AppRadius.card,
    this.onTap,
    this.elevated = false,
    this.borderColor,
    this.color,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool elevated;
  final Color? borderColor;
  final Color? color;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? scheme.outline),
    );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.fromBorderSide(shape.side),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: scheme.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return decorated;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: decorated,
      ),
    );
  }
}

/// Section heading used across Home, Library, Rewards and Artifacts.
///
/// Mirrors the webapp pattern: a bronze accent icon followed by a Fraunces
/// title, with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final FaIconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            FaIcon(icon, color: AppColors.bronze, size: 20),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Neutral "nothing here yet" state with an optional call to action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = AppIcons.auto_stories_outlined,
    this.action,
  });

  final String title;
  final String? subtitle;
  final FaIconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              icon,
              size: 56,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Failure state with a retry affordance. Used by every list screen so API
/// failures are never silently rendered as an empty list.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.onRetry,
    this.icon = AppIcons.error_outline,
  });

  final String message;
  final String title;
  final VoidCallback? onRetry;
  final FaIconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const FaIcon(AppIcons.refresh, size: 16),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-area loading state that also works as a list footer.
class LoadingSliver extends StatelessWidget {
  const LoadingSliver({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => GriotLoadingState(label: label);
}

/// Small pill used for region/category metadata on cards.
class MetadataPill extends StatelessWidget {
  const MetadataPill({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final FaIconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = color ?? scheme.onSurfaceVariant;

    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            FaIcon(icon, size: 11, color: tone),
            const SizedBox(width: AppSpacing.xs + 1),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}

/// Progress row: a track plus its own dedicated percentage slot.
///
/// Exists so a progress value can never be laid over a title again — the value
/// gets its own box next to the bar (mirrors `library.html`'s
/// `bar + <span>{{ progress_percent }}%</span>` row).
class ProgressRow extends StatelessWidget {
  const ProgressRow({
    super.key,
    required this.fraction,
    this.label,
    this.trailingLabel,
    this.thickness = 6,
    this.showValue = true,
  });

  /// 0.0 – 1.0.
  final double fraction;

  /// Optional leading caption (e.g. "45% read").
  final String? label;

  /// Optional trailing text; defaults to the rounded percentage.
  final String? trailingLabel;

  final double thickness;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = fraction.clamp(0.0, 1.0);
    final percent = (value * 100).round();

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(thickness / 2),
            child: LinearProgressIndicator(
              value: value,
              minHeight: thickness,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(label!, style: theme.textTheme.bodySmall),
        ],
        if (showValue) ...[
          SizedBox(
            width: 46,
            child: Text(
              trailingLabel ?? '$percent%',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
