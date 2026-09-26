import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/features/video/models/video_model.dart';
import 'package:griot_ai/features/video/providers/video_provider.dart';

/// The media API serialises a job with `story` (the FK id) and `video_url`.
/// These tests pin that contract: reading the wrong key names silently yields
/// storyId 0 and an empty url, which makes `isReady` permanently false and the
/// video unplayable no matter what the server returned.
void main() {
  group('VideoModel.fromJson', () {
    test('should read story id from the `story` key the API sends', () {
      final model = VideoModel.fromJson(const {
        'id': 7,
        'story': 42,
        'status': 'pending',
      });

      expect(model.id, 7);
      expect(model.storyId, 42);
    });

    test('should read the playable url from the `video_url` key', () {
      final model = VideoModel.fromJson(const {
        'id': 7,
        'story': 42,
        'video_url': 'https://cdn.example.com/clip.mp4',
        'status': 'completed',
      });

      expect(model.url, 'https://cdn.example.com/clip.mp4');
    });

    test('should be ready only when completed with a non-empty url', () {
      final completed = VideoModel.fromJson(const {
        'id': 7,
        'story': 42,
        'video_url': 'https://cdn.example.com/clip.mp4',
        'status': 'completed',
      });
      expect(completed.isReady, isTrue);

      final completedButNoUrl = VideoModel.fromJson(const {
        'id': 8,
        'story': 42,
        'status': 'completed',
      });
      expect(completedButNoUrl.isReady, isFalse);

      final processing = VideoModel.fromJson(const {
        'id': 9,
        'story': 42,
        'status': 'processing',
      });
      expect(processing.isReady, isFalse);
      expect(processing.isProcessing, isTrue);
    });

    test('should still parse the legacy `story_id` / `url` keys', () {
      // Payloads written by an older build (offline queue, cached JSON) use
      // the old names; they must keep working rather than degrade silently.
      final model = VideoModel.fromJson(const {
        'id': 3,
        'story_id': 11,
        'url': 'https://cdn.example.com/legacy.mp4',
        'status': 'completed',
      });

      expect(model.storyId, 11);
      expect(model.url, 'https://cdn.example.com/legacy.mp4');
      expect(model.isReady, isTrue);
    });

    test('should read progress and the failure reason', () {
      final model = VideoModel.fromJson(const {
        'id': 5,
        'story': 42,
        'status': 'failed',
        'progress_percent': 45,
        'error_message': 'Video generation could not be started: quota exceeded',
      });

      expect(model.progressPercent, 45);
      expect(model.hasFailed, isTrue);
      expect(
        model.errorMessage,
        'Video generation could not be started: quota exceeded',
      );
    });

    test('should survive a payload with none of the known keys', () {
      final model = VideoModel.fromJson(const {});

      expect(model.id, 0);
      expect(model.storyId, 0);
      expect(model.url, isEmpty);
      expect(model.status, VideoStatus.pending);
    });
  });

  group('VideoGenerationState.jobForStory', () {
    test('should match a job to its story using the parsed story id', () {
      final state = VideoGenerationState(
        jobs: [
          VideoModel.fromJson(const {
            'id': 1,
            'story': 100,
            'status': 'processing',
          }),
          VideoModel.fromJson(const {
            'id': 2,
            'story': 200,
            'status': 'completed',
            'video_url': 'https://cdn.example.com/b.mp4',
          }),
        ],
      );

      expect(state.jobForStory(200)?.id, 2);
      expect(state.jobForStory(100)?.id, 1);
      expect(state.jobForStory(999), isNull);
    });
  });
}
