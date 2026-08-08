import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_model.dart';
import '../services/video_api_service.dart';
import '../services/video_status_poller.dart';

/// State for video generation requests.
class VideoGenerationState {
  const VideoGenerationState({
    this.jobs = const [],
    this.isLoading = false,
    this.isCreating = false,
    this.errorMessage,
  });

  final List<VideoModel> jobs;
  final bool isLoading;
  final bool isCreating;
  final String? errorMessage;

  VideoGenerationState copyWith({
    List<VideoModel>? jobs,
    bool? isLoading,
    bool? isCreating,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VideoGenerationState(
      jobs: jobs ?? this.jobs,
      isLoading: isLoading ?? this.isLoading,
      isCreating: isCreating ?? this.isCreating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// Get the most recent job for a given story.
  VideoModel? jobForStory(int storyId) {
    try {
      return jobs.firstWhere((j) => j.storyId == storyId);
    } catch (_) {
      return null;
    }
  }
}

/// Notifier for managing video generation jobs.
class VideoGenerationNotifier extends StateNotifier<VideoGenerationState> {
  VideoGenerationNotifier()
      : _apiService = VideoApiService.instance,
        _poller = VideoStatusPoller.instance,
        super(const VideoGenerationState());

  final VideoApiService _apiService;
  final VideoStatusPoller _poller;

  /// Load all video jobs for the current user.
  Future<void> loadJobs() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final jobs = await _apiService.listVideoJobs();
      state = state.copyWith(jobs: jobs, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load video jobs: $e',
      );
    }
  }

  /// Request a new video generation for a story.
  Future<VideoModel?> createVideo({
    required int storyId,
    required String prompt,
    int duration = 10,
    String aspectRatio = '16:9',
  }) async {
    state = state.copyWith(isCreating: true, clearError: true);
    try {
      final job = await _apiService.createVideoJob(
        storyId: storyId,
        prompt: prompt,
        duration: duration,
        aspectRatio: aspectRatio,
      );

      // Add to local list and start polling.
      state = state.copyWith(
        jobs: [job, ...state.jobs],
        isCreating: false,
      );

      // Start background polling for this job.
      _startPollingForJob(job);

      return job;
    } catch (e) {
      state = state.copyWith(
        isCreating: false,
        errorMessage: 'Failed to create video: $e',
      );
      return null;
    }
  }

  /// Cancel a video generation job.
  Future<void> cancelJob(int jobId) async {
    try {
      await _apiService.cancelVideoJob(jobId);
      _poller.stopPolling(jobId);

      // Update local state.
      final updatedJobs = state.jobs.map((j) {
        if (j.id == jobId) {
          return j.copyWith(status: VideoStatus.failed, errorMessage: 'Cancelled by user');
        }
        return j;
      }).toList();

      state = state.copyWith(jobs: updatedJobs);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to cancel: $e');
    }
  }

  /// Refresh status of a specific job.
  Future<void> refreshJob(int jobId) async {
    try {
      final updated = await _apiService.getVideoStatus(jobId);
      _updateJobInState(updated);

      if (updated.isProcessing) {
        _startPollingForJob(updated);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to refresh: $e');
    }
  }

  void _startPollingForJob(VideoModel job) {
    _poller.startPolling(job.id).listen(
      (updated) {
        _updateJobInState(updated);
      },
      onError: (e) {
        // Polling error — the poller will retry internally.
      },
    );
  }

  void _updateJobInState(VideoModel updated) {
    final updatedJobs = state.jobs.map((j) {
      if (j.id == updated.id) return updated;
      return j;
    }).toList();
    state = state.copyWith(jobs: updatedJobs);
  }

  @override
  void dispose() {
    _poller.stopAll();
    super.dispose();
  }
}

/// Main video generation provider.
final videoGenerationProvider =
    StateNotifierProvider<VideoGenerationNotifier, VideoGenerationState>((ref) {
  return VideoGenerationNotifier();
});

/// Video for a specific story.
final videoForStoryProvider = Provider.family<VideoModel?, int>((ref, storyId) {
  final state = ref.watch(videoGenerationProvider);
  return state.jobForStory(storyId);
});
