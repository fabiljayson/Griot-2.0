import 'package:dio/dio.dart';

/// Shared value formatting helpers for the admin dashboard.

/// Compact count formatting (1.2K / 3.4M).
String formatCount(int n) {
  if (n >= 1000000) {
    final v = n / 1000000;
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}M';
  }
  if (n >= 1000) {
    final v = n / 1000;
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}K';
  }
  return '$n';
}

/// Human-readable message for a dashboard load error.
String friendlyError(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 403) {
      return 'You need administrator access to view analytics.';
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Could not reach the server. Check your connection.';
    }
  }
  return 'Something went wrong while loading analytics.';
}
