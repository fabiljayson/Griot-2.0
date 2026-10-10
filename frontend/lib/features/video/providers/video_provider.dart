import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_error.dart';
import '../../auth/providers/auth_provider.dart';
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
    this.premiumRequired = false,
  });

  final List<VideoModel> jobs;
  final bool isLoading;
  final bool isCreating;
  final String? errorMessage;

  /// The backend answered 402 (`premium_required`): the story is fine, the
  /// account is simply not entitled. Surfaced separately so the sheet can
  /// offer the paywall instead of a generic failure.
  final bool premiumRequired;

  VideoGenerationState copyWith({
    List<VideoModel>? jobs,
    bool? isLoading,
    bool? isCreating,
    String? errorMessage,
    bool? premiumRequired,
    bool clearError = false,
  }) {
    return VideoGenerationState(
      jobs: jobs ?? this.jobs,
      isLoading: isLoading ?? this.isLoading,
      isCreating: isCreating ?? this.isCreating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      // A fresh attempt starts from "not a paywall problem"; an explicit
      // argument (the 402 handler) wins over the reset.
      premiumRequired:
          premiumRequired ?? (clearError ? false : this.premiumRequired),
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
  VideoGenerationNotifier({VideoApiService? apiService})
    : _apiService = apiService ?? VideoApiService(),
      _poller = VideoStatusPoller(apiService: apiService),
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
        errorMessage: 'Failed to load video jobs: ${_describe(e)}',
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

      // The backend answers 201 even when Luma refused the job, so a failed
      // job is a real outcome here rather than an exception. Report it as an
      // error instead of a cheerful "we'll notify you" message.
      if (job.hasFailed) {
        state = state.copyWith(
          jobs: [job, ...state.jobs],
          isCreating: false,
          errorMessage:
              job.errorMessage ?? 'Video generation could not be started.',
        );
        return null;
      }

      // Add to local list and start polling.
      state = state.copyWith(jobs: [job, ...state.jobs], isCreating: false);

      // Start background polling for this job.
      _startPollingForJob(job);

      return job;
    } catch (e) {
      // 402 is the server's paywall: `code: premium_required` in the body.
      // The backend is the authority — this only decides how the sheet
      // explains the refusal.
      final isPremiumRefusal =
          e is DioException && e.response?.statusCode == 402;
      final detail = isPremiumRefusal
          ? ((e.response?.data as Map<String, dynamic>?)?['detail']
                as String?)
          : null;
      state = state.copyWith(
        isCreating: false,
        premiumRequired: isPremiumRefusal,
        errorMessage: isPremiumRefusal
            ? (detail ?? 'AI video generation is a premium feature.')
            : 'Failed to create video: ${_describe(e)}',
      );
      return null;
    }
  }

  /// Turn a transport failure into a message worth showing a user.
  ///
  /// Raw `DioException.toString()` dumps the request options and is both
  /// unreadable and noise-prone, so route it through the shared mapper.
  String _describe(Object e) {
    if (e is DioException) return AppErrorMapper.fromDio(e).message;
    return e.toString();
  }

  /// Cancel a video generation job.
  Future<void> cancelJob(int jobId) async {
    try {
      await _apiService.cancelVideoJob(jobId);
      _poller.stopPolling(jobId);

      // Update local state.
      final updatedJobs = state.jobs.map((j) {
        if (j.id == jobId) {
          return j.copyWith(
            status: VideoStatus.failed,
            errorMessage: 'Cancelled by user',
          );
        }
        return j;
      }).toList();

      state = state.copyWith(jobs: updatedJobs);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to cancel: ${_describe(e)}');
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
      state = state.copyWith(errorMessage: 'Failed to refresh: ${_describe(e)}');
    }
  }

  void _startPollingForJob(VideoModel job) {
    _poller
        .startPolling(job.id)
        .listen(
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
///
/// Wires the auth-aware client so the JWT is attached — the media endpoints
/// reject anonymous callers with 401.
final videoGenerationProvider =
    StateNotifierProvider<VideoGenerationNotifier, VideoGenerationState>((ref) {
      final apiClient = ref.watch(authenticatedApiClientProvider);
      return VideoGenerationNotifier(apiService: VideoApiService(dio: apiClient.dio));
    });

/// Video for a specific story.
final videoForStoryProvider = Provider.family<VideoModel?, int>((ref, storyId) {
  final state = ref.watch(videoGenerationProvider);
  return state.jobForStory(storyId);
});
