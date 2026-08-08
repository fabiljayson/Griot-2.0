import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_model.dart';
import '../models/narration_job_model.dart';
import '../services/audio_api_service.dart';
import '../services/audio_player_service.dart';

/// Audio player state notifier.
class AudioPlayerNotifier extends StateNotifier<AudioPlayerState> {
  AudioPlayerNotifier() : super(const AudioPlayerState()) {
    _listenToService();
  }

  final _service = AudioPlayerService.instance;

  void _listenToService() {
    _service.stateStream.listen((serviceState) {
      state = serviceState;
    });
  }

  /// Play an audio track.
  Future<void> play(AudioModel audio) async {
    await _service.play(audio);
  }

  /// Pause playback.
  Future<void> pause() async {
    await _service.pause();
  }

  /// Resume playback.
  Future<void> resume() async {
    await _service.resume();
  }

  /// Toggle play/pause.
  Future<void> togglePlayPause() async {
    await _service.togglePlayPause();
  }

  /// Stop playback.
  Future<void> stop() async {
    await _service.stop();
  }

  /// Seek to a position.
  Future<void> seek(Duration position) async {
    await _service.seek(position);
  }

  /// Seek to a percentage (0.0 to 1.0).
  Future<void> seekToPercent(double percent) async {
    await _service.seekToPercent(percent);
  }

  /// Skip forward.
  Future<void> skipForward([
    Duration duration = const Duration(seconds: 10),
  ]) async {
    await _service.skipForward(duration);
  }

  /// Skip backward.
  Future<void> skipBackward([
    Duration duration = const Duration(seconds: 10),
  ]) async {
    await _service.skipBackward(duration);
  }

  /// Set playback speed.
  Future<void> setPlaybackSpeed(double speed) async {
    await _service.setPlaybackSpeed(speed);
  }

  /// Cycle through playback speeds.
  Future<void> cyclePlaybackSpeed() async {
    await _service.cyclePlaybackSpeed();
  }

  /// Set sleep timer.
  void setSleepTimer(SleepTimer timer) {
    _service.setSleepTimer(timer);
  }

  /// Toggle repeat.
  void toggleRepeat() {
    _service.toggleRepeat();
  }

  /// Set volume.
  Future<void> setVolume(double volume) async {
    await _service.setVolume(volume);
  }

  /// Toggle mute.
  Future<void> toggleMute() async {
    await _service.toggleMute();
  }
}

/// Audio player provider.
final audioPlayerProvider =
    StateNotifierProvider<AudioPlayerNotifier, AudioPlayerState>((ref) {
      return AudioPlayerNotifier();
    });

/// Current audio provider (convenience).
final currentAudioProvider = Provider<AudioModel?>((ref) {
  return ref.watch(audioPlayerProvider).currentAudio;
});

/// Is playing provider (convenience).
final isPlayingProvider = Provider<bool>((ref) {
  return ref.watch(audioPlayerProvider).isPlaying;
});

// ---------------------------------------------------------------------------
// Narration generation (gTTS)
// ---------------------------------------------------------------------------

/// State for TTS narration requests.
class AudioNarrationState {
  const AudioNarrationState({
    this.isGenerating = false,
    this.lastJob,
    this.errorMessage,
  });

  final bool isGenerating;
  final NarrationJobModel? lastJob;
  final String? errorMessage;

  AudioNarrationState copyWith({
    bool? isGenerating,
    NarrationJobModel? lastJob,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AudioNarrationState(
      isGenerating: isGenerating ?? this.isGenerating,
      lastJob: lastJob ?? this.lastJob,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Notifier for generating TTS narration and playing it.
class AudioNarrationNotifier extends StateNotifier<AudioNarrationState> {
  AudioNarrationNotifier({required this.onReady})
    : _apiService = AudioApiService.instance,
      super(const AudioNarrationState());

  final AudioApiService _apiService;

  /// Called with the generated job when narration completes successfully.
  final Future<void> Function(NarrationJobModel job) onReady;

  /// Generate narration for a story or artifact and auto-play the audio.
  Future<NarrationJobModel?> generateNarration({
    int? storyId,
    int? artifactId,
    String language = 'en',
  }) async {
    state = state.copyWith(isGenerating: true, clearError: true);
    try {
      final job = await _apiService.generateNarration(
        storyId: storyId,
        artifactId: artifactId,
        language: language,
      );
      state = state.copyWith(isGenerating: false, lastJob: job);

      if (job.isCompleted && job.audioUrl.isNotEmpty) {
        await onReady(job);
      }
      return job;
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        errorMessage: 'Failed to generate narration: $e',
      );
      return null;
    }
  }

  /// Clear the last generation error.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

/// Narration generation provider. Plays completed narrations automatically.
final audioNarrationProvider =
    StateNotifierProvider<AudioNarrationNotifier, AudioNarrationState>((ref) {
      return AudioNarrationNotifier(
        onReady: (job) async {
          await ref.read(audioPlayerProvider.notifier).play(job.toAudioModel());
        },
      );
    });
