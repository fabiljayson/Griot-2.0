import 'dart:async';

import '../models/video_model.dart';
import 'video_api_service.dart';

/// Polls the backend for video generation status updates.
///
/// Uses exponential backoff:
///   - First poll: 3 seconds
///   - Then: 5s, 8s, 12s, 18s, 25s (capped)
///   - Stops when job completes, fails, or is cancelled.
class VideoStatusPoller {
  VideoStatusPoller._({
    VideoApiService? apiService,
  }) : _apiService = apiService ?? VideoApiService.instance;

  final VideoApiService _apiService;

  static final VideoStatusPoller instance = VideoStatusPoller._();

  /// Active pollers keyed by job ID.
  final Map<int, Timer> _activePollers = {};

  /// Stream controllers for status updates per job.
  final Map<int, StreamController<VideoModel>> _statusControllers = {};

  /// Poll intervals in seconds (exponential backoff).
  static const List<int> _pollIntervals = [3, 5, 8, 12, 18, 25];

  /// Start polling for a video generation job.
  ///
  /// Returns a stream that emits [VideoModel] updates until the job
  /// reaches a terminal state (completed, failed, cancelled).
  Stream<VideoModel> startPolling(int jobId) {
    // Cancel existing poller for this job if any.
    stopPolling(jobId);

    final controller = StreamController<VideoModel>.broadcast();
    _statusControllers[jobId] = controller;

    _pollOnce(jobId, controller, 0);

    return controller.stream;
  }

  void _pollOnce(int jobId, StreamController<VideoModel> controller, int attempt) {
    if (controller.isClosed) return;

    final interval = _pollIntervals[
      attempt.clamp(0, _pollIntervals.length - 1)
    ];

    _activePollers[jobId] = Timer(Duration(seconds: interval), () async {
      if (controller.isClosed) return;

      try {
        final updated = await _apiService.getVideoStatus(jobId);
        if (!controller.isClosed) {
          controller.add(updated);
        }

        // Continue polling if still processing.
        if (updated.isProcessing && !controller.isClosed) {
          _pollOnce(jobId, controller, attempt + 1);
        } else {
          // Terminal state — close.
          if (!controller.isClosed) {
            await controller.close();
          }
          _cleanup(jobId);
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          // Retry with backoff on error.
          _pollOnce(jobId, controller, attempt + 1);
        }
      }
    });
  }

  /// Stop polling for a specific job.
  void stopPolling(int jobId) {
    _activePollers[jobId]?.cancel();
    _activePollers.remove(jobId);
    _cleanup(jobId);
  }

  /// Stop all active pollers.
  void stopAll() {
    for (final timer in _activePollers.values) {
      timer.cancel();
    }
    _activePollers.clear();
    for (final controller in _statusControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _statusControllers.clear();
  }

  void _cleanup(int jobId) {
    _activePollers.remove(jobId);
    _statusControllers.remove(jobId);
  }

  /// Whether a job is currently being polled.
  bool isPolling(int jobId) => _activePollers.containsKey(jobId);
}
