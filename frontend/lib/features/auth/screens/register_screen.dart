import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/brand_widgets.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';

/// Registration screen for the Griot AI app.
///
/// Split-screen layout matching the login screen:
/// - Left panel: dark branding with GriotMark, African proverb, platform metrics
/// - Right panel: clean registration form with role selection
///
/// On narrow screens (< 720px) the layout stacks vertically.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  UserRole _selectedRole = UserRole.visitor;

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
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    final status = await ref
        .read(authProvider.notifier)
        .register(
          username: _usernameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          role: _selectedRole,
        );

    if (!mounted) return;

    if (status == AuthStatus.pendingSync) {
      // Offline: the account is saved locally and will sync later.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You're offline — your account was saved and will be activated "
            "when you're back online.",
          ),
        ),
      );
      Navigator.of(context).pop();
    } else if (status == AuthStatus.authenticated) {
      // Online registration succeeded and auto-logged-in; drop back to the
      // root, where AuthWrapper has already switched to the home screen.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final authState = ref.watch(authProvider);

    return BrandScaffold(
      animController: _animController,
      child: _RegisterFormPanel(
        formKey: _formKey,
        usernameController: _usernameController,
        emailController: _emailController,
        passwordController: _passwordController,
        confirmPasswordController: _confirmPasswordController,
        firstNameController: _firstNameController,
        lastNameController: _lastNameController,
        obscurePassword: _obscurePassword,
        obscureConfirmPassword: _obscureConfirmPassword,
        selectedRole: _selectedRole,
        onTogglePassword: () =>
            setState(() => _obscurePassword = !_obscurePassword),
        onToggleConfirmPassword: () =>
            setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
        onRoleChanged: (role) => setState(() => _selectedRole = role),
        onRegister: _handleRegister,
        onNavigateToLogin: () => Navigator.of(context).pop(),
        authState: authState,
        theme: theme,
        scheme: scheme,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  REGISTER FORM PANEL (Right side)
// ═══════════════════════════════════════════════════════════════════════

class _RegisterFormPanel extends StatelessWidget {
  const _RegisterFormPanel({
    required this.formKey,
    required this.usernameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.firstNameController,
    required this.lastNameController,
    required this.obscurePassword,
    required this.obscureConfirmPassword,
    required this.selectedRole,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onRoleChanged,
    required this.onRegister,
    required this.onNavigateToLogin,
    required this.authState,
    required this.theme,
    required this.scheme,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final bool obscurePassword;
  final bool obscureConfirmPassword;
  final UserRole selectedRole;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmPassword;
  final ValueChanged<UserRole> onRoleChanged;
  final Future<void> Function() onRegister;
  final VoidCallback onNavigateToLogin;
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
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──
                  Text(
                    'Join the journey',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontFamily: 'Fraunces',
                      fontWeight: FontWeight.w700,
                      fontSize: isWide ? null : 30,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create an account to save your progress and contribute stories.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: isWide ? 32 : 24),

                  // ── Role selection ──
                  Text(
                    'Choose your role',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'PlusJakartaSans',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _RoleCard(
                          role: UserRole.visitor,
                          selected: selectedRole == UserRole.visitor,
                          onTap: () => onRoleChanged(UserRole.visitor),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _RoleCard(
                          role: UserRole.contributor,
                          selected: selectedRole == UserRole.contributor,
                          onTap: () => onRoleChanged(UserRole.contributor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Username ──
                  _AuthTextField(
                    controller: usernameController,
                    label: 'Username',
                    hint: 'Choose a unique username',
                    icon: FaIcon(AppIcons.person_outline),
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a username';
                      }
                      if (value.trim().length < 3) {
                        return 'Must be at least 3 characters';
                      }
                      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value.trim())) {
                        return 'Only letters, numbers, and underscores';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Email ──
                  _AuthTextField(
                    controller: emailController,
                    label: 'Email',
                    hint: 'you@example.com',
                    icon: FaIcon(AppIcons.email_outlined),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!RegExp(
                        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                      ).hasMatch(value.trim())) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Name fields ──
                  Row(
                    children: [
                      Expanded(
                        child: _AuthTextField(
                          controller: firstNameController,
                          label: 'First Name',
                          hint: 'Optional',
                          icon: FaIcon(AppIcons.person_outline),
                          textInputAction: TextInputAction.next,
                          showIcon: false,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AuthTextField(
                          controller: lastNameController,
                          label: 'Last Name',
                          hint: 'Optional',
                          icon: FaIcon(AppIcons.person_outline),
                          textInputAction: TextInputAction.next,
                          showIcon: false,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Password ──
                  _AuthTextField(
                    controller: passwordController,
                    label: 'Password',
                    hint: 'At least 8 characters',
                    icon: FaIcon(AppIcons.lock_outline),
                    obscureText: obscurePassword,
                    textInputAction: TextInputAction.next,
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
                        return 'Please enter a password';
                      }
                      if (value.length < 8) {
                        return 'Must be at least 8 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Confirm password ──
                  _AuthTextField(
                    controller: confirmPasswordController,
                    label: 'Confirm Password',
                    hint: 'Re-enter your password',
                    icon: FaIcon(AppIcons.lock_outline),
                    obscureText: obscureConfirmPassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => onRegister(),
                    suffixIcon: IconButton(
                      icon: FaIcon(
                        obscureConfirmPassword
                            ? AppIcons.visibility_off
                            : AppIcons.visibility,
                        size: 18,
                      ),
                      onPressed: onToggleConfirmPassword,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // ── Error message ──
                  if ((authState.value?.hasError ?? false)) ...[
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
                        children: [
                          const FaIcon(
                            AppIcons.error_outline,
                            color: AppColors.error,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              authState.value?.errorMessage ??
                                  'An error occurred',
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

                  // ── Register button ──
                  _AuthButton(
                    onPressed: authState.isLoading ? null : onRegister,
                    isLoading: authState.isLoading,
                    label: 'Create Account',
                  ),
                  const SizedBox(height: 20),

                  // ── Divider ──
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'or',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: scheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Sign in link ──
                  TextButton(
                    onPressed: onNavigateToLogin,
                    child: RichText(
                      text: TextSpan(
                        text: 'Already have an account? ',
                        style: theme.textTheme.bodyMedium,
                        children: [
                          TextSpan(
                            text: 'Sign In',
                            style: TextStyle(
                              color: AppColors.terracotta,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ROLE CARD
// ═══════════════════════════════════════════════════════════════════════

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected
          ? AppColors.terracotta.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppColors.terracotta
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              FaIcon(
                role == UserRole.visitor
                    ? AppIcons.explore
                    : AppIcons.edit_outlined,
                color: selected
                    ? AppColors.terracotta
                    : theme.colorScheme.onSurfaceVariant,
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                role.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontFamily: 'PlusJakartaSans',
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? AppColors.terracotta : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                role == UserRole.visitor
                    ? 'Browse & read stories'
                    : 'Submit & share stories',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════

/// Styled text field for auth forms.
class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.textInputAction,
    this.onFieldSubmitted,
    this.suffixIcon,
    this.validator,
    this.keyboardType,
    this.showIcon = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final FaIcon icon;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      keyboardType: keyboardType,
      style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'PlusJakartaSans'),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: showIcon ? icon : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: theme.brightness == Brightness.dark
            ? AppColors.surfaceDark.withValues(alpha: 0.6)
            : AppColors.sand.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.terracotta, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}

/// Primary auth action button.
class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.onPressed,
    required this.label,
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.terracotta,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.terracotta.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}
