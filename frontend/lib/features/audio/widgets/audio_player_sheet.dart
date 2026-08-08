import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../models/audio_model.dart';
import '../providers/audio_provider.dart';

/// Persistent sticky audio player sheet.
///
/// Displays at the bottom of the screen when audio is playing.
/// Features:
/// - Play/pause control
/// - Progress bar with seek
/// - Playback speed control
/// - Sleep timer
/// - Expandable to full player view
class AudioPlayerSheet extends ConsumerWidget {
  const AudioPlayerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(audioPlayerProvider);

    if (!audioState.hasAudio) {
      return const SizedBox.shrink();
    }

    return _MiniPlayer(audioState: audioState);
  }
}

/// Mini player displayed at the bottom.
class _MiniPlayer extends ConsumerWidget {
  const _MiniPlayer({required this.audioState});

  final AudioPlayerState audioState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _showFullPlayer(context),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Progress bar
            LinearProgressIndicator(
              value: audioState.progress,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.terracotta,
              ),
              minHeight: 2,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Album art / story icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.terracotta.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text('🎵', style: TextStyle(fontSize: 24)),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title and narrator
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            audioState.currentAudio?.storyTitle ?? '',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            audioState.currentAudio?.narrator.isNotEmpty == true
                                ? audioState.currentAudio!.narrator
                                : 'Narration',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Time
                    Text(
                      '${audioState.formattedPosition} / ${audioState.formattedDuration}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Skip backward
                    IconButton(
                      icon: const Icon(Icons.replay_10, size: 24),
                      onPressed: () =>
                          ref.read(audioPlayerProvider.notifier).skipBackward(),
                      tooltip: 'Rewind 10s',
                    ),

                    // Play/Pause
                    IconButton(
                      icon: Icon(
                        audioState.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 40,
                        color: AppColors.terracotta,
                      ),
                      onPressed: () => ref
                          .read(audioPlayerProvider.notifier)
                          .togglePlayPause(),
                    ),

                    // Skip forward
                    IconButton(
                      icon: const Icon(Icons.forward_10, size: 24),
                      onPressed: () =>
                          ref.read(audioPlayerProvider.notifier).skipForward(),
                      tooltip: 'Forward 10s',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullPlayer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _FullPlayerSheet(),
    );
  }
}

/// Full-screen player sheet.
class _FullPlayerSheet extends ConsumerWidget {
  const _FullPlayerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final audioState = ref.watch(audioPlayerProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Album art
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: AppColors.terracotta.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.terracotta.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('🎵', style: TextStyle(fontSize: 80)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    audioState.currentAudio?.storyTitle ?? '',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Narrator
                  Text(
                    audioState.currentAudio?.narrator.isNotEmpty == true
                        ? 'Narrated by ${audioState.currentAudio!.narrator}'
                        : 'Story Narration',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Progress bar with time
                  Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.terracotta,
                          inactiveTrackColor:
                              theme.colorScheme.surfaceContainerHighest,
                          thumbColor: AppColors.terracotta,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: audioState.progress,
                          onChanged: (value) {
                            ref
                                .read(audioPlayerProvider.notifier)
                                .seekToPercent(value);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              audioState.formattedPosition,
                              style: theme.textTheme.labelMedium,
                            ),
                            Text(
                              audioState.formattedDuration,
                              style: theme.textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Main controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Skip backward
                      IconButton(
                        icon: const Icon(Icons.replay_10, size: 32),
                        onPressed: () => ref
                            .read(audioPlayerProvider.notifier)
                            .skipBackward(),
                      ),
                      const SizedBox(width: 16),

                      // Play/Pause
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.terracotta,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.terracotta.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            audioState.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            size: 40,
                            color: Colors.white,
                          ),
                          onPressed: () => ref
                              .read(audioPlayerProvider.notifier)
                              .togglePlayPause(),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Skip forward
                      IconButton(
                        icon: const Icon(Icons.forward_10, size: 32),
                        onPressed: () => ref
                            .read(audioPlayerProvider.notifier)
                            .skipForward(),
                      ),
                      const SizedBox(width: 16),

                      // Repeat
                      IconButton(
                        icon: const Icon(Icons.repeat, size: 24),
                        onPressed: () => ref
                            .read(audioPlayerProvider.notifier)
                            .toggleRepeat(),
                        color: audioState.isRepeatEnabled
                            ? AppColors.terracotta
                            : theme.colorScheme.onSurfaceVariant,
                        tooltip: 'Repeat',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Speed and Sleep Timer controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Playback speed
                      _ControlButton(
                        icon: Icons.speed,
                        label: '${audioState.playbackSpeed}x',
                        onTap: () => _showSpeedPicker(context, ref),
                      ),

                      // Sleep timer
                      _ControlButton(
                        icon: Icons.bedtime_outlined,
                        label: audioState.sleepTimer.label,
                        onTap: () => _showSleepTimerPicker(context, ref),
                      ),

                      // Volume
                      _ControlButton(
                        icon: Icons.volume_up,
                        label: 'Volume',
                        onTap: () => _showVolumePicker(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSpeedPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Playback Speed',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...PlaybackSpeed.values.map((speed) {
                return ListTile(
                  title: Text(speed.label),
                  trailing:
                      ref.read(audioPlayerProvider).playbackSpeed == speed.value
                      ? const Icon(Icons.check, color: AppColors.terracotta)
                      : null,
                  onTap: () {
                    ref
                        .read(audioPlayerProvider.notifier)
                        .setPlaybackSpeed(speed.value);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showSleepTimerPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Sleep Timer',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...SleepTimer.values.map((timer) {
                return ListTile(
                  title: Text(timer.label),
                  trailing: ref.read(audioPlayerProvider).sleepTimer == timer
                      ? const Icon(Icons.check, color: AppColors.terracotta)
                      : null,
                  onTap: () {
                    ref.read(audioPlayerProvider.notifier).setSleepTimer(timer);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showVolumePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Volume',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final volume = ref.watch(audioPlayerProvider).volume;
                    return Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            volume == 0 ? Icons.volume_off : Icons.volume_up,
                            color: AppColors.terracotta,
                          ),
                          tooltip: volume == 0 ? 'Unmute' : 'Mute',
                          onPressed: () => ref
                              .read(audioPlayerProvider.notifier)
                              .toggleMute(),
                        ),
                        Expanded(
                          child: Slider(
                            value: volume,
                            activeColor: AppColors.terracotta,
                            inactiveColor:
                                theme.colorScheme.surfaceContainerHighest,
                            onChanged: (value) => ref
                                .read(audioPlayerProvider.notifier)
                                .setVolume(value),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${(volume * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Control button used in the full player.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
