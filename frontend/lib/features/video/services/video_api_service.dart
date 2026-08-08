import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/video_model.dart';

/// API service for interacting with the media backend.
///
/// Provides methods for:
///   - Creating video generation jobs
///   - Polling job status
///   - Cancelling jobs
///   - Listing user's jobs
class VideoApiService {
  VideoApiService._({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static final VideoApiService instance = VideoApiService._();

  /// Base path for media endpoints.
  static const _mediaPath = '/api/media';

  /// Create a video generation job.
  ///
  /// Returns the created [VideoModel] with initial status.
  Future<VideoModel> createVideoJob({
    required int storyId,
    required String prompt,
    int duration = 10,
    String aspectRatio = '16:9',
  }) async {
    final response = await _dio.post(
      '$_mediaPath/videos/',
      data: {
        'story_id': storyId,
        'prompt': prompt,
        'duration': duration,
        'aspect_ratio': aspectRatio,
      },
    );
    return VideoModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get the status of a video generation job.
  Future<VideoModel> getVideoStatus(int jobId) async {
    final response = await _dio.get('$_mediaPath/videos/$jobId/status/');
    return VideoModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Cancel a video generation job.
  Future<void> cancelVideoJob(int jobId) async {
    await _dio.post('$_mediaPath/videos/$jobId/cancel/');
  }

  /// List all video generation jobs for the current user.
  Future<List<VideoModel>> listVideoJobs({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '$_mediaPath/videos/',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
      },
    );
    final results = response.data['results'] as List<dynamic>;
    return results
        .map((json) => VideoModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get a specific video generation job detail.
  Future<VideoModel> getVideoDetail(int jobId) async {
    final response = await _dio.get('$_mediaPath/videos/$jobId/');
    return VideoModel.fromJson(response.data as Map<String, dynamic>);
  }
}
