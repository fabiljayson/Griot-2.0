import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../providers/auth_provider.dart';
import '../screens/login_screen.dart';

/// The single sign-in prompt used by every gated action in the app.
///
/// Story actions, artifact audio guides and the reader's quiz CTA all used to
/// raise their own dialog whose "Sign In" button had an empty body (a comment
/// explaining that "navigation to login is handled by the auth wrapper"), so
/// the button did nothing. [SignInPrompt.show] presents the same message and
/// then actually opens the login form, dismissing it once the session becomes
/// authenticated.
abstract final class SignInPrompt {
  /// Ask the user to sign in.
  ///
  /// Returns true when the user completed sign-in. When they cancel, or when
  /// they signed in through a different path while the form was open, returns
  /// false.
  static Future<bool> show(
    BuildContext context, {
    required String message,
    String title = 'Sign In Required',
  }) async {
    final wantsToSignIn = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign In'),
          ),
        ],
      ),
    );

    if (wantsToSignIn != true || !context.mounted) return false;

    final signedIn = await Navigator.of(context, rootNavigator: true)
        .push<bool>(
          MaterialPageRoute(
            builder: (_) => const _SignInRoute(),
            fullscreenDialog: true,
          ),
        );
    return signedIn ?? false;
  }
}

/// Hosts the login form and pops itself as soon as the session is authenticated.
class _SignInRoute extends ConsumerWidget {
  const _SignInRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authProvider, (previous, next) {
      final status = next.value?.status;
      if (status == AuthStatus.authenticated) {
        // Defer the pop: this listener runs before the frame that paints the
        // new auth state, and popping mid-build is not allowed.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).pop(true);
        });
      }
    });

    return const _SignInScaffold(child: LoginScreen());
  }
}

/// Adds a themed app bar above the login form so its "close" affordance is
/// visible when presented as a route rather than as the auth wrapper's home.
class _SignInScaffold extends StatelessWidget {
  const _SignInScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(AppIcons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('Sign In'),
        backgroundColor: scheme.surface,
      ),
      body: child,
      bottomNavigationBar: const SizedBox(height: AppSpacing.xs),
    );
  }
}
