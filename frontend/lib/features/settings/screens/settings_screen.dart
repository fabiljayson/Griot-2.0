import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/widgets/profile/action_tile.dart';
import '../../auth/widgets/profile/section_title.dart';
import '../services/whatsapp_feedback_service.dart';

/// App settings and developer contact.
///
/// Reached as a pushed route from the Profile screen, so it owns its own
/// [Scaffold] and [SafeArea]. Hosts the developer feedback entry point, which
/// hands off to WhatsApp with a pre-filled message ready to send.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SectionTitle(title: 'Support & Feedback'),
            const SizedBox(height: AppSpacing.md),
            ActionTile(
              icon: AppIcons.chat_bubble,
              label: 'Send Feedback via WhatsApp',
              color: AppColors.accentTextStrong,
              onTap: () async {
                final launched =
                    await WhatsAppFeedbackService.openDefaultFeedback();
                if (!launched && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Could not open WhatsApp. Please try again.'),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Share a bug, an idea or a suggestion. Opens WhatsApp to '
              '${AppConstants.developerName} with a message ready to send.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.section),
          ],
        ),
      ),
    );
  }
}