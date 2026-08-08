import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../services/sharing_service.dart';

/// Share button that opens a platform picker.
class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    required this.title,
    required this.slug,
    required this.summary,
    this.compact = false,
  });

  final String title;
  final String slug;
  final String summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        icon: const Icon(Icons.share_outlined, size: 20),
        onPressed: () => _showShareSheet(context),
        tooltip: 'Share',
      );
    }

    return IconButton(
      icon: const Icon(Icons.share_outlined, color: Colors.white),
      onPressed: () => _showShareSheet(context),
    );
  }

  void _showShareSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareSheet(title: title, slug: slug, summary: summary),
    );
  }
}

/// Share sheet with platform options.
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
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.charcoalMuted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Share "$title"',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),

          // Platform buttons
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              _buildPlatformButton(
                context,
                icon: Icons.language,
                label: 'Copy Link',
                color: AppColors.charcoalMuted,
                onTap: () => _share(context, 'link'),
              ),
              _buildPlatformButton(
                context,
                icon: Icons.chat_bubble,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () => _share(context, 'whatsapp'),
              ),
              _buildPlatformButton(
                context,
                icon: Icons.send,
                label: 'Telegram',
                color: const Color(0xFF0088cc),
                onTap: () => _share(context, 'telegram'),
              ),
              _buildPlatformButton(
                context,
                icon: Icons.facebook,
                label: 'Facebook',
                color: const Color(0xFF1877F2),
                onTap: () => _share(context, 'facebook'),
              ),
              _buildPlatformButton(
                context,
                icon: Icons.alternate_email,
                label: 'Twitter',
                color: const Color(0xFF1DA1F2),
                onTap: () => _share(context, 'twitter'),
              ),
              _buildPlatformButton(
                context,
                icon: Icons.more_horiz,
                label: 'More',
                color: AppColors.charcoalMuted,
                onTap: () => _share(context, 'other'),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPlatformButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppColors.charcoalMuted),
          ),
        ],
      ),
    );
  }

  void _share(BuildContext context, String platform) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
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
