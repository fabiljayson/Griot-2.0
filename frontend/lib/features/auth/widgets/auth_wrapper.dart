import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/onboarding_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand_widgets.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';
import '../screens/onboarding_screen.dart';

/// Wrapper widget that handles authentication routing.
///
/// Shows:
/// - Onboarding screen on first launch
/// - Loading indicator while checking auth status
/// - Login screen if unauthenticated
/// - Child widget if authenticated
///
/// Usage:
/// ```dart
/// AuthWrapper(
///   child: HomeScreen(),
/// )
/// ```
class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final onboardingCompleted = ref.watch(onboardingProvider);

    // Wait until the stored onboarding status has been read so a first-launch
    // user never sees the main shell flash before the onboarding is shown.
    if (onboardingCompleted == null) {
      return const _AuthLoadingScreen();
    }

    // Show onboarding on first launch
    if (!onboardingCompleted) {
      return const OnboardingScreen();
    }

    return authState.when(
      loading: () => const _AuthLoadingScreen(),
      error: (error, stack) => const LoginScreen(),
      data: (state) {
        switch (state.status) {
          case AuthStatus.initial:
          case AuthStatus.loading:
            return const _AuthLoadingScreen();
          case AuthStatus.unauthenticated:
            return const LoginScreen();
          case AuthStatus.authenticated:
            return child;
          case AuthStatus.pendingSync:
            // Registration is queued offline; keep showing login until the
            // account has synced to the server.
            return const LoginScreen();
          case AuthStatus.error:
            // Show login with error state
            return const LoginScreen();
        }
      },
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return BrandScaffold(
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.terracotta,
            strokeWidth: 2.5,
          ),
        ),
      ),
    );
  }
}
