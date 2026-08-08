import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../models/narration_job_model.dart';

/// API service for the backend TTS (gTTS) narration endpoints.
///
/// Provides methods for:
///   - Generating narration audio from a story or an artifact
///   - Listing the user's narration jobs
///   - Fetching a single job (status / audio URL)
class AudioApiService {
  AudioApiService._({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  final Dio _dio;

  static final AudioApiService instance = AudioApiService._();

  static const _mediaPath = '/api/media';

  /// Generate a narration for a story or an artifact.
  ///
  /// Pass exactly one of [storyId] (narrate that story) or [artifactId]
  /// (narrate the artifact's story / audio guide).
  ///
  /// Returns the completed job — [NarrationJobModel.audioUrl] holds the
  /// playable audio URL when [NarrationJobModel.isCompleted] is true.
  Future<NarrationJobModel> generateNarration({
    int? storyId,
    int? artifactId,
    String language = 'en',
    double speed = 1.0,
  }) async {
    // gTTS generation is synchronous on the backend and makes many
    // sequential chunk requests, so allow a generous receive timeout.
    final response = await _dio.post(
      '$_mediaPath/audio/',
      data: {
        'story_id': ?storyId,
        'artifact_id': ?artifactId,
        'language': language,
        'speed': speed,
      },
      options: Options(receiveTimeout: const Duration(minutes: 3)),
    );
    return NarrationJobModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// List narration jobs for the current user.
  Future<List<NarrationJobModel>> listNarrations({int page = 1}) async {
    final response = await _dio.get(
      '$_mediaPath/audio/',
      queryParameters: {'page': page},
    );
    final results = response.data['results'] as List<dynamic>? ?? [];
    return results
        .map((json) => NarrationJobModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Fetch a single narration job (e.g., to check status / audio URL).
  Future<NarrationJobModel> getNarration(int jobId) async {
    final response = await _dio.get('$_mediaPath/audio/$jobId/');
    return NarrationJobModel.fromJson(response.data as Map<String, dynamic>);
  }
}
