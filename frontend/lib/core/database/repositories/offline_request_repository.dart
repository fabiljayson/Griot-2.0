import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models/offline_request.dart';

/// Data-access layer for the `offline_requests` table.
///
/// Manages pending API requests that were queued while offline.
/// These requests are replayed when connectivity is restored.
class OfflineRequestRepository {
  OfflineRequestRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Database> get _db async => _database.database;

  /// Header names that must never be written to the database.
  ///
  /// A queued request is replayed later through the same Dio instance, and
  /// `AuthInterceptor.onRequest` overwrites `Authorization` with the token
  /// that is valid *at replay time*. Persisting the one that was current when
  /// the request was queued buys nothing and costs a lot: the `offline_requests`
  /// table is plain SQLite with no encryption, it is included in unencrypted
  /// device backups, and a row can sit there for days. Anyone who can read the
  /// file gets a bearer token for the backend — and unlike a password, the
  /// token needs no cracking, and may well still be valid.
  ///
  /// Compared case-insensitively: HTTP header names are not case-sensitive, so
  /// `authorization` and `Authorization` are the same header to any server.
  static const Set<String> _strippedHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
    'x-auth-token',
  };

  /// Copy of [headers] with credential-bearing entries removed.
  ///
  /// Drops the whole entry rather than blanking the value, so a stripped header
  /// cannot be mistaken for a present-but-empty one.
  static Map<String, dynamic>? _sanitizeHeaders(Map<String, dynamic>? headers) {
    if (headers == null) return null;

    final sanitized = <String, dynamic>{};
    for (final entry in headers.entries) {
      if (_strippedHeaders.contains(entry.key.toLowerCase())) continue;
      sanitized[entry.key] = entry.value;
    }
    return sanitized;
  }

  /// Queue a request for later execution when offline.
  ///
  /// Credential headers are removed before the row is written — see
  /// [_strippedHeaders]. Replay re-attaches the current token, so this does not
  /// weaken the request.
  Future<OfflineRequest> saveRequest({
    required String method,
    required String path,
    dynamic body,
    Map<String, dynamic>? headers,
  }) async {
    final db = await _db;
    final safeHeaders = _sanitizeHeaders(headers);
    final request = OfflineRequest(
      method: method,
      path: path,
      body: body != null ? jsonEncode(body) : null,
      headers: safeHeaders != null ? jsonEncode(safeHeaders) : null,
      createdAt: DateTime.now(),
    );

    final id = await db.insert(
      'offline_requests',
      request.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return request.copyWith(id: id);
  }

  /// Get all requests that still need to be executed, ordered by creation time.
  ///
  /// Includes `pending` and `failed` requests so previously failed attempts
  /// are retried on the next sync (subject to [OfflineRequest.canRetry]/maxRetries).
  /// Any request left in `in_progress` by a previous sync (e.g. the app was
  /// killed mid-sync) is reset back to `pending` so it isn't stranded forever.
  Future<List<OfflineRequest>> getPendingRequests() async {
    final db = await _db;

    // Crash recovery: reset requests stuck in 'in_progress' from a previous
    // sync attempt so they get replayed on the next sync.
    await db.update(
      'offline_requests',
      {'status': OfflineRequestStatus.pending.value},
      where: 'status = ?',
      whereArgs: [OfflineRequestStatus.inProgress.value],
    );

    final rows = await db.query(
      'offline_requests',
      where: 'status != ?',
      whereArgs: [OfflineRequestStatus.completed.value],
      orderBy: 'created_at ASC',
    );
    return rows.map(OfflineRequest.fromMap).toList();
  }

  /// Mark a request as in-progress.
  Future<void> markInProgress(int requestId) async {
    final db = await _db;
    await db.update(
      'offline_requests',
      {'status': OfflineRequestStatus.inProgress.value},
      where: 'id = ?',
      whereArgs: [requestId],
    );
  }

  /// Mark a request as completed.
  Future<void> markCompleted(int requestId) async {
    final db = await _db;
    await db.update(
      'offline_requests',
      {'status': OfflineRequestStatus.completed.value},
      where: 'id = ?',
      whereArgs: [requestId],
    );
  }

  /// Mark a request as failed with an error message.
  Future<void> markFailed(int requestId, String errorMessage) async {
    final db = await _db;
    final request = await getRequest(requestId);
    if (request != null) {
      await db.update(
        'offline_requests',
        {
          'status': OfflineRequestStatus.failed.value,
          'retry_count': request.retryCount + 1,
          'error_message': errorMessage,
        },
        where: 'id = ?',
        whereArgs: [requestId],
      );
    }
  }

  /// Get a specific request by ID.
  Future<OfflineRequest?> getRequest(int requestId) async {
    final db = await _db;
    final rows = await db.query(
      'offline_requests',
      where: 'id = ?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflineRequest.fromMap(rows.first);
  }

  /// Get count of requests still awaiting sync (pending, failed, in-progress).
  Future<int> getPendingCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM offline_requests WHERE status != 'completed'",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear all completed or failed requests older than the specified duration.
  Future<void> clearOldRequests({Duration maxAge = const Duration(days: 7)}) async {
    final db = await _db;
    final cutoff = DateTime.now().subtract(maxAge).toIso8601String();
    await db.delete(
      'offline_requests',
      where: "status IN ('completed', 'failed') AND created_at < ?",
      whereArgs: [cutoff],
    );
  }

  /// Clear all requests (for logout or manual sync reset).
  Future<void> clearAll() async {
    final db = await _db;
    await db.delete('offline_requests');
  }
}
