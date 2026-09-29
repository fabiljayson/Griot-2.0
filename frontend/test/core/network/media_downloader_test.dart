import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/core/network/media_downloader.dart';

void main() {
  group('MediaDownloader.isAllowed', () {
    // The URL handed to the downloader comes from an API response field, so
    // whoever can write a story's media path chooses what the app fetches.
    // The policy is expressed purely so it can be tested without a socket.

    test('accepts an https URL on the configured API host', () {
      expect(
        MediaDownloader.isAllowed(
          'https://api.example.org/media/stories/x.mp3',
          apiBaseUrl: 'https://api.example.org',
          debug: false,
        ),
        isTrue,
      );
    });

    test('rejects a cleartext URL in release', () {
      // A release build must not fetch over http: the response can be rewritten
      // in transit and the cached file is then trusted content.
      expect(
        MediaDownloader.isAllowed(
          'http://api.example.org/media/stories/x.mp3',
          apiBaseUrl: 'https://api.example.org',
          debug: false,
        ),
        isFalse,
      );
    });

    test('allows cleartext in debug so local development still works', () {
      expect(
        MediaDownloader.isAllowed(
          'http://10.0.2.2:8000/media/stories/x.mp3',
          apiBaseUrl: 'http://10.0.2.2:8000',
          debug: true,
        ),
        isTrue,
      );
    });

    test('rejects a third-party host even over https', () {
      // This is the rule that stops a media field from turning the app into a
      // fetcher for arbitrary third-party URLs.
      expect(
        MediaDownloader.isAllowed(
          'https://evil.example.com/payload.mp3',
          apiBaseUrl: 'https://api.example.org',
          debug: false,
        ),
        isFalse,
      );
    });

    test('rejects a look-alike host', () {
      expect(
        MediaDownloader.isAllowed(
          'https://api.example.org.evil.com/x.mp3',
          apiBaseUrl: 'https://api.example.org',
          debug: false,
        ),
        isFalse,
      );
      expect(
        MediaDownloader.isAllowed(
          'https://evil.com/?x=api.example.org',
          apiBaseUrl: 'https://api.example.org',
          debug: false,
        ),
        isFalse,
      );
    });

    test('rejects non-http schemes', () {
      for (final url in [
        'file:///etc/passwd',
        'ftp://api.example.org/x.mp3',
        'griot-ai://story/x',
      ]) {
        expect(
          MediaDownloader.isAllowed(
            url,
            apiBaseUrl: 'https://api.example.org',
            debug: true,
          ),
          isFalse,
          reason: 'expected "$url" to be rejected',
        );
      }
    });

    test('rejects an unparseable URL', () {
      expect(
        MediaDownloader.isAllowed(
          'not a url',
          apiBaseUrl: 'https://api.example.org',
          debug: false,
        ),
        isFalse,
      );
    });
  });

  group('MediaDownloader.cacheFileName', () {
    // The caches used `audio_${url.hashCode}.mp3`. Dart's String.hashCode is
    // not stable across runs and collides routinely, so two different stories
    // could share one filename: the second download overwrote the first and the
    // player served the wrong audio.

    test('is deterministic for the same URL', () {
      final a = MediaDownloader.cacheFileName(
        'https://api.example.org/media/x.mp3',
        extension: 'mp3',
      );
      final b = MediaDownloader.cacheFileName(
        'https://api.example.org/media/x.mp3',
        extension: 'mp3',
      );
      expect(a, b);
    });

    test('differs for different URLs', () {
      final a = MediaDownloader.cacheFileName(
        'https://api.example.org/media/one.mp3',
        extension: 'mp3',
      );
      final b = MediaDownloader.cacheFileName(
        'https://api.example.org/media/two.mp3',
        extension: 'mp3',
      );
      expect(a, isNot(b));
    });

    test('appends the extension with or without a leading dot', () {
      expect(
        MediaDownloader.cacheFileName('https://a/x', extension: 'mp3'),
        endsWith('.mp3'),
      );
      expect(
        MediaDownloader.cacheFileName('https://a/x', extension: '.mp4'),
        endsWith('.mp4'),
      );
    });

    test('is filesystem-safe — hex only, no separators', () {
      final name = MediaDownloader.cacheFileName(
        'https://api.example.org/../../etc/passwd?a=b#c',
        extension: 'mp3',
      );
      expect(name, matches(RegExp(r'^[0-9a-f]+\.mp3$')));
    });

    test('does not collide across a spread of similar URLs', () {
      // Stands in for the collision check that String.hashCode failed.
      final names = <String>{};
      for (var i = 0; i < 200; i++) {
        names.add(
          MediaDownloader.cacheFileName(
            'https://api.example.org/media/story-$i.mp3',
            extension: 'mp3',
          ),
        );
      }
      expect(names.length, 200);
    });
  });

  group('MediaDownloader.resolveCachePath', () {
    test('joins the directory and the hashed name', () {
      final path = MediaDownloader.resolveCachePath(
        '/tmp/audio_cache',
        'https://api.example.org/media/x.mp3',
        extension: 'mp3',
      );
      expect(path, startsWith('/tmp/audio_cache/'));
      expect(path, endsWith('.mp3'));
    });

    test('cannot escape the cache directory via the URL', () {
      // Even though cacheFileName is already hex-only, the basename is
      // re-derived here so a future change cannot turn this into traversal.
      final path = MediaDownloader.resolveCachePath(
        '/tmp/audio_cache',
        'https://api.example.org/../../../../etc/passwd',
        extension: 'mp3',
      );
      expect(path, startsWith('/tmp/audio_cache/'));
      expect(path, isNot(contains('..')));
    });
  });

  group('MediaDownloader.download', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('media_dl_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('refuses a URL outside the policy before opening a socket', () async {
      final destination = File('${tempDir.path}/out.mp3');

      await expectLater(
        MediaDownloader.download(
          'https://evil.example.com/payload.mp3',
          destination,
          apiBaseUrl: 'https://api.example.org',
        ),
        throwsA(isA<MediaDownloadException>()),
      );

      // Nothing was written, and no request was made.
      expect(await destination.exists(), isFalse);
    });

    test('refuses a cleartext URL in a release build', () async {
      final destination = File('${tempDir.path}/out.mp3');

      await expectLater(
        MediaDownloader.download(
          'http://api.example.org/media/x.mp3',
          destination,
          apiBaseUrl: 'https://api.example.org',
        ),
        throwsA(isA<MediaDownloadException>()),
      );
      expect(await destination.exists(), isFalse);
    });
  });
}
