import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import 'auth_interceptor.dart';

/// Shared Dio instance for all API calls.
///
/// Pre-configured with:
///   - exponential-backoff smart retry (1s → 3s → 7s, Task 4.3)
///   - auth interceptor for automatic Bearer token injection & refresh
///   - JSON request/response handling
///   - a base URL injected via --dart-define=API_BASE_URL

class ApiClient {
  ApiClient._({AuthInterceptor? authInterceptor}) {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ),
    );

    // Auth interceptor (if provided) — injects Bearer tokens and refreshes.
    if (authInterceptor != null) {
      dio.interceptors.add(authInterceptor);
    }

    // Exponential backoff: attempt, wait 1s; attempt, wait 3s; attempt, wait 7s.
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        logPrint: (message) => debugPrint('[dio] $message'),
        retries: 3,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 3),
          Duration(seconds: 7),
        ],
      ),
    );
  }

  static final ApiClient instance = ApiClient._();

  /// Create an ApiClient with auth interceptor for authenticated requests.
  static ApiClient withAuth({required AuthInterceptor authInterceptor}) {
    return ApiClient._(authInterceptor: authInterceptor);
  }

  late final Dio dio;
}
