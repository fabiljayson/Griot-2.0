import 'package:flutter_timezone/flutter_timezone.dart';

/// Reads the device's IANA timezone name for the backend.
///
/// A streak is decided on the reader's own calendar, so the client has to send
/// a real zone name like `Africa/Douala`. `DateTime.now().timeZoneName` is no
/// substitute: it yields abbreviations such as `WAT` or `EAT`, which no tz
/// database can resolve, and the server would then fall back to the default and
/// roll the streak over at the wrong hour for a reader abroad.
abstract final class DeviceTimezone {
  static Future<String?> current() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      final identifier = info.identifier.trim();
      // Some platforms report an empty string rather than failing. Sending that
      // would be no better than sending nothing.
      return identifier.isEmpty ? null : identifier;
    } catch (_) {
      // Unsupported platform, or the channel is unavailable in a test or on web.
      // The server keeps the stored zone, so staying silent is the safe answer.
      return null;
    }
  }
}
