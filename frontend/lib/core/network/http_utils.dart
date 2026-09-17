import 'dart:async';
import 'dart:io';

/// Consolidates an [HttpClientResponse] into a single list of bytes.
///
/// This is useful for downloading files for offline caching.
Future<List<int>> consolidateHttpClientResponseBytes(
  HttpClientResponse response, {
  bool autoUncompress = true,
}) async {
  final Completer<List<int>> completer = Completer<List<int>>();
  final List<List<int>> chunks = [];

  response.listen(
    (data) {
      chunks.add(data);
    },
    onDone: () {
      final result = <int>[];
      for (final chunk in chunks) {
        result.addAll(chunk);
      }
      completer.complete(result);
    },
    onError: (error, stackTrace) {
      completer.completeError(error, stackTrace);
    },
  );

  return completer.future;
}
