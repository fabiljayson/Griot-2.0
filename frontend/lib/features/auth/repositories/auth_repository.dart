import 'package:dio/dio.dart';

import '../../../core/database/repositories/local_auth_repository.dart';
import '../models/user_model.dart';
import 'server_auth_repository.dart';

/// Thrown when the backend rejects login credentials AND no matching local
/// account exists to fall back on.
class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException();

  @override
  String toString() => 'Invalid username or password.';
}

/// Repository handling authentication.
///
/// Auth is online-first: when the backend is reachable, real JWT pairs are
/// obtained from `/api/auth/token/` and stored in secure storage so
/// authenticated endpoints (TTS narration, gamification, …) work. When the
/// server is unreachable the legacy local SQLite/secure-storage session is
/// used so the app remains usable offline.
class AuthRepository {
  AuthRepository({
    LocalAuthRepository? localAuth,
    ServerAuthRepository? server,
  })  : _local = localAuth ?? LocalAuthRepository(),
        _server = server ?? ServerAuthRepository();

  final LocalAuthRepository _local;
  final ServerAuthRepository _server;

  // --- Token management ---

  /// Check if the user has a stored access token.
  Future<bool> get isAuthenticated => _local.isAuthenticated;

  /// Get the stored access token (real JWT or synthetic offline marker).
  Future<String?> get accessToken => _local.accessToken;

  /// Get the stored refresh token.
  Future<String?> get refreshToken => _local.refreshToken;

  /// Clear all stored tokens.
  Future<void> clearTokens() => _local.clearTokens();

  /// Whether the stored session carries a real backend JWT.
  Future<bool> get hasServerSession => _local.hasServerSession;

  // --- Authentication ---

  /// Login with username and password.
  ///
  /// Tries the backend first. On unreachable server or rejected credentials
  /// for an account that only exists locally, falls back to the offline
  /// SQLite session so existing devices keep working.
  Future<TokenPair> login({
    required String username,
    required String password,
  }) async {
    try {
      final tokens = await _server.login(
        username: username,
        password: password,
      );

      final profile = await _server.me(tokens.accessToken);
      await _local.saveRemoteSession(
        serverUserId: profile['id'] as int? ?? 0,
        username: username,
        email: profile['email'] as String? ?? '',
        firstName: profile['first_name'] as String? ?? '',
        lastName: profile['last_name'] as String? ?? '',
        role: UserRole.fromString(profile['role'] as String? ?? 'visitor'),
        institution: profile['institution'] as String? ?? '',
        password: password,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens;
    } on DioException catch (e) {
      if (_isServerUnreachable(e)) {
        // Offline: fall back to the legacy local account.
        await _local.login(username: username, password: password);
        return _localPair();
      }

      if (e.response?.statusCode == 401) {
        // Server is reachable but rejected the credentials. Still honour a
        // matching local account (hybrid), otherwise surface a clear error.
        try {
          await _local.login(username: username, password: password);
          return await _localPair();
        } on Exception {
          throw const InvalidCredentialsException();
        }
      }

      rethrow;
    }
  }

  /// Register a new account.
  ///
  /// Online: creates the account on the backend, signs in, and persists a
  /// real session before returning. Unreachable-server [DioException]s are
  /// rethrown so the caller's offline path (pending-sync) can handle them.
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    UserRole role = UserRole.visitor,
  }) async {
    final userData = await _server.register(
      username: username,
      email: email,
      password: password,
      firstName: firstName ?? '',
      lastName: lastName ?? '',
      role: role,
    );

    final user = UserModel.fromJson(userData);

    // Auto sign-in to persist the real session.
    final tokens = await _server.login(
      username: user.username,
      password: password,
    );
    await _local.saveRemoteSession(
      serverUserId: user.id,
      username: user.username,
      email: user.email,
      firstName: user.firstName,
      lastName: user.lastName,
      role: user.role,
      institution: user.institution,
      password: password,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    return user;
  }

  /// Refresh the access token.
  ///
  /// Real sessions are refreshed against the backend endpoint. Synthetic
  /// (offline) tokens never expire, so refresh is a no-op for them.
  Future<TokenPair> refreshTokens() async {
    final refreshToken = await _local.refreshToken;

    final isSynthetic = refreshToken == null ||
        refreshToken.isEmpty ||
        refreshToken.startsWith('local_');
    if (isSynthetic) {
      await _local.refreshTokens();
      return _localPair();
    }

    final tokens = await _server.refresh(refreshToken);
    await _local.saveAccessToken(tokens.accessToken);
    return TokenPair(
      accessToken: tokens.accessToken,
      refreshToken: refreshToken,
    );
  }

  // --- Profile ---

  /// Get the current user's profile.
  Future<UserModel> getMe() => _local.getMe();

  /// Update the current user's profile.
  Future<UserModel> updateProfile({String? firstName, String? lastName}) =>
      _local.updateProfile(firstName: firstName, lastName: lastName);

  /// Delete the current user's account.
  Future<void> deleteAccount() => _local.deleteAccount();

  /// Logout by clearing stored tokens.
  Future<void> logout() => _local.logout();

  // --- Helpers ---

  Future<TokenPair> _localPair() async {
    // Local session: tokens are the synthetic markers held in secure storage.
    return TokenPair(
      accessToken: await _local.accessToken ?? '',
      refreshToken: await _local.refreshToken ?? '',
    );
  }

  bool _isServerUnreachable(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout;
  }
}