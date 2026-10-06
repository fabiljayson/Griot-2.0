import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/vr/vr_constants.dart';

/// The launch link is a string that becomes an Android Intent.
///
/// These tests pin the boundary: the client accepts only an exact
/// `griotvr://launch` link with a plausibly-minted token and numeric ids, and
/// every link it does accept is **rebuilt** from those checked parts rather
/// than passed through.
void main() {
  const token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  group('VrDeepLink.parseAndValidate', () {
    test('rewrites a valid link from its validated parts', () {
      final uri = VrDeepLink.parseAndValidate(
        'griotvr://launch?token=$token&experience=42&artifact=108',
      );

      expect(uri, isNotNull);
      expect(uri!.scheme, 'griotvr');
      expect(uri.host, 'launch');
      expect(uri.queryParameters['token'], token);
      expect(uri.queryParameters['experience'], '42');
      expect(uri.queryParameters['artifact'], '108');
    });

    test('accepts a launch with no artifact id', () {
      final uri = VrDeepLink.parseAndValidate(
        'griotvr://launch?token=$token&experience=42',
      );

      expect(uri, isNotNull);
      expect(uri!.queryParameters.containsKey('artifact'), isFalse);
    });

    test('drops query parameters that are not part of the grammar', () {
      final uri = VrDeepLink.parseAndValidate(
        'griotvr://launch?token=$token&experience=42&admin=1&redirect=evil',
      );

      expect(uri!.queryParameters.keys, ['token', 'experience']);
    });

    test('rejects a link on another scheme', () {
      expect(
        VrDeepLink.parseAndValidate(
          'https://africanteller.org/launch?token=$token&experience=42',
        ),
        isNull,
      );
      expect(
        VrDeepLink.parseAndValidate(
          'griot-ai://launch?token=$token&experience=42',
        ),
        isNull,
      );
    });

    test('rejects a link with no host or the wrong host', () {
      expect(
        VrDeepLink.parseAndValidate('griotvr:?token=$token&experience=42'),
        isNull,
      );
      expect(
        VrDeepLink.parseAndValidate(
          'griotvr://story?token=$token&experience=42',
        ),
        isNull,
      );
    });

    test('rejects a missing, short, or malformed token', () {
      expect(
        VrDeepLink.parseAndValidate('griotvr://launch?experience=42'),
        isNull,
      );
      expect(
        VrDeepLink.parseAndValidate('griotvr://launch?token=&experience=42'),
        isNull,
      );
      expect(
        VrDeepLink.parseAndValidate('griotvr://launch?token=short&experience=42'),
        isNull,
      );
      expect(
        VrDeepLink.parseAndValidate(
          'griotvr://launch?token=has%20space%20inside&experience=42',
        ),
        isNull,
      );
      expect(
        VrDeepLink.parseAndValidate('griotvr://launch?token=a/b&experience=42'),
        isNull,
      );
    });

    test('rejects a missing, non-numeric, or non-positive experience id', () {
      for (final experience in ['', 'abc', '0', '-4', '4.2']) {
        expect(
          VrDeepLink.parseAndValidate(
            'griotvr://launch?token=$token&experience=$experience',
          ),
          isNull,
          reason: 'experience="$experience" must not be launchable',
        );
      }
    });

    test('rejects a malformed artifact id rather than ignoring it', () {
      expect(
        VrDeepLink.parseAndValidate(
          'griotvr://launch?token=$token&experience=42&artifact=not-a-number',
        ),
        isNull,
      );
      expect(
        VrDeepLink.parseAndValidate(
          'griotvr://launch?token=$token&experience=42&artifact=0',
        ),
        isNull,
      );
    });

    test('rejects something that is not a URI at all', () {
      expect(VrDeepLink.parseAndValidate(''), isNull);
      expect(VrDeepLink.parseAndValidate('launch?token=x'), isNull);
    });
  });

  group('VrDeepLink.build', () {
    test('encodes an artifact id only when one is given', () {
      final without = VrDeepLink.build(token: token, experienceId: 7);
      final with_ = VrDeepLink.build(
        token: token,
        experienceId: 7,
        artifactId: 9,
      );

      expect(without.toString(), 'griotvr://launch?token=$token&experience=7');
      expect(with_.queryParameters['artifact'], '9');
    });

    test('round-trips through parseAndValidate', () {
      final built = VrDeepLink.build(
        token: token,
        experienceId: 42,
        artifactId: 108,
      );

      expect(VrDeepLink.parseAndValidate(built.toString()), built);
    });
  });

  group('VrDeepLink.isLaunchUri', () {
    test('recognises only the launch host', () {
      expect(
        VrDeepLink.isLaunchUri(Uri.parse('griotvr://launch?token=x')),
        isTrue,
      );
      expect(VrDeepLink.isLaunchUri(Uri.parse('griotvr://other')), isFalse);
      expect(VrDeepLink.isLaunchUri(Uri.parse('https://example.org')), isFalse);
    });
  });
}
