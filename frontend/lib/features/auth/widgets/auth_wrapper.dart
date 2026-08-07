import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';

/// Wrapper widget that handles authentication routing.
///
/// Shows:
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
  const AuthWrapper({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

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
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.terracotta,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.terracotta.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Text('🪘', style: TextStyle(fontSize: 40)),
            ),
            const SizedBox(height: 24),
            Text(
              'African Teller',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              color: AppColors.terracotta,
            ),
          ],
        ),
      ),
    );
  }
}
