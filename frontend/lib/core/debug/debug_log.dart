import 'package:flutter/foundation.dart';

/// Prints [message] to the console in debug builds and is fully compiled away
/// in release builds.
///
/// Wrap noisy development output in this instead of [debugPrint] so release
/// consoles stay clean.
void debugLog(String message) {
  assert(() {
    debugPrint(message);
    return true;
  }());
}
