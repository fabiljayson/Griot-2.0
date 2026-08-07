import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/audio_model.dart';

/// Service for managing audio playback with just_audio.
///
/// Features:
/// - Persistent playback across screens
/// - Variable playback speed (0.75x – 2.0x)
/// - Sleep timer functionality
/// - Background playback support
class AudioPlayerService {
  AudioPlayerService._() {
    _initListeners();
  }

  static final AudioPlayerService instance = AudioPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  
  // State
  AudioModel? _currentAudio;
  SleepTimer _sleepTimer = SleepTimer.off;
  Timer? _sleepTimerTimer;
  
  // Stream controllers
  final _stateController = StreamController<AudioPlayerState>.broadcast();
  Stream<AudioPlayerState> get stateStream => _stateController.stream;
  
  AudioPlayerState _state = const AudioPlayerState();
  AudioPlayerState get currentState => _state;

  void _initListeners() {
    // Listen to player position
    _player.positionStream.listen((position) {
      _updateState(position: position);
    });

    // Listen to player duration
    _player.durationStream.listen((duration) {
      _updateState(duration: duration ?? Duration.zero);
    });

    // Listen to player state
    _player.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      switch (processingState) {
        case ProcessingState.idle:
          _updateState(isPlaying: false, isBuffering: false);
          break;
        case ProcessingState.loading:
          _updateState(isPlaying: false, isBuffering: true);
          break;
        case ProcessingState.buffering:
          _updateState(isPlaying: false, isBuffering: true);
          break;
        case ProcessingState.ready:
          _updateState(isPlaying: isPlaying, isBuffering: false);
          break;
        case ProcessingState.completed:
          _handlePlaybackComplete();
          break;
      }
    });
  }

  void _updateState({
    AudioModel? currentAudio,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? playbackSpeed,
    SleepTimer? sleepTimer,
    bool? isBuffering,
    String? errorMessage,
    bool clearAudio = false,
    bool clearError = false,
  }) {
    _state = _state.copyWith(
      currentAudio: currentAudio,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
      playbackSpeed: playbackSpeed,
      sleepTimer: sleepTimer,
      isBuffering: isBuffering,
      errorMessage: errorMessage,
      clearAudio: clearAudio,
      clearError: clearError,
    );
    _stateController.add(_state);
  }

  void _handlePlaybackComplete() {
    _updateState(isPlaying: false, position: _state.duration);
    // Could auto-play next track or stop
  }

  // --- Playback Controls ---

  /// Load and play an audio track.
  Future<void> play(AudioModel audio) async {
    try {
      _currentAudio = audio;
      _updateState(currentAudio: audio, isBuffering: true);

      // Set playback speed
      await _player.setSpeed(audio.playbackSpeed);

      // Load the audio source
      if (audio.url.isNotEmpty) {
        await _player.setUrl(audio.url);
      } else {
        _updateState(errorMessage: 'No audio URL provided', clearAudio: true);
        return;
      }

      // Start playback
      await _player.play();
      _updateState(isBuffering: false);
    } catch (e) {
      _updateState(
        errorMessage: 'Failed to play audio: $e',
        clearAudio: true,
      );
    }
  }

  /// Pause playback.
  Future<void> pause() async {
    try {
      await _player.pause();
      _updateState(isPlaying: false);
    } catch (e) {
      _updateState(errorMessage: 'Failed to pause: $e');
    }
  }

  /// Resume playback.
  Future<void> resume() async {
    try {
      await _player.play();
      _updateState(isPlaying: true);
    } catch (e) {
      _updateState(errorMessage: 'Failed to resume: $e');
    }
  }

  /// Toggle play/pause.
  Future<void> togglePlayPause() async {
    if (_state.isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  /// Stop playback.
  Future<void> stop() async {
    try {
      await _player.stop();
      _cancelSleepTimer();
      _updateState(
        isPlaying: false,
        position: Duration.zero,
        clearAudio: true,
      );
    } catch (e) {
      _updateState(errorMessage: 'Failed to stop: $e');
    }
  }

  /// Seek to a position.
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
      _updateState(position: position);
    } catch (e) {
      _updateState(errorMessage: 'Failed to seek: $e');
    }
  }

  /// Seek to a percentage (0.0 to 1.0).
  Future<void> seekToPercent(double percent) async {
    final position = Duration(
      milliseconds: (_state.duration.inMilliseconds * percent).round(),
    );
    await seek(position);
  }

  /// Skip forward by [duration] (default 10 seconds).
  Future<void> skipForward([Duration duration = const Duration(seconds: 10)]) async {
    final newPosition = _state.position + duration;
    final clampedPosition = newPosition > _state.duration ? _state.duration : newPosition;
    await seek(clampedPosition);
  }

  /// Skip backward by [duration] (default 10 seconds).
  Future<void> skipBackward([Duration duration = const Duration(seconds: 10)]) async {
    final newPosition = _state.position - duration;
    final clampedPosition = newPosition < Duration.zero ? Duration.zero : newPosition;
    await seek(clampedPosition);
  }

  // --- Playback Speed ---

  /// Set playback speed.
  Future<void> setPlaybackSpeed(double speed) async {
    try {
      await _player.setSpeed(speed);
      _updateState(playbackSpeed: speed);
    } catch (e) {
      _updateState(errorMessage: 'Failed to set speed: $e');
    }
  }

  /// Cycle through playback speeds.
  Future<void> cyclePlaybackSpeed() async {
    final speeds = PlaybackSpeed.values;
    final currentIndex = speeds.indexWhere((s) => s.value == _state.playbackSpeed);
    final nextIndex = (currentIndex + 1) % speeds.length;
    await setPlaybackSpeed(speeds[nextIndex].value);
  }

  // --- Sleep Timer ---

  /// Set sleep timer.
  void setSleepTimer(SleepTimer timer) {
    _cancelSleepTimer();
    _updateState(sleepTimer: timer);

    if (timer.minutes > 0) {
      _sleepTimerTimer = Timer(Duration(minutes: timer.minutes), () {
        pause();
        _updateState(sleepTimer: SleepTimer.off);
      });
    }
  }

  void _cancelSleepTimer() {
    _sleepTimerTimer?.cancel();
    _sleepTimerTimer = null;
  }

  // --- Volume ---

  /// Set volume (0.0 to 1.0).
  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume);
    } catch (e) {
      _updateState(errorMessage: 'Failed to set volume: $e');
    }
  }

  /// Mute/unmute.
  Future<void> toggleMute() async {
    try {
      if (_player.volume > 0) {
        await _player.setVolume(0);
      } else {
        await _player.setVolume(1);
      }
    } catch (e) {
      _updateState(errorMessage: 'Failed to toggle mute: $e');
    }
  }

  // --- Cleanup ---

  /// Dispose of the player.
  Future<void> dispose() async {
    _cancelSleepTimer();
    await _player.dispose();
    await _stateController.close();
  }
}