import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/constants/app_constants.dart';
import 'package:griot_ai/core/widgets/griot_image.dart';

void main() {
  group('GriotImageResolver.classify', () {
    test('recognises bundled assets', () {
      expect(
        GriotImageResolver.classify('assets/imagery/stories/lions-bath.jpg'),
        GriotImageSource.asset,
      );
    });

    test('treats absolute and media-relative paths as network images', () {
      expect(
        GriotImageResolver.classify('https://example.com/a.jpg'),
        GriotImageSource.network,
      );
      expect(
        GriotImageResolver.classify('/media/artifacts/images/a.jpg'),
        GriotImageSource.network,
      );
      expect(
        GriotImageResolver.classify('artifacts/images/a.jpg'),
        GriotImageSource.network,
      );
    });

    test('reports nothing usable for blank input', () {
      expect(GriotImageResolver.classify(null), GriotImageSource.none);
      expect(GriotImageResolver.classify(''), GriotImageSource.none);
      expect(GriotImageResolver.classify('   '), GriotImageSource.none);
    });
  });

  group('AppConstants.resolveMediaUrl', () {
    const base = 'http://10.0.2.2:8000';

    test('leaves absolute urls alone', () {
      expect(
        AppConstants.resolveMediaUrl(
          'https://cdn.example.com/a.jpg',
          baseUrl: base,
        ),
        'https://cdn.example.com/a.jpg',
      );
    });

    test('prefixes root-relative paths with the host', () {
      expect(
        AppConstants.resolveMediaUrl('/media/a.jpg', baseUrl: base),
        'http://10.0.2.2:8000/media/a.jpg',
      );
    });

    test('prefixes media-relative paths with the media root', () {
      expect(
        AppConstants.resolveMediaUrl(
          'artifacts/images/a.jpg',
          baseUrl: base,
        ),
        'http://10.0.2.2:8000/media/artifacts/images/a.jpg',
      );
    });

    test('tolerates a trailing slash on the base url', () {
      expect(
        AppConstants.resolveMediaUrl('a.jpg', baseUrl: '$base/'),
        'http://10.0.2.2:8000/media/a.jpg',
      );
    });

    test('returns null for blank input', () {
      expect(AppConstants.resolveMediaUrl(null, baseUrl: base), isNull);
      expect(AppConstants.resolveMediaUrl('  ', baseUrl: base), isNull);
    });
  });
}
