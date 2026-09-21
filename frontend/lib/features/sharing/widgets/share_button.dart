import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../services/sharing_service.dart';

/// Icon button that opens the share sheet.
class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    required this.title,
    required this.slug,
    required this.summary,
    this.compact = false,
    this.color,
  });

  final String title;
  final String slug;
  final String summary;
  final bool compact;

  /// Overrides the icon colour (e.g. white on a dark app bar). Defaults to the
  /// inherited icon theme so the button adapts to light and dark surfaces.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: FaIcon(AppIcons.share_outlined, size: compact ? 20 : 24, color: color),
      onPressed: () => showShareSheet(context),
      tooltip: 'Share',
    );
  }

  void showShareSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareSheet(title: title, slug: slug, summary: summary),
    );
  }
}

/// Share sheet with platform options.
///
/// The sheet surface and its labels come from the active [ColorScheme]; it used
/// to hardcode the ivory `parchment` surface, which is a light-mode-only panel.
class ShareSheet extends StatelessWidget {
  const ShareSheet({
    super.key,
    required this.title,
    required this.slug,
    required this.summary,
  });

  final String title;
  final String slug;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.hero),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outline,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          Text(
            'Share "$title"',
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xl),

          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.lg,
            crossAxisSpacing: AppSpacing.lg,
            children: [
              _PlatformButton(
                icon: AppIcons.language,
                label: 'Copy Link',
                color: scheme.onSurfaceVariant,
                onTap: () => _share(context, 'link'),
              ),
              _PlatformButton(
                icon: AppIcons.chat_bubble,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () => _share(context, 'whatsapp'),
              ),
              _PlatformButton(
                icon: AppIcons.send,
                label: 'Telegram',
                color: const Color(0xFF0088CC),
                onTap: () => _share(context, 'telegram'),
              ),
              _PlatformButton(
                icon: AppIcons.facebook,
                label: 'Facebook',
                color: const Color(0xFF1877F2),
                onTap: () => _share(context, 'facebook'),
              ),
              _PlatformButton(
                icon: AppIcons.alternate_email,
                label: 'X',
                color: scheme.onSurface,
                onTap: () => _share(context, 'twitter'),
              ),
              _PlatformButton(
                icon: AppIcons.more_horiz,
                label: 'More',
                color: scheme.onSurfaceVariant,
                onTap: () => _share(context, 'other'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  void _share(BuildContext context, String platform) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();

    if (platform == 'link') {
      // Copy Link copies to the clipboard instead of opening the share sheet.
      SharingService.instance.copyLink(slug: slug);
      messenger.showSnackBar(
        const SnackBar(content: Text('Link copied to clipboard')),
      );
      return;
    }

    SharingService.instance.shareToPlatform(
      title: title,
      slug: slug,
      summary: summary,
      platform: platform,
    );
  }
}

class _PlatformButton extends StatelessWidget {
  const _PlatformButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: 'Share to $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: FaIcon(icon, color: color, size: 22),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: theme.textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
