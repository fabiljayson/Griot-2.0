import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/database/repositories/local_auth_repository.dart';
import '../models/user_model.dart';

/// Repository handling local authentication against SQLite.
///
/// All operations delegate to [LocalAuthRepository] — no network requests
/// are made.  Tokens stored in [FlutterSecureStorage] are synthetic markers
/// so the UI and interceptor logic remain compatible.
class AuthRepository {
  AuthRepository({LocalAuthRepository? localAuth})
      : _local = localAuth ?? LocalAuthRepository();

  final LocalAuthRepository _local;

  // --- Token management ---

  /// Check if the user has a stored access token.
  Future<bool> get isAuthenticated => _local.isAuthenticated;

  /// Get the stored access token.
  Future<String?> get accessToken => _local.accessToken;

  /// Get the stored refresh token.
  Future<String?> get refreshToken => _local.refreshToken;

  /// Clear all stored tokens.
  Future<void> clearTokens() => _local.clearTokens();

  // --- Authentication ---

  /// Login with username and password.
  Future<TokenPair> login({
    required String username,
    required String password,
  }) async {
    await _local.login(username: username, password: password);
    return TokenPair(
      accessToken: await _local.accessToken ?? '',
      refreshToken: await _local.refreshToken ?? '',
    );
  }

  /// Register a new account.
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    UserRole role = UserRole.visitor,
  }) async {
    return _local.register(
      username: username,
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      role: role,
    );
  }

  /// Refresh the access token (no-op for local auth).
  Future<TokenPair> refreshTokens() async {
    await _local.refreshTokens();
    return TokenPair(
      accessToken: await _local.accessToken ?? '',
      refreshToken: await _local.refreshToken ?? '',
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
}
