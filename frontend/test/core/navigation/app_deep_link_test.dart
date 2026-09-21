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
}
