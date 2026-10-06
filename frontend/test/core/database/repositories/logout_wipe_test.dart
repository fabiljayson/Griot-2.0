import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;

import 'package:griot_ai/core/database/app_database.dart';
import 'package:griot_ai/core/database/repositories/local_auth_repository.dart';
import 'package:griot_ai/core/database/repositories/offline_request_repository.dart';
import 'package:griot_ai/core/database/repositories/offline_user_repository.dart';
import 'package:griot_ai/core/security/local_credential_hasher.dart';
import 'package:griot_ai/features/auth/repositories/auth_repository.dart';

/// Signing out has to take the person with it, not just their token.
///
/// A shared or handed-over phone is the case that matters: if logout only
/// dropped the session, the next person to open the app found the previous
/// reader's name, email, searches, drafts queued for upload and quiz history
/// already on screen.
class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDb;
  late String dbPath;
  late _MockSecureStorage storage;
  late Map<String, String> secureValues;
  late LocalAuthRepository localAuth;
  late OfflineUserRepository offlineUsers;
  late OfflineRequestRepository offlineRequests;
  late AuthRepository auth;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbPath = p.join(await getDatabasesPath(), 'griot_logout_test.db');
    appDb = AppDatabase.forTesting(name: 'griot_logout_test.db');
  });

  setUp(() async {
    await appDb.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();

    appDb = AppDatabase.forTesting(name: 'griot_logout_test.db');
    secureValues = <String, String>{};
    storage = _MockSecureStorage();

    when(() => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
          aOptions: any(named: 'aOptions'),
          iOptions: any(named: 'iOptions'),
          wOptions: any(named: 'wOptions'),
          lOptions: any(named: 'lOptions'),
          webOptions: any(named: 'webOptions'),
        )).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value == null) {
        secureValues.remove(key);
      } else {
        secureValues[key] = value;
      }
    });

    when(() => storage.read(
          key: any(named: 'key'),
          aOptions: any(named: 'aOptions'),
          iOptions: any(named: 'iOptions'),
          wOptions: any(named: 'wOptions'),
          lOptions: any(named: 'lOptions'),
          webOptions: any(named: 'webOptions'),
        )).thenAnswer(
      (invocation) async => secureValues[invocation.namedArguments[#key] as String],
    );

    when(() => storage.delete(
          key: any(named: 'key'),
          aOptions: any(named: 'aOptions'),
          iOptions: any(named: 'iOptions'),
          wOptions: any(named: 'wOptions'),
          lOptions: any(named: 'lOptions'),
          webOptions: any(named: 'webOptions'),
        )).thenAnswer(
      (invocation) async => secureValues.remove(invocation.namedArguments[#key] as String),
    );

    localAuth = LocalAuthRepository(database: appDb, secureStorage: storage);
    offlineUsers =
        OfflineUserRepository(database: appDb, secureStorage: storage);
    offlineRequests = OfflineRequestRepository(database: appDb);
    auth = AuthRepository(
      localAuth: localAuth,
      database: appDb,
      offlineUsers: offlineUsers,
    );
    // Valid-but-fast records: a full-cost hash would risk the per-test
    // timeout once a test registers and signs in.
    LocalCredentialHasher.debugOverrideIterations = 10000;
  });

  tearDown(() async {
    LocalCredentialHasher.debugOverrideIterations = null;
    await appDb.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  Future<int> count(String table) async {
    final db = await appDb.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// A device mid-session: signed in, with a draft queued and a registration
  /// still waiting to reach the server.
  Future<void> signInAndLeaveTraces() async {
    final user = await localAuth.register(
      username: 'amara',
      email: 'amara@example.com',
      password: 'correct-horse',
    );
    await localAuth.login(username: 'amara', password: 'correct-horse');

    final db = await appDb.database;
    await db.insert('search_history', {'query': 'why did my mother leave'});
    await db.insert('local_user_gamification', {'user_id': user.id, 'total_xp': 900});
    await db.insert('local_quiz_attempts', {'quiz_id': 1, 'user_id': user.id, 'score': 100});
    await db.insert('reading_progress', {'story_id': 1, 'scroll_fraction': 0.5});
    await db.insert('local_stories', {
      'title': 'The Ba\'aka Pygmies',
      'slug': 'the-baaka-pygmies',
      'content': 'A story in the public library.',
    });
    await offlineRequests.saveRequest(
      method: 'POST',
      path: '/api/stories/',
      body: {'title': 'My unfinished draft'},
    );
    await offlineUsers.saveUser(
      username: 'kwame',
      email: 'kwame@example.com',
      password: 'pending-registration-secret',
    );
  }

  test('logout leaves no trace of the account on the device', () async {
    await signInAndLeaveTraces();

    await auth.logout();

    expect(await localAuth.isAuthenticated, isFalse);
    expect(await localAuth.accessToken, isNull);
    expect(await localAuth.refreshToken, isNull);
    expect(await count('local_users'), 0);
    expect(await count('offline_users'), 0);
    expect(await count('local_user_gamification'), 0);
    expect(await count('local_quiz_attempts'), 0);
    expect(await count('search_history'), 0);
    expect(await count('offline_requests'), 0);
  });

  test('logout also drops the password of a registration awaiting sync',
      () async {
    await signInAndLeaveTraces();
    expect(
      secureValues.values.any((v) => v.contains('pending-registration-secret')),
      isTrue,
      reason: 'precondition: the pending password is stored before logout',
    );

    await auth.logout();

    expect(secureValues.values, isNot(contains('pending-registration-secret')));
  });

  test('the whole database is free of the reader after logout', () async {
    await signInAndLeaveTraces();

    await auth.logout();

    final db = await appDb.database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final dump = StringBuffer();
    for (final t in tables) {
      dump.writeln((await db.rawQuery('SELECT * FROM ${t['name']}')).toString());
    }
    final text = dump.toString();
    expect(text, isNot(contains('amara')));
    expect(text, isNot(contains('amara@example.com')));
    expect(text, isNot(contains('My unfinished draft')));
    expect(text, isNot(contains('why did my mother leave')));
  });

  test('the offline library survives, so the next reader is not punished',
      () async {
    await signInAndLeaveTraces();
    // The library is seeded on create, so compare against what was there
    // rather than an absolute number.
    final storiesBefore = await count('local_stories');

    await auth.logout();

    // Public content and per-story position carry no account identity, and
    // clearing them would leave the next person with nothing to read offline.
    expect(await count('local_stories'), storiesBefore);
    expect(await count('reading_progress'), 1);
    final db = await appDb.database;
    final mine = await db.query(
      'local_stories',
      where: 'slug = ?',
      whereArgs: ['the-baaka-pygmies'],
    );
    expect(mine, hasLength(1));
  });

  test('a 401 clears the session without destroying offline state', () async {
    // An expired token is recoverable; wiping a reader's library over one would
    // be a far worse outcome than keeping it.
    await signInAndLeaveTraces();

    await auth.clearTokens();

    expect(await localAuth.isAuthenticated, isFalse);
    expect(await count('local_users'), 1);
    expect(await count('search_history'), 1);
    expect(await count('local_stories'), greaterThan(0));
  });

  test('logout is safe to call with no session', () async {
    await expectLater(auth.logout(), completes);
  });
}
