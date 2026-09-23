import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/app_error.dart';
import '../../../core/network/auth_interceptor.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';
import '../repositories/offline_auth_repository.dart';

/// State of the authentication system.
enum AuthStatus {
  /// Initial state, checking for existing session.
  initial,

  /// No authenticated user.
  unauthenticated,

  /// User is authenticated.
  authenticated,

  /// Registration was saved locally while offline and is awaiting sync to
  /// the server. The account is not usable until sync completes.
  pendingSync,

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
      return AuthState(status: AuthStatus.authenticated, user: user);
    } catch (e) {
      // Token might be expired; try refresh.
      try {
        await authRepo.refreshTokens();
        final user = await authRepo.getMe();
        return AuthState(status: AuthStatus.authenticated, user: user);
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

      state = AsyncData(
        AuthState(status: AuthStatus.authenticated, user: user),
      );
    } on DioException catch (e) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.error,
          errorMessage: AppErrorMapper.fromDio(e).message,
        ),
      );
    } catch (e) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.error,
          errorMessage: AppErrorMapper.fromException(e).message,
        ),
      );
    }
  }

  /// Register a new account.
  ///
  /// Online: registers, auto-logs-in, and returns [AuthStatus.authenticated].
  /// Offline: the registration is saved locally (synced by the
  /// OfflineSyncManager when connectivity returns) and the method returns
  /// [AuthStatus.pendingSync] — the account can only be used once synced.
  Future<AuthStatus> register({
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

      // Register already signs in and persists the real session.
      final user = await authRepo.getMe();

      state = AsyncData(
        AuthState(status: AuthStatus.authenticated, user: user),
      );
      return AuthStatus.authenticated;
    } on DioException catch (e) {
      // Server unreachable — save the registration locally and let the
      // OfflineSyncManager push it to the server when connectivity returns.
      if (_isOfflineError(e)) {
        // Server unreachable — save the registration locally and let the
        // OfflineSyncManager push it to the server when connectivity returns.
        try {
          final offlineRepo = ref.read(offlineAuthProvider);
          await offlineRepo.register(
            username: username,
            email: email,
            password: password,
            firstName: firstName ?? '',
            lastName: lastName ?? '',
            role: role.value,
          );
          state = const AsyncData(AuthState(status: AuthStatus.pendingSync));
          return AuthStatus.pendingSync;
        } catch (offlineError) {
          state = AsyncData(
            AuthState(
              status: AuthStatus.error,
              errorMessage:
                  'Could not save your account for offline activation. Please try again.',
            ),
          );
          return AuthStatus.error;
        }
      }
      state = AsyncData(
        AuthState(
          status: AuthStatus.error,
          errorMessage: AppErrorMapper.fromDio(e).message,
        ),
      );
      return AuthStatus.error;
    } catch (e) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.error,
          errorMessage: AppErrorMapper.fromException(e).message,
        ),
      );
      return AuthStatus.error;
    }
  }

  /// Update the user's profile.
  Future<void> updateProfile({String? firstName, String? lastName}) async {
    state = const AsyncData(AuthState(status: AuthStatus.loading));

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final user = await authRepo.updateProfile(
        firstName: firstName,
        lastName: lastName,
      );

      state = AsyncData(
        AuthState(status: AuthStatus.authenticated, user: user),
      );
    } on DioException catch (e) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.error,
          errorMessage: AppErrorMapper.fromDio(e).message,
        ),
      );
    } catch (e) {
      state = AsyncData(
        AuthState(status: AuthStatus.error, errorMessage: e.toString()),
      );
    }
  }

  /// Delete the user's account.
  Future<void> deleteAccount() async {
    state = const AsyncData(AuthState(status: AuthStatus.loading));

    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.deleteAccount();

      state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
    } catch (e) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.error,
          errorMessage: AppErrorMapper.fromException(e).message,
        ),
      );
    }
  }

  /// Logout and clear all data.
  Future<void> logout() async {
    final authRepo = ref.read(authRepositoryProvider);
    await authRepo.logout();

    state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
  }

  /// Clear any error message.
  void clearError() {
    final current = state.maybeWhen(data: (s) => s, orElse: () => null);
    if (current != null && current.hasError) {
      state = AsyncData(
        AuthState(status: AuthStatus.unauthenticated, user: current.user),
      );
    }
  }

  /// Whether [e] indicates the server could not be reached (offline).
  bool _isOfflineError(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout;
  }
}

// --- Providers ---

/// Repository provider.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// ApiClient wired with the [AuthInterceptor], so any authenticated feature
/// (TTS narration, gamification, …) automatically presents a valid Bearer
/// token and refreshes when the server returns 401.
final authenticatedApiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient.withAuth(
    authInterceptor: AuthInterceptor(
      authRepository: ref.watch(authRepositoryProvider),
    ),
  );
});

/// Authentication state provider.
final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
