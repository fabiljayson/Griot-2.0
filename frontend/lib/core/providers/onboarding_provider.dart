import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provider to check and manage onboarding completion status.
///
/// Uses FlutterSecureStorage to persist the onboarding state across app restarts.
/// Shows onboarding only on the very first app launch.
///
/// State is `null` while the stored value is still being read, so consumers can
/// avoid flashing a screen before the onboarding status is known.
final onboardingProvider = StateNotifierProvider<OnboardingNotifier, bool?>(
  (ref) => OnboardingNotifier()..checkStatus(),
);

/// Notifier for managing onboarding state.
class OnboardingNotifier extends StateNotifier<bool?> {
  /// [initialCompleted] lifts the stored value for tests/overrides; the default
  /// (null = unknown) makes consumers wait for [checkStatus] instead of
  /// flashing a screen before the real value is read.
  OnboardingNotifier({bool? initialCompleted}) : super(initialCompleted);

  static const _key = 'onboarding_completed';
  final _storage = const FlutterSecureStorage();

  /// Check if onboarding has been completed.
  Future<void> checkStatus() async {
    try {
      final value = await _storage.read(key: _key);
      state = value == 'true';
    } catch (_) {
      // Storage unavailable (fresh install, restricted test env): never block
      // the consumer on a status that cannot be resolved.
      state = false;
    }
  }

  /// Mark onboarding as completed.
  Future<void> completeOnboarding() async {
    await _storage.write(key: _key, value: 'true');
    state = true;
  }

  /// Reset onboarding (for testing purposes).
  Future<void> resetOnboarding() async {
    await _storage.delete(key: _key);
    state = false;
  }
}
