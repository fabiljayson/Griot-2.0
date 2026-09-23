import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../models/user_model.dart';

/// HTTP client for the backend's public auth endpoints.
///
/// These endpoints are deliberately excluded from the shared client's retry
/// and offline-queueing behaviour (see `OfflineQueueInterceptor`), so this
/// repository keeps its own bare Dio with the same base URL and timeouts.
/// No tokens are injected here — login, refresh and register are all
/// anonymous by design.
class ServerAuthRepository {
  ServerAuthRepository({Dio? dio}) : _dio = dio ?? _defaultDio();

  final Dio _dio;

  static Dio _defaultDio() {
    return Dio(
      BaseOptions(
        baseUrl: AppConstants.effectiveBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ),
    );
  }

  /// Exchange username/password for a real JWT pair.
  Future<TokenPair> login({
    required String username,
    required String password,
  }) async {
    final response = await _dio.post(
      '/api/auth/token/',
      data: {'username': username, 'password': password},
    );
    return TokenPair.fromJson(response.data as Map<String, dynamic>);
  }

  /// Exchange a refresh token for a fresh access token.
  Future<TokenPair> refresh(String refreshToken) async {
    final response = await _dio.post(
      '/api/auth/token/refresh/',
      data: {'refresh': refreshToken},
    );
    return TokenPair.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetch the authenticated user's profile (needs the access token).
  Future<Map<String, dynamic>> me(String accessToken) async {
    final response = await _dio.get(
      '/api/users/me/',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return response.data as Map<String, dynamic>;
  }

  /// Create a Visitor/Contributor account.
  ///
  /// Returns the created user's profile map (the backend registers first and
  /// does not return tokens here — call [login] afterwards to sign in).
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String firstName = '',
    String lastName = '',
    UserRole role = UserRole.visitor,
  }) async {
    final response = await _dio.post(
      '/api/auth/register/',
      data: {
        'username': username,
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'role': role.value,
      },
    );
    final body = response.data as Map<String, dynamic>;
    return body['user'] as Map<String, dynamic>? ?? body;
  }
}
