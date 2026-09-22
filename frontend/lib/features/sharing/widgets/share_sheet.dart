import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../services/sharing_service.dart';

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
            // Five tiles (no logo exists for X in Material's icon set and a
            // "More" tile duplicated the system share sheet), so the row
            // shows 4 + 1 instead of a padded 4 + 2.
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.lg,
            crossAxisSpacing: AppSpacing.lg,
            // Icon circle (48) + gap + label needs ~68px; 0.8 keeps the
            // tile tall enough on ~320dp phones where each cell is ~58px
            // wide. (Aspect 1.0 overflowed tiles by ~10px there.)
            childAspectRatio: 0.8,
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
                icon: AppIcons.share_outlined,
                label: 'Share',
                semanticLabel: 'Share via other apps',
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
    String? semanticLabel,
  }) : _semanticLabel = semanticLabel;

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// Screen-reader label; defaults to "Share to [label]".
  final String? _semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: _semanticLabel ?? 'Share to $label',
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
              child: Icon(icon, color: color, size: 22),
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
