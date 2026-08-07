import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_client.dart';
import '../models/user_model.dart';

/// Repository handling authentication API calls and token persistence.
///
/// Tokens are stored securely using flutter_secure_storage. The repository
/// provides methods for login, registration, token refresh, and profile
/// management.
class AuthRepository {
  AuthRepository({
    ApiClient? apiClient,
    FlutterSecureStorage? secureStorage,
  })  : _api = apiClient ?? ApiClient.instance,
        _storage = secureStorage ?? const FlutterSecureStorage();

  final ApiClient _api;
  final FlutterSecureStorage _storage;

  // --- Storage keys ---
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';

  // --- Token management ---

  /// Check if the user has a stored access token.
  Future<bool> get isAuthenticated async {
    final token = await _storage.read(key: _keyAccessToken);
    return token != null && token.isNotEmpty;
  }

  /// Get the stored access token.
  Future<String?> get accessToken => _storage.read(key: _keyAccessToken);

  /// Get the stored refresh token.
  Future<String?> get refreshToken => _storage.read(key: _keyRefreshToken);

  /// Save token pair to secure storage.
  Future<void> _saveTokens(TokenPair tokens) async {
    await _storage.write(key: _keyAccessToken, value: tokens.accessToken);
    await _storage.write(key: _keyRefreshToken, value: tokens.refreshToken);
  }

  /// Clear all stored tokens.
  Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
  }

  // --- Authentication ---

  /// Login with username and password.
  ///
  /// Returns a [TokenPair] on success. Throws [DioException] on failure.
  Future<TokenPair> login({
    required String username,
    required String password,
  }) async {
    final response = await _api.dio.post(
      '/api/auth/token/',
      data: {
        'username': username,
        'password': password,
      },
    );

    final tokens = TokenPair.fromJson(response.data as Map<String, dynamic>);
    await _saveTokens(tokens);
    return tokens;
  }

  /// Register a new account.
  ///
  /// Returns the created [UserModel] on success.
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    UserRole role = UserRole.visitor,
  }) async {
    final response = await _api.dio.post(
      '/api/auth/register/',
      data: {
        'username': username,
        'email': email,
        'password': password,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        'role': role.value,
      },
    );

    final userData = response.data as Map<String, dynamic>;
    return UserModel.fromJson(userData['user'] as Map<String, dynamic>);
  }

  /// Refresh the access token using the stored refresh token.
  Future<TokenPair> refreshTokens() async {
    final storedRefresh = await refreshToken;
    if (storedRefresh == null || storedRefresh.isEmpty) {
      throw Exception('No refresh token available');
    }

    final response = await _api.dio.post(
      '/api/auth/token/refresh/',
      data: {'refresh': storedRefresh},
    );

    final tokens = TokenPair.fromJson(response.data as Map<String, dynamic>);
    await _saveTokens(tokens);
    return tokens;
  }

  // --- Profile ---

  /// Get the current user's profile.
  Future<UserModel> getMe() async {
    final response = await _api.dio.get('/api/users/me/');
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update the current user's profile.
  Future<UserModel> updateProfile({
    String? firstName,
    String? lastName,
  }) async {
    final response = await _api.dio.patch(
      '/api/users/me/',
      data: {
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
      },
    );
    return UserModel.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete the current user's account.
  Future<void> deleteAccount() async {
    await _api.dio.delete('/api/users/me/');
    await clearTokens();
  }

  /// Logout by clearing stored tokens.
  Future<void> logout() async {
    await clearTokens();
  }
}
