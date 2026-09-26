import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../../core/constants/app_constants.dart';
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

    // Errors raised by the player itself (decoder failures, a source that
    // dies mid-stream) never travel through `play()`, so without this the
    // UI would keep showing a paused player with no explanation.
    _player.errorStream.listen((playerError) {
      _updateState(
        isPlaying: false,
        isBuffering: false,
        errorMessage: _describePlaybackError(playerError),
      );
    });
  }

  void _updateState({
    AudioModel? currentAudio,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? playbackSpeed,
    SleepTimer? sleepTimer,
    bool? isRepeatEnabled,
    double? volume,
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
      isRepeatEnabled: isRepeatEnabled,
      volume: volume,
      isBuffering: isBuffering,
      errorMessage: errorMessage,
      clearAudio: clearAudio,
      clearError: clearError,
    );
    _stateController.add(_state);
  }

  void _handlePlaybackComplete() {
    if (_state.isRepeatEnabled) {
      // Repeat mode: replay the current track from the start.
      _replay();
    } else {
      _updateState(isPlaying: false, position: _state.duration);
    }
  }

  Future<void> _replay() async {
    try {
      await _player.seek(Duration.zero);
      await _player.play();
      _updateState(isPlaying: true, position: Duration.zero);
    } catch (e) {
      _updateState(errorMessage: 'Failed to repeat playback: $e');
    }
  }

  // --- Playback Controls ---

  /// Load and play an audio track.
  Future<void> play(AudioModel audio) async {
    try {
      _updateState(currentAudio: audio, isBuffering: true, clearError: true);

      // Set playback speed
      await _player.setSpeed(audio.playbackSpeed);

      // Load the audio source
      if (audio.url.isEmpty) {
        _updateState(
          isBuffering: false,
          errorMessage: 'No audio URL provided',
        );
        return;
      }

      // Resolve relative URLs (e.g. a bare '/media/audio/x.mp3') against
      // the effective backend base, the same way [GriotImage] does.
      final url = AppConstants.resolveMediaUrl(
            audio.url,
            baseUrl: AppConstants.effectiveBaseUrl,
          ) ??
          audio.url;
      await _player.setUrl(url);

      // Start playback
      await _player.play();
      _updateState(isBuffering: false);
    } catch (e) {
      // Keep `currentAudio` so the sheet still shows the track and can offer
      // a retry. Clearing it made a failed load look like the audio had
      // simply never existed.
      _updateState(isBuffering: false, errorMessage: _describePlaybackError(e));
    }
  }

  /// Turn a playback failure into something a user can act on.
  ///
  /// `PlayerException.toString()` is just "($code) $message", where `code` is
  /// a platform-specific integer (`NSError.code`, `ExoPlaybackException.type`
  /// or `MediaError.code`) and so is not comparable across platforms. Match on
  /// the message text for the two cases worth distinguishing and otherwise
  /// stay generic rather than inventing a code we cannot rely on.
  String _describePlaybackError(Object e) {
    if (e is PlayerException) {
      final message = (e.message ?? '').toLowerCase();
      const networkHints = [
        'network',
        'unable to connect',
        'connection',
        'timed out',
        'timeout',
        'host',
        'resolve',
      ];
      const decodeHints = [
        'unsupported',
        'decode',
        'corrupt',
        'format',
        'codec',
        'no such',
      ];

      if (networkHints.any(message.contains)) {
        return 'Could not reach the audio. Please check your connection.';
      }
      if (decodeHints.any(message.contains)) {
        return 'This audio file could not be played.';
      }
    }
    return 'Audio playback failed. Please try again.';
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
      _updateState(isPlaying: false, position: Duration.zero, clearAudio: true);
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
  Future<void> skipForward([
    Duration duration = const Duration(seconds: 10),
  ]) async {
    final newPosition = _state.position + duration;
    final clampedPosition = newPosition > _state.duration
        ? _state.duration
        : newPosition;
    await seek(clampedPosition);
  }

  /// Skip backward by [duration] (default 10 seconds).
  Future<void> skipBackward([
    Duration duration = const Duration(seconds: 10),
  ]) async {
    final newPosition = _state.position - duration;
    final clampedPosition = newPosition < Duration.zero
        ? Duration.zero
        : newPosition;
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
    final currentIndex = speeds.indexWhere(
      (s) => s.value == _state.playbackSpeed,
    );
    final nextIndex = (currentIndex + 1) % speeds.length;
    await setPlaybackSpeed(speeds[nextIndex].value);
  }

  // --- Repeat ---

  /// Toggle repeat (replays the current track when it completes).
  void toggleRepeat() {
    _updateState(isRepeatEnabled: !_state.isRepeatEnabled);
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
      _updateState(volume: volume);
    } catch (e) {
      _updateState(errorMessage: 'Failed to set volume: $e');
    }
  }

  /// Mute/unmute.
  Future<void> toggleMute() async {
    try {
      if (_player.volume > 0) {
        await _player.setVolume(0);
        _updateState(volume: 0);
      } else {
        await _player.setVolume(1);
        _updateState(volume: 1);
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
