import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/vr/models/vr_launch_ticket.dart';

void main() {
  Map<String, dynamic> payload({
    String token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    String deepLink = 'griotvr://launch?token=t&experience=42',
    String expiresAt = '2099-01-01T00:00:00Z',
    int expiresIn = 120,
    Map<String, dynamic>? experience,
    Map<String, dynamic>? artifact,
  }) {
    return {
      'token': token,
      'deep_link': deepLink,
      'expires_at': expiresAt,
      'expires_in': expiresIn,
      'experience': experience ??
          {
            'id': 42,
            'slug': 'bamoun-heritage-gallery',
            'title': 'Bamoun Heritage Gallery',
            'scene_identifier': 'bamoun_gallery',
            'language': 'en',
          },
      'artifact': artifact,
    };
  }

  group('VrLaunchTicket.fromJson', () {
    test('reads the token, the link and the experience', () {
      final ticket = VrLaunchTicket.fromJson(payload());

      expect(ticket.token, isNotEmpty);
      expect(ticket.experience.id, 42);
      expect(ticket.experience.sceneIdentifier, 'bamoun_gallery');
      expect(ticket.expiresInSeconds, 120);
      expect(ticket.artifact, isNull);
      expect(ticket.isUsable, isTrue);
    });

    test('reads the artifact when the launch came from one', () {
      final ticket = VrLaunchTicket.fromJson(
        payload(artifact: {'id': 108, 'slug': 'traditional-mask', 'name': 'Mask'}),
      );

      expect(ticket.artifact?.slug, 'traditional-mask');
    });

    test('survives a sparse payload without throwing', () {
      final ticket = VrLaunchTicket.fromJson(const {});

      expect(ticket.token, isEmpty);
      expect(ticket.experience.id, 0);
      expect(ticket.artifact, isNull);
      expect(ticket.isUsable, isFalse);
    });

    test('ignores an experience of the wrong shape', () {
      final ticket = VrLaunchTicket.fromJson(payload()..['experience'] = 'nope');

      expect(ticket.experience.id, 0);
      expect(ticket.isUsable, isFalse);
    });
  });

  group('VrLaunchTicket.isExpired', () {
    test('is false while the expiry is in the future', () {
      final ticket = VrLaunchTicket.fromJson(payload());

      expect(ticket.isExpired, isFalse);
    });

    test('is true once the expiry has passed', () {
      final ticket = VrLaunchTicket.fromJson(
        payload(expiresAt: '2020-01-01T00:00:00Z'),
      );

      expect(ticket.isExpired, isTrue);
      expect(ticket.isUsable, isFalse);
    });

    test('falls back to the countdown when there is no timestamp', () {
      final live = VrLaunchTicket.fromJson(
        payload(expiresAt: 'not-a-date', expiresIn: 120),
      );
      final dead = VrLaunchTicket.fromJson(
        payload(expiresAt: 'not-a-date', expiresIn: 0),
      );

      expect(live.isExpired, isFalse);
      expect(dead.isExpired, isTrue);
    });
  });

  group('VrLaunchTicket.isUsable', () {
    test('needs a token, a link, an experience and time left', () {
      expect(
        VrLaunchTicket.fromJson(payload(deepLink: '')).isUsable,
        isFalse,
      );
      expect(
        VrLaunchTicket.fromJson(payload(token: '')).isUsable,
        isFalse,
      );
      expect(
        VrLaunchTicket.fromJson(payload(expiresIn: 0, expiresAt: '2020-01-01T00:00:00Z'))
            .isUsable,
        isFalse,
      );
    });
  });
}
