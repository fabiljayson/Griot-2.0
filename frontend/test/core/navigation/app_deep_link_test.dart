import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/navigation/app_deep_link.dart';

void main() {
  group('AppDeepLink.parse', () {
    test('parses the custom story scheme', () {
      expect(
        AppDeepLink.parse(Uri.parse('griot-ai://story/river-goddess')),
        const AppDeepLink(kind: DeepLinkKind.story, value: 'river-goddess'),
      );
    });

    test('parses an https story link', () {
      expect(
        AppDeepLink.parse(Uri.parse('https://griot-ai.org/story/lions-bath')),
        const AppDeepLink(kind: DeepLinkKind.story, value: 'lions-bath'),
      );
    });

    test('parses the QR label path used by museum artifacts', () {
      expect(
        AppDeepLink.parse(Uri.parse('https://griot-ai.org/qr/bamoun-throne')),
        const AppDeepLink(
          kind: DeepLinkKind.artifact,
          value: 'bamoun-throne',
        ),
      );
    });

    test('parses an artifact link', () {
      expect(
        AppDeepLink.parse(
          Uri.parse('https://griot-ai.org/artifact/talking-drum/'),
        ),
        const AppDeepLink(
          kind: DeepLinkKind.artifact,
          value: 'talking-drum',
        ),
      );
    });

    test('still accepts legacy africanteller.org artifact links', () {
      expect(
        AppDeepLink.parse(
          Uri.parse('https://africanteller.org/artifact/old-id'),
        ),
        const AppDeepLink(kind: DeepLinkKind.artifact, value: 'old-id'),
      );
    });

    test('parses a region query link', () {
      expect(
        AppDeepLink.parse(
          Uri.parse('https://griot-ai.org/stories?region=grassfields'),
        ),
        const AppDeepLink(kind: DeepLinkKind.region, value: 'grassfields'),
      );
    });

    test('parses a region path link', () {
      expect(
        AppDeepLink.parse(Uri.parse('griot-ai://region/adamawa')),
        const AppDeepLink(kind: DeepLinkKind.region, value: 'adamawa'),
      );
    });

    test('matches collections case-insensitively', () {
      expect(
        AppDeepLink.parse(Uri.parse('https://griot-ai.org/STORY/Lions-Bath')),
        const AppDeepLink(kind: DeepLinkKind.story, value: 'Lions-Bath'),
      );
    });

    test('returns null for links the app cannot open', () {
      expect(AppDeepLink.parse(null), isNull);
      expect(AppDeepLink.parse(Uri.parse('https://griot-ai.org/')), isNull);
      expect(
        AppDeepLink.parse(Uri.parse('https://griot-ai.org/unknown/thing')),
        isNull,
      );
      expect(AppDeepLink.parse(Uri.parse('griot-ai://story')), isNull);
    });
  });

  group('slug validation', () {
    // A deep link is attacker-supplied: any installed app or any web page can
    // fire one at this app, and the slug becomes a route argument that is sent
    // to the API. Values that are not shaped like a Django SlugField are
    // refused at parse time rather than passed along.

    test('accepts the slugs the backend actually produces', () {
      for (final slug in [
        'lions-bath',
        'royal_bamoun_throne',
        'Bamoun',
        'story-2024',
        'art-de-la-province',
      ]) {
        expect(
          AppDeepLink.isValidSlug(slug),
          isTrue,
          reason: 'expected "$slug" to be a valid slug',
        );
      }
    });

    test('accepts non-latin slugs', () {
      // Django's SlugField allows Unicode letters; the QR labels are not
      // restricted to ASCII.
      expect(AppDeepLink.isValidSlug('patrimoine-culturel'), isTrue);
    });

    test('rejects path traversal', () {
      for (final slug in ['..', '../../etc/passwd', 'a/../b', '.']) {
        expect(
          AppDeepLink.isValidSlug(slug),
          isFalse,
          reason: 'expected "$slug" to be rejected',
        );
      }
    });

    test('rejects spaces and separators', () {
      for (final slug in ['lions bath', 'lions/bath', 'lions?bath', 'a b']) {
        expect(AppDeepLink.isValidSlug(slug), isFalse);
      }
    });

    test('rejects log-injection characters', () {
      // These would end up in a log line or an error message.
      for (final slug in [
        'story\nINFO: user logged in',
        'story\r\nSet-Cookie: x=1',
        'story\u0000null',
      ]) {
        expect(
          AppDeepLink.isValidSlug(slug),
          isFalse,
          reason: 'expected control characters to be rejected',
        );
      }
    });

    test('rejects quote and angle-bracket characters', () {
      for (final slug in ["story'", 'story"', '<script>', 'a&b']) {
        expect(AppDeepLink.isValidSlug(slug), isFalse);
      }
    });

    test('rejects an over-long slug', () {
      final tooLong = 'a' * (AppDeepLink.maxSlugLength + 1);
      expect(AppDeepLink.isValidSlug(tooLong), isFalse);
      expect(
        AppDeepLink.isValidSlug('a' * AppDeepLink.maxSlugLength),
        isTrue,
      );
    });

    test('rejects an empty slug', () {
      expect(AppDeepLink.isValidSlug(''), isFalse);
    });

    test('parse drops a story link whose slug is not a slug', () {
      expect(
        AppDeepLink.parse(Uri.parse('griot-ai://story/..%2F..%2Fadmin')),
        isNull,
      );
      expect(
        AppDeepLink.parse(Uri.parse('https://griot-ai.org/story/lions%20bath')),
        isNull,
      );
    });

    test('parse drops an artifact link carrying a traversal slug', () {
      expect(
        AppDeepLink.parse(Uri.parse('griot-ai://artifact/..%2Fadmin')),
        isNull,
      );
    });

    test('parse drops a region query that is not a slug', () {
      expect(
        AppDeepLink.parse(
          Uri.parse('https://griot-ai.org/stories?region=..%2Fadmin'),
        ),
        isNull,
      );
    });

    test('a valid slug on a custom-scheme link still parses', () {
      // Guards against the validation accidentally rejecting the real thing.
      expect(
        AppDeepLink.parse(Uri.parse('griot-ai://story/royal-bamoun-throne')),
        const AppDeepLink(
          kind: DeepLinkKind.story,
          value: 'royal-bamoun-throne',
        ),
      );
    });
  });
}
