import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../database/repositories/offline_request_repository.dart';
import 'auth_interceptor.dart';
import 'connectivity_service.dart';

/// Shared Dio instance for all API calls.
///
/// Pre-configured with:
///   - exponential-backoff smart retry (1s → 3s → 7s, Task 4.3)
///   - auth interceptor for automatic Bearer token injection & refresh
///   - JSON request/response handling
///   - a base URL injected via --dart-define=API_BASE_URL
///   - offline request queueing when device is offline
class ApiClient {
  ApiClient._({
    AuthInterceptor? authInterceptor,
    OfflineRequestRepository? offlineRepository,
    ConnectivityService? connectivityService,
    String? baseUrl,
  }) {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? AppConstants.effectiveBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
        },
      ),
    );

    _offlineRepository = offlineRepository ?? OfflineRequestRepository();
    _connectivityService = connectivityService;

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

    // Add offline queue interceptor
    dio.interceptors.add(OfflineQueueInterceptor(
      offlineRepository: _offlineRepository,
      connectivityService: _connectivityService,
    ));
  }

  static final ApiClient instance = ApiClient._();

  /// Create an ApiClient with auth interceptor for authenticated requests.
  static ApiClient withAuth({
    required AuthInterceptor authInterceptor,
    ConnectivityService? connectivityService,
    String? baseUrl,
  }) {
    return ApiClient._(
      authInterceptor: authInterceptor,
      connectivityService: connectivityService,
      baseUrl: baseUrl,
    );
  }

  late final Dio dio;
  late final OfflineRequestRepository _offlineRepository;
  ConnectivityService? _connectivityService;

  /// Queue a request for later execution when offline.
  Future<void> queueOfflineRequest({
    required String method,
    required String path,
    dynamic body,
    Map<String, dynamic>? headers,
  }) async {
    await _offlineRepository.saveRequest(
      method: method,
      path: path,
      body: body,
      headers: headers,
    );
    debugPrint('[ApiClient] Request queued for offline: $method $path');
  }
}

/// Interceptor that queues requests when offline.
class OfflineQueueInterceptor extends Interceptor {
  OfflineQueueInterceptor({
    required OfflineRequestRepository offlineRepository,
    ConnectivityService? connectivityService,
  })  : _offlineRepository = offlineRepository,
        _connectivityService = connectivityService;

  final OfflineRequestRepository _offlineRepository;
  final ConnectivityService? _connectivityService;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Check if we're online
    final isOnline = _connectivityService?.isOnline ?? true;

    // Auth endpoints (login, register, token refresh) are time-sensitive and
    // their callers expect a real token response. Never queue them with a
    // synthetic body (callers would crash or fake success), and never let the
    // retry interceptor stall them for seconds. When offline, fail fast with a
    // real connection error the UI can surface.
    if (options.path.contains('/api/auth/')) {
      options.disableRetry = true;
      if (!isOnline) {
        return handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'You are offline.',
          ),
        );
      }
      return handler.next(options);
    }

    if (!isOnline && options.method != 'GET') {
      // Queue non-GET requests when offline
      await _offlineRepository.saveRequest(
        method: options.method,
        path: options.path,
        body: options.data,
        headers: options.headers.cast<String, String>(),
      );

      // Return a synthetic response indicating the request was queued
      final queuedResponse = Response(
        requestOptions: options,
        statusCode: 202,
        data: {
          'status': 'queued',
          'message': 'Request queued for offline execution',
          'queued_at': DateTime.now().toIso8601String(),
        },
      );
      return handler.resolve(queuedResponse);
    }

    return handler.next(options);
  }
}
