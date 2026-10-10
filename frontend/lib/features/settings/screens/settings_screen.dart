import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../audio/models/tts_voice_model.dart';
import '../../audio/providers/tts_voice_provider.dart';
import '../../auth/widgets/profile/action_tile.dart';
import '../../auth/widgets/profile/section_title.dart';
import '../services/whatsapp_feedback_service.dart';

/// App settings and developer contact.
///
/// Reached as a pushed route from the Profile screen, so it owns its own
/// [Scaffold] and [SafeArea]. Hosts the developer feedback entry point, which
/// hands off to WhatsApp with a pre-filled message ready to send, and the
/// narration voice picker for the text-to-speech player.
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
            const NarrationVoiceSection(),
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

/// Narration voice row plus its explanatory caption.
///
/// Lives in the `audio` feature's provider layer for the state; this widget
/// only renders the current choice and hosts the picker sheet.
class NarrationVoiceSection extends ConsumerWidget {
  const NarrationVoiceSection({super.key});

  /// Shown when the voice list hasn't loaded (offline, before first fetch).
  /// Mirrors `SUPPORTED_LANGUAGES`/`ENGLISH_TLDS` on the backend; the live
  /// list replaces it whenever it is available.
  static const Map<String, String> fallbackVoiceNames = {
    'en': 'English (US)',
    'en.co.uk': 'English (UK)',
    'fr': 'French',
    'es': 'Spanish',
    'pt': 'Portuguese',
    'de': 'German',
    'sw': 'Swahili',
    'ig': 'Igbo',
    'yo': 'Yoruba',
    'ha': 'Hausa',
    'am': 'Amharic',
  };

  static String labelFor(String? voiceId, List<TtsVoiceModel>? voices) {
    if (voiceId == null) return 'Automatic';
    for (final voice in voices ?? const <TtsVoiceModel>[]) {
      if (voice.id == voiceId) return voice.name;
    }
    return fallbackVoiceNames[voiceId] ?? voiceId;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedVoice = ref.watch(ttsVoiceSettingsProvider);
    final voices = ref.watch(ttsVoicesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Narration'),
        const SizedBox(height: AppSpacing.md),
        ActionTile(
          icon: AppIcons.volume_up,
          label: 'Narration voice: '
              '${labelFor(selectedVoice, voices.valueOrNull)}',
          color: AppColors.accentTextStrong,
          onTap: () => _showVoicePicker(context),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Google text-to-speech voice used for story narrations and '
          'artifact audio guides. Automatic narrates each story in its own '
          'language; picking a voice always uses it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.section),
      ],
    );
  }

  void _showVoicePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 480),
          child: const _VoicePickerList(),
        ),
      ),
    );
  }
}

/// Scrollable list of voices with the current choice ticked.
class _VoicePickerList extends ConsumerWidget {
  const _VoicePickerList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final voices = ref.watch(ttsVoicesProvider);
    final selectedVoice = ref.watch(ttsVoiceSettingsProvider);

    return voices.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stackTrace) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load the voice list. Check your connection.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: () => ref.invalidate(ttsVoicesProvider),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
      data: (voiceList) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: Icon(
              selectedVoice == null ? Icons.check_circle : Icons.circle_outlined,
              color: selectedVoice == null
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            title: const Text('Automatic'),
            subtitle: const Text('Narrate each story in its own language'),
            onTap: () {
              ref.read(ttsVoiceSettingsProvider.notifier).setVoice(null);
              Navigator.of(context).pop();
            },
          ),
          const Divider(),
          for (final voice in voiceList)
            ListTile(
              leading: Icon(
                selectedVoice == voice.id
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: selectedVoice == voice.id
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              title: Text(voice.name),
              subtitle: Text(voice.language.toUpperCase()),
              onTap: () {
                ref
                    .read(ttsVoiceSettingsProvider.notifier)
                    .setVoice(voice.id);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}
