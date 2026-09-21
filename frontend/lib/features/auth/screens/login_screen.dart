import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/auth_page_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/auth_form_widgets.dart';
import '../../../core/widgets/brand_widgets.dart';
import '../providers/auth_provider.dart';
import 'register_screen.dart';

/// Login screen for the Griot AI app.
///
/// Split-screen layout:
/// - Left panel: dark branding with GriotMark, African proverb, platform metrics
/// - Right panel: clean login form
///
/// On narrow screens (< 720px) the layout stacks vertically.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Animation for the branding panel elements
  late final AnimationController _animController;
  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(authProvider.notifier)
        .login(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final authState = ref.watch(authProvider);

    return BrandScaffold(
      animController: _animController,
      child: _LoginFormPanel(
        formKey: _formKey,
        usernameController: _usernameController,
        passwordController: _passwordController,
        obscurePassword: _obscurePassword,
        onTogglePassword: () =>
            setState(() => _obscurePassword = !_obscurePassword),
        onLogin: _handleLogin,
        onNavigateToRegister: () =>
            navigateWithFadeSlide(context, const RegisterScreen()),
        authState: authState,
        theme: theme,
        scheme: scheme,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  LOGIN FORM PANEL (Right side)
// ═══════════════════════════════════════════════════════════════════════

class _LoginFormPanel extends StatelessWidget {
  const _LoginFormPanel({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onNavigateToRegister,
    required this.authState,
    required this.theme,
    required this.scheme,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final Future<void> Function() onLogin;
  final VoidCallback onNavigateToRegister;
  final AsyncValue<dynamic> authState;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 720;

    return Container(
      color: isWide ? scheme.surface : Colors.transparent,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 48 : 24,
            vertical: isWide ? 40 : 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Welcome text ──
                  Text(
                    'Welcome back',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w700,
                      fontSize: isWide ? null : 30,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to continue your journey through living heritage.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: isWide ? 40 : 28),

                  // ── Username / Email field ──
                  AuthTextField(
                    controller: usernameController,
                    label: 'Username',
                    hint: 'Enter your username',
                    icon: FaIcon(AppIcons.person_outline),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your username';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // ── Password field ──
                  AuthTextField(
                    controller: passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: FaIcon(AppIcons.lock_outline),
                    obscureText: obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => onLogin(),
                    suffixIcon: IconButton(
                      icon: FaIcon(
                        obscurePassword
                            ? AppIcons.visibility_off
                            : AppIcons.visibility,
                        size: 18,
                      ),
                      onPressed: onTogglePassword,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Error message ──
                  if (authState.maybeWhen(
                    data: (s) => s.hasError,
                    orElse: () => false,
                  )) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FaIcon(
                            AppIcons.error_outline,
                            color: AppColors.error,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              authState.maybeWhen(
                                data: (s) => s.errorMessage,
                                orElse: () => 'An error occurred',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Sign In button ──
                  AuthButton(
                    onPressed: authState.isLoading ? null : onLogin,
                    isLoading: authState.isLoading,
                    label: 'Sign In',
                  ),
                  const SizedBox(height: 20),

                  // ── Create account button ──
                  OutlinedButton(
                    onPressed: onNavigateToRegister,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(
                        color: AppColors.terracotta.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      'Create Free Account',
                      style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Closing note ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bronzeTint.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FaIcon(
                          AppIcons.bookmark_outline,
                          color: AppColors.bronzeDark,
                          size: 15,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Your saved stories and progress stay with you.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.charcoal,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
