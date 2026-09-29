import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:griot_ai/core/database/app_database.dart';
import 'package:griot_ai/core/database/repositories/offline_request_repository.dart';

/// A queued request must not become a credential store.
///
/// The `offline_requests` table is unencrypted SQLite that ships inside device
/// backups, and a queued row can sit there for days. Anything that authenticates
/// the holder — a bearer token, a session cookie, an API key — must not be
/// written to it, because replay re-attaches a current credential anyway.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDb;
  late String dbPath;
  late OfflineRequestRepository repo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbPath = p.join(await getDatabasesPath(), 'griot_offreq_test.db');
    appDb = AppDatabase.forTesting(name: 'griot_offreq_test.db');
  });

  setUp(() async {
    await appDb.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
    appDb = AppDatabase.forTesting(name: 'griot_offreq_test.db');
    repo = OfflineRequestRepository(database: appDb);
  });

  tearDown(() async {
    await appDb.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  /// The whole database as text, to prove a secret is absent from the file
  /// rather than merely moved elsewhere.
  Future<String> dumpDatabase() async {
    final db = await appDb.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final buffer = StringBuffer();
    for (final t in tables) {
      final table = t['name'] as String;
      buffer.writeln((await db.rawQuery('SELECT * FROM $table')).toString());
    }
    return buffer.toString();
  }

  Future<Map<String, dynamic>> headersOf(int id) async {
    final request = await repo.getRequest(id);
    return Map<String, dynamic>.from(
      jsonDecode(request!.headers ?? '{}') as Map,
    );
  }

  test('an Authorization header is never persisted', () async {
    final request = await repo.saveRequest(
      method: 'POST',
      path: '/api/stories/',
      body: {'title': 'Anansi'},
      headers: {
        'Authorization': 'Bearer eyJhbGciOiJIUzI1NiJ9.secret.signature',
        'Content-Type': 'application/json',
      },
    );

    final stored = await headersOf(request.id!);
    expect(stored.containsKey('Authorization'), isFalse);
    expect(stored['Content-Type'], 'application/json');
    expect(await dumpDatabase(), isNot(contains('Bearer eyJ')));
  });

  test('the returned request object also omits it, not just the row', () async {
    final request = await repo.saveRequest(
      method: 'POST',
      path: '/api/stories/',
      headers: {'Authorization': 'Bearer secret'},
    );

    expect(request.headers, isNot(contains('secret')));
  });

  test('other credential headers are stripped too', () async {
    final request = await repo.saveRequest(
      method: 'POST',
      path: '/api/stories/',
      headers: {
        'Authorization': 'Bearer a',
        'Proxy-Authorization': 'Basic b',
        'Cookie': 'sessionid=abc',
        'X-API-Key': 'k',
        'X-Auth-Token': 't',
        'X-Correlation-Id': 'keep-me',
      },
    );

    final stored = await headersOf(request.id!);
    expect(stored.keys, ['X-Correlation-Id']);
  });

  test('stripping is case-insensitive, as HTTP header names are', () async {
    final request = await repo.saveRequest(
      method: 'POST',
      path: '/api/stories/',
      headers: {
        'authorization': 'Bearer a',
        'AUTHORIZATION': 'Bearer b',
        'AuThOrIzAtIoN': 'Bearer c',
        'Cookie': 'sessionid=abc',
      },
    );

    expect(await headersOf(request.id!), isEmpty);
  });

  test('a request with no headers is still stored', () async {
    final request = await repo.saveRequest(
      method: 'POST',
      path: '/api/stories/',
      body: {'title': 'Anansi'},
    );

    expect(request.id, isNotNull);
    expect(await repo.getPendingRequests(), hasLength(1));
  });

  test('the body and path survive intact', () async {
    final request = await repo.saveRequest(
      method: 'PUT',
      path: '/api/users/me/',
      body: {'first_name': 'Amara'},
      headers: {'Authorization': 'Bearer a', 'X-Trace': '1'},
    );

    final stored = await repo.getRequest(request.id!);
    expect(stored!.path, '/api/users/me/');
    expect(stored.method, 'PUT');
    expect(jsonDecode(stored.body!), {'first_name': 'Amara'});
    expect(jsonDecode(stored.headers!), {'X-Trace': '1'});
  });

  test(
      'v8 scrubs tokens that an earlier build already queued', () async {
    // A device from before the fix: a queued row with a live bearer token.
    final old = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE offline_requests (
              id            INTEGER PRIMARY KEY AUTOINCREMENT,
              method        TEXT NOT NULL,
              path          TEXT NOT NULL,
              body          TEXT,
              headers       TEXT,
              created_at    TEXT NOT NULL DEFAULT (datetime('now')),
              retry_count   INTEGER NOT NULL DEFAULT 0,
              max_retries   INTEGER NOT NULL DEFAULT 3,
              status        TEXT NOT NULL DEFAULT 'pending',
              error_message TEXT
            )
          ''');
          await db.execute(
            "INSERT INTO offline_requests (method, path, headers) VALUES "
            "('POST', '/api/stories/', "
            "'{\"Authorization\": \"Bearer leaked-token-value\", "
            "\"Content-Type\": \"application/json\"}')",
          );
        },
      ),
    );
    await old.close();

    final db = await appDb.database;
    final rows = await db.query('offline_requests');

    final headers = Map<String, dynamic>.from(
      jsonDecode(rows.single['headers'] as String) as Map,
    );
    expect(headers.containsKey('Authorization'), isFalse);
    expect(headers['Content-Type'], 'application/json');
    expect((await db.rawQuery('SELECT * FROM offline_requests')).toString(),
        isNot(contains('leaked-token-value')));
  });
}
