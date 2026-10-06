import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../vr_constants.dart';

/// What happened when we tried to open the Unity application.
enum VrLaunchOutcome {
  /// Android handed the link to the VR app.
  launched,

  /// No installed application accepts `griotvr://`.
  notInstalled,

  /// The system accepted the request but did not open anything, or refused it.
  failed,
}

/// Opens the Unity VR application by deep link.
///
/// Two system behaviours drive this design:
///
/// * **Android 11+ package visibility.** `canLaunchUrl` cannot see an app the
///   manifest has not declared, so it returns false for a *correct* link
///   unless the scheme is listed in `<queries>` (see
///   `android/app/src/main/AndroidManifest.xml`). That is why a false here is
///   reported as "not installed" and why the manifest entry is not optional.
/// * **Launch failures are ordinary.** A link can resolve to an app that then
///   crashes on start. `launchUrl` returning false, or throwing a
///   `PlatformException`, is a normal outcome to report — not a reason to let
///   the app fall over.
class VrLauncher {
  const VrLauncher({VrCanLaunch? canLaunch, VrOpenExternal? open})
    : _canLaunch = canLaunch ?? canLaunchUrl,
      _open = open ?? _openExternal;

  final VrCanLaunch _canLaunch;
  final VrOpenExternal _open;

  /// Open [uri], which must already have been validated by
  /// [VrDeepLink.parseAndValidate].
  Future<VrLaunchOutcome> open(Uri uri) async {
    if (!VrDeepLink.isLaunchUri(uri)) return VrLaunchOutcome.failed;

    try {
      final canOpen = await _canLaunch(uri);
      if (!canOpen) return VrLaunchOutcome.notInstalled;

      final opened = await _open(uri);
      return opened ? VrLaunchOutcome.launched : VrLaunchOutcome.failed;
    } on PlatformException {
      // The platform refused the intent (a restricted profile, a malformed
      // component). Report it rather than propagating it into the widget tree.
      return VrLaunchOutcome.failed;
    }
  }

  static Future<bool> _openExternal(Uri uri) => launchUrl(
    uri,
    // `externalNonBrowserApplication` is the mode that hands the URI to the
    // registered app. The default (`platformDefault`) can route it through a
    // browser tab, which is a dead end for a custom scheme.
    mode: LaunchMode.externalNonBrowserApplication,
  );
}

/// Injectable `canLaunchUrl`, so the launcher is testable without a platform.
typedef VrCanLaunch = Future<bool> Function(Uri uri);

/// Injectable `launchUrl`.
typedef VrOpenExternal = Future<bool> Function(Uri uri);
