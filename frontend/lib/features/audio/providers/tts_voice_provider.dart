import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/tts_voice_model.dart';
import '../services/audio_api_service.dart';

// ---------------------------------------------------------------------------
// Narration voice selection
// ---------------------------------------------------------------------------

/// The reader's chosen narration voice, persisted across launches.
///
/// State is the voice id (`en`, `en.co.uk`, …) or `null` — "Automatic",
/// which means narrate each story in its own language. That is the default
/// and requires no stored value, so a fresh install behaves exactly as the
/// app did before the picker existed.
class TtsVoiceSettingsNotifier extends StateNotifier<String?> {
  TtsVoiceSettingsNotifier() : super(null) {
    _restore();
  }

  static const _storageKey = 'tts_narration_voice_id';

  /// Restores the last choice. Storage being unavailable (tests, web
  /// fallback) must never block narration — staying on Automatic is the
  /// correct degradation.
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      if (mounted && saved != null && saved.isNotEmpty) {
        state = saved;
      }
    } on Exception {
      // No storage, no preference: keep Automatic.
    }
  }

  /// Chooses [voiceId], or `null` to return to Automatic. Persisted so the
  /// choice survives an app restart.
  Future<void> setVoice(String? voiceId) async {
    state = (voiceId == null || voiceId.isEmpty) ? null : voiceId;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (state == null) {
        await prefs.remove(_storageKey);
      } else {
        await prefs.setString(_storageKey, state!);
      }
    } on Exception {
      // The in-memory choice still applies for this session.
    }
  }
}

/// Current narration voice (`null` = Automatic).
final ttsVoiceSettingsProvider =
    StateNotifierProvider<TtsVoiceSettingsNotifier, String?>((ref) {
      return TtsVoiceSettingsNotifier();
    });

/// The voice list from the backend, cached for the session.
///
/// Auth-gated, so it rides the JWT-carrying client; `autoDispose` because
/// only the settings picker needs it.
final ttsVoicesProvider = FutureProvider.autoDispose<List<TtsVoiceModel>>((
  ref,
) async {
  final apiClient = ref.watch(authenticatedApiClientProvider);
  return AudioApiService(dio: apiClient.dio).fetchVoices();
});
