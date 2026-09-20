import 'package:dio/dio.dart';

/// Sealed union representing all possible application failures.
///
/// Every notifier should map exceptions to one of these subtypes so the UI
/// can display context-appropriate messages and Sentry can categorize errors.
sealed class AppFailure {
  const AppFailure();

  /// Human-readable message suitable for end users.
  String get message;

  /// Optional underlying exception for logging / Sentry.
  Object? get cause => null;
}

/// Network-level failure (no internet, DNS, timeout).
final class NetworkFailure extends AppFailure {
  const NetworkFailure({this.cause, this.message = 'Unable to connect. Check your internet connection.'});

  @override
  final String message;

  @override
  final Object? cause;
}

/// Server returned an error response (4xx / 5xx).
final class ServerFailure extends AppFailure {
  const ServerFailure({required this.message, this.statusCode, this.cause});

  @override
  final String message;

  final int? statusCode;

  @override
  final Object? cause;
}

/// Validation / business-rule error from the server.
final class ValidationFailure extends AppFailure {
  const ValidationFailure({required this.message, this.fieldErrors, this.cause});

  @override
  final String message;

  final Map<String, List<String>>? fieldErrors;

  @override
  final Object? cause;
}

/// Offline / cached fallback failure.
final class OfflineFailure extends AppFailure {
  const OfflineFailure({this.message = 'No cached data available offline.', this.cause});

  @override
  final String message;

  @override
  final Object? cause;
}

/// Catch-all for unexpected errors.
final class UnknownFailure extends AppFailure {
  const UnknownFailure({this.message = 'An unexpected error occurred. Please try again.', this.cause});

  @override
  final String message;

  @override
  final Object? cause;
}

/// Maps exceptions (primarily [DioException]) to typed [AppFailure]s.
///
/// Use in notifiers / repositories to replace ad-hoc `_extractErrorMessage`
/// methods. The mapper returns a typed failure the UI can switch on, rather
/// than raw strings.
abstract final class AppErrorMapper {
  /// Convert a [DioException] into the most specific [AppFailure].
  static AppFailure fromDio(DioException e) {
    // --- Timeout / connection errors → Network or Offline ---
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(
          message: 'Connection timed out. Please check your network.',
          cause: e,
        );
      case DioExceptionType.connectionError:
        return OfflineFailure(cause: e);
      case DioExceptionType.badCertificate:
        return NetworkFailure(
          message: 'Security certificate error. Please try again later.',
          cause: e,
        );
      case DioExceptionType.cancel:
        return const UnknownFailure(message: 'Request was cancelled.');
      case DioExceptionType.unknown:
        return NetworkFailure(
          message: 'Unable to connect to the server.',
          cause: e,
        );
      case DioExceptionType.badResponse:
        return _mapBadResponse(e);
      case DioExceptionType.transformTimeout:
        return NetworkFailure(
          message: 'Connection timed out. Please check your network.',
          cause: e,
        );
    }
  }

  /// Map a bad-response DioException based on status code.
  static AppFailure _mapBadResponse(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    // Extract detail message from DRF-style responses.
    String? detail;
    if (data is Map<String, dynamic>) {
      detail = data['detail'] as String?;
      // Also check for validation error arrays.
      if (detail == null && data.containsKey('non_field_errors')) {
        final errors = data['non_field_errors'];
        if (errors is List && errors.isNotEmpty) {
          detail = errors.first.toString();
        }
      }
    }

    final message = detail ?? _defaultMessage(statusCode);

    switch (statusCode) {
      case 400:
        return ValidationFailure(message: message, cause: e);
      case 401:
        return const ServerFailure(
          message: 'Your session has expired. Please log in again.',
          statusCode: 401,
        );
      case 403:
        return const ServerFailure(
          message: 'You don\'t have permission to perform this action.',
          statusCode: 403,
        );
      case 404:
        return ServerFailure(message: message, statusCode: 404);
      case 429:
        return const ServerFailure(
          message: 'Too many requests. Please wait a moment and try again.',
          statusCode: 429,
        );
      case final code? when code >= 500:
        return ServerFailure(message: message, statusCode: code, cause: e);
      default:
        return ServerFailure(message: message, statusCode: statusCode, cause: e);
    }
  }

  static String _defaultMessage(int? statusCode) {
    if (statusCode == null) return 'An unexpected error occurred.';
    if (statusCode >= 500) return 'Server error. Please try again later.';
    return 'An unexpected error occurred. Please try again.';
  }

  /// Generic mapper for non-Dio exceptions.
  static AppFailure fromException(Object e) {
    return UnknownFailure(message: e.toString(), cause: e);
  }
}
