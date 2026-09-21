import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Provider to check and manage onboarding completion status.
///
/// Uses FlutterSecureStorage to persist the onboarding state across app restarts.
/// Shows onboarding only on the very first app launch.
final onboardingProvider = StateNotifierProvider<OnboardingNotifier, bool>(
  (ref) => OnboardingNotifier()..checkStatus(),
);

/// Notifier for managing onboarding state.
class OnboardingNotifier extends StateNotifier<bool> {
  OnboardingNotifier() : super(true);

  static const _key = 'onboarding_completed';
  final _storage = const FlutterSecureStorage();

  /// Check if onboarding has been completed.
  Future<void> checkStatus() async {
    final value = await _storage.read(key: _key);
    state = value == 'true';
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
