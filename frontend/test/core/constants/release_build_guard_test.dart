import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/core/constants/app_constants.dart';

void main() {
  group('AppConstants release build guard', () {
    // A release compiled without `--dart-define=API_BASE_URL=https://...` keeps
    // the emulator loopback default. Android blocks that at the network layer
    // and iOS blocks it via ATS, so either way the shipped app has no working
    // API origin. The guard turns a silent misconfiguration into a startup
    // failure that is visible on the build machine.

    test('the test build is not a release build', () {
      // These tests compile without RELEASE_BUILD, so the guard must be inert
      // here — otherwise the whole suite would throw at startup.
      expect(AppConstants.isReleaseBuild, isFalse);
    });

    test('the guard does not fire outside a release build', () {
      expect(AppConstants.assertCleartextBaseUrlIsSafe, returnsNormally);
    });

    test('recognises cleartext origins', () {
      expect(AppConstants.isCleartextUrl('http://10.0.2.2:8000'), isTrue);
      expect(AppConstants.isCleartextUrl('http://localhost:8000'), isTrue);
      expect(AppConstants.isCleartextUrl('https://api.example.org'), isFalse);
      expect(AppConstants.isCleartextUrl('not a url'), isFalse);
    });

    test('an unconfigured build resolves to a cleartext base URL', () {
      // Documents the exact condition the guard exists for. These tests
      // compile with no API_BASE_URL define, so effectiveBaseUrl is the
      // emulator loopback — which is what a release build missing the
      // --dart-define would also get, and which iOS ATS would then refuse.
      expect(
        AppConstants.isCleartextUrl(AppConstants.effectiveBaseUrl),
        isTrue,
        reason: 'expected the default base URL to be the cleartext loopback',
      );
    });
  });
}
