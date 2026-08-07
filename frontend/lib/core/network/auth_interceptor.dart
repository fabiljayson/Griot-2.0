import 'package:dio/dio.dart';

import '../../features/auth/repositories/auth_repository.dart';

/// Dio interceptor that automatically:
/// 1. Injects the Bearer token on every request
/// 2. Attempts a token refresh on 401 responses
/// 3. Retries the failed request with the new token
///
/// This ensures seamless authentication without the UI needing to
/// manage token lifecycle explicitly.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required AuthRepository authRepository})
      : _authRepo = authRepository;

  final AuthRepository _authRepo;

  /// Flag to prevent infinite refresh loops.
  bool _isRefreshing = false;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip token injection for auth endpoints (login, register, refresh).
    final path = options.path;
    if (path.contains('/api/auth/')) {
      return handler.next(options);
    }

    final token = await _authRepo.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    return handler.next(options);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only attempt refresh on 401 errors and if not already refreshing.
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;

      try {
        // Attempt to refresh the token.
        await _authRepo.refreshTokens();
        final newToken = await _authRepo.accessToken;

        if (newToken != null && newToken.isNotEmpty) {
          // Retry the original request with the new token.
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          final response = await Dio().fetch(err.requestOptions);
          return handler.resolve(response);
        }
      } catch (_) {
        // Refresh failed; clear tokens and propagate the error.
        await _authRepo.clearTokens();
      } finally {
        _isRefreshing = false;
      }
    }

    return handler.next(err);
  }
}
