import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/vr/services/vr_launcher.dart';
import 'package:griot_ai/features/vr/vr_constants.dart';

/// Two system behaviours decide what these tests have to cover: with the VR app
/// absent, `canLaunchUrl` returns false (which must read as "not installed"),
/// and with it present the launch can still fail. Neither may throw.
void main() {
  const token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  final launchUri = VrDeepLink.build(token: token, experienceId: 42, artifactId: 108);

  test('reports installed and launched when the system accepts the link', () async {
    Uri? opened;
    final launcher = VrLauncher(
      canLaunch: (_) async => true,
      open: (uri) async {
        opened = uri;
        return true;
      },
    );

    final outcome = await launcher.open(launchUri);

    expect(outcome, VrLaunchOutcome.launched);
    expect(opened, launchUri);
  });

  test('reports not installed without attempting to launch', () async {
    var attempted = false;
    final launcher = VrLauncher(
      canLaunch: (_) async => false,
      open: (_) async {
        attempted = true;
        return true;
      },
    );

    final outcome = await launcher.open(launchUri);

    expect(outcome, VrLaunchOutcome.notInstalled);
    expect(attempted, isFalse);
  });

  test('reports failed when the system opens nothing', () async {
    final launcher = VrLauncher(
      canLaunch: (_) async => true,
      open: (_) async => false,
    );

    expect(await launcher.open(launchUri), VrLaunchOutcome.failed);
  });

  test('reports failed rather than throwing when the platform refuses', () async {
    final launcher = VrLauncher(
      canLaunch: (_) async => true,
      open: (_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );

    expect(await launcher.open(launchUri), VrLaunchOutcome.failed);
  });

  test('reports failed for a URI that is not a launch link', () async {
    var asked = false;
    final launcher = VrLauncher(
      canLaunch: (_) async {
        asked = true;
        return true;
      },
      open: (_) async => true,
    );

    final outcome = await launcher.open(Uri.parse('https://example.org/'));

    expect(outcome, VrLaunchOutcome.failed);
    expect(asked, isFalse);
  });
}
