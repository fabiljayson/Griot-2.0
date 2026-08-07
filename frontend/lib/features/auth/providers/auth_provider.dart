import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../repositories/auth_repository.dart';

/// State of the authentication system.
enum AuthStatus {
  /// Initial state, checking for existing session.
  initial,

  /// No authenticated user.
  unauthenticated,

  /// User is authenticated.
  authenticated,

  /// Loading state (login, register, etc.).
  loading,

  /// An error occurred.
  error,
}

/// Immutable state class for authentication.
class AuthState {
  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
  });

  final AuthStatus status;
  final UserModel? user;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading => status == AuthStatus.loading;
  bool get hasError => status == AuthStatus.error;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Notifier managing authentication state.
class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    // Check for existing session on app start.
    final authRepo = ref.read(authRepositoryProvider);
    final isAuth = await authRepo.isAuthenticated;

    if (!isAuth) {
      return const AuthState(status: AuthStatus.unauthenticated);
    }

    try {
      final user = await authRepo.getMe();
      return AuthState(
        status: AuthStatus.authenticated,
        user: user,
      );
    } catch (e) {
      // Token might be expired; try refresh.
      try {
        await authRepo.refreshTokens();
        final user = await authRepo.getMe();
        return AuthState(
          status: AuthStatus.authenticated,
          user: user,
        );
      } catch (_) {
        await authRepo.clearTokens();
        return const AuthState(status: AuthStatus.unauthenticated);
      }
    }
  }

  /// Login with username and password.
  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = const AsyncData(AuthState(status: AuthStatus.loading));

    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.login(username: username, password: password);
      final user = await authRepo.getMe();

      state = AsyncData(AuthState(
        status: AuthStatus.authenticated,
        user: user,
      ));
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      state = AsyncData(AuthState(
        status: AuthStatus.error,
        errorMessage: message,
      ));
    } catch (e) {
      state = AsyncData(AuthState(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Register a new account.
  Future<void> register({
    required String username,
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    UserRole role = UserRole.visitor,
  }) async {
    state = const AsyncData(AuthState(status: AuthStatus.loading));

    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.register(
        username: username,
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
        role: role,
      );

      // Auto-login after registration.
      await authRepo.login(username: username, password: password);
      final user = await authRepo.getMe();

      state = AsyncData(AuthState(
        status: AuthStatus.authenticated,
        user: user,
      ));
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      state = AsyncData(AuthState(
        status: AuthStatus.error,
        errorMessage: message,
      ));
    } catch (e) {
      state = AsyncData(AuthState(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Update the user's profile.
  Future<void> updateProfile({
    String? firstName,
    String? lastName,
  }) async {
    state = const AsyncData(AuthState(status: AuthStatus.loading));

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final user = await authRepo.updateProfile(
        firstName: firstName,
        lastName: lastName,
      );

      state = AsyncData(AuthState(
        status: AuthStatus.authenticated,
        user: user,
      ));
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      state = AsyncData(AuthState(
        status: AuthStatus.error,
        errorMessage: message,
      ));
    } catch (e) {
      state = AsyncData(AuthState(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Delete the user's account.
  Future<void> deleteAccount() async {
    state = const AsyncData(AuthState(status: AuthStatus.loading));

    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.deleteAccount();

      state = const AsyncData(AuthState(
        status: AuthStatus.unauthenticated,
      ));
    } catch (e) {
      state = AsyncData(AuthState(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Logout and clear all data.
  Future<void> logout() async {
    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.logout();

    state = const AsyncData(AuthState(
      status: AuthStatus.unauthenticated,
    ));
  }

  /// Clear any error message.
  void clearError() {
    final current = state.valueOrNull;
    if (current != null && current.hasError) {
      state = AsyncData(current.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: null,
      ));
    }
  }

  String _extractErrorMessage(DioException e) {
    if (e.response?.data is Map) {
      final data = e.response!.data as Map<String, dynamic>;
      if (data.containsKey('detail')) {
        return data['detail'] as String;
      }
      // Extract first error message from validation errors.
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) {
          return value.first.toString();
        }
        if (value is String) return value;
      }
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timed out. Please check your network.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Unable to connect to the server.';
    }
    return 'An unexpected error occurred. Please try again.';
  }
}

// --- Providers ---

/// Repository provider.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Authentication state provider.
final authProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
