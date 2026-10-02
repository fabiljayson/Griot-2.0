import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:griot_ai/core/database/app_database.dart';
import 'package:griot_ai/core/database/repositories/local_auth_repository.dart';
import 'package:griot_ai/core/database/repositories/offline_user_repository.dart';
import 'package:griot_ai/core/security/local_credential_hasher.dart';

/// Guards the two places a credential used to reach the SQLite file.
///
/// The repositories run against the real schema (via `sqflite_common_ffi`), so
/// these assertions cover what the app actually writes rather than a stand-in.
class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase appDb;
  late String dbPath;
  late _MockSecureStorage storage;
  late Map<String, String> secureValues;
  late LocalAuthRepository localAuth;
  late OfflineUserRepository offlineUsers;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbPath = p.join(await getDatabasesPath(), 'griot_cred_test.db');
    // Created here as well as in setUp so the first `close()` in setUp has
    // something to close.
    appDb = AppDatabase.forTesting(name: 'griot_cred_test.db');
  });

  setUp(() async {
    await appDb.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();

    appDb = AppDatabase.forTesting(name: 'griot_cred_test.db');
    secureValues = <String, String>{};
    storage = _MockSecureStorage();

    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
        aOptions: any(named: 'aOptions'),
        iOptions: any(named: 'iOptions'),
        wOptions: any(named: 'wOptions'),
        lOptions: any(named: 'lOptions'),
        webOptions: any(named: 'webOptions'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String?;
      if (value == null) {
        secureValues.remove(key);
      } else {
        secureValues[key] = value;
      }
    });

    when(
      () => storage.read(
        key: any(named: 'key'),
        aOptions: any(named: 'aOptions'),
        iOptions: any(named: 'iOptions'),
        wOptions: any(named: 'wOptions'),
        lOptions: any(named: 'lOptions'),
        webOptions: any(named: 'webOptions'),
      ),
    ).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      return secureValues[key];
    });

    when(
      () => storage.delete(
        key: any(named: 'key'),
        aOptions: any(named: 'aOptions'),
        iOptions: any(named: 'iOptions'),
        wOptions: any(named: 'wOptions'),
        lOptions: any(named: 'lOptions'),
        webOptions: any(named: 'webOptions'),
      ),
    ).thenAnswer((invocation) async {
      secureValues.remove(invocation.namedArguments[#key] as String);
    });

    localAuth = LocalAuthRepository(database: appDb, secureStorage: storage);
    offlineUsers = OfflineUserRepository(
      database: appDb,
      secureStorage: storage,
    );
  });

  tearDown(() async {
    await appDb.close();
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
  });

  /// The whole database as text, to prove a secret is absent from the file
  /// rather than merely moved to another column.
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

  String base64Of(String value) => base64.encode(utf8.encode(value));

  group('LocalAuthRepository', () {
    test('register then login with the correct password succeeds', () async {
      final user = await localAuth.register(
        username: 'amara',
        email: 'amara@example.com',
        password: 'correct-horse',
      );

      final loggedIn = await localAuth.login(
        username: 'amara',
        password: 'correct-horse',
      );

      expect(loggedIn.id, user.id);
      expect(loggedIn.username, 'amara');
    });

    test('login with the wrong password is refused', () async {
      await localAuth.register(
        username: 'amara',
        email: 'amara@example.com',
        password: 'correct-horse',
      );

      await expectLater(
        localAuth.login(username: 'amara', password: 'wrong'),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'the stored password never reaches the database in the clear',
      () async {
        const secret = 'SuperSecretPassphrase!';
        await localAuth.register(
          username: 'amara',
          email: 'amara@example.com',
          password: secret,
        );

        final dump = await dumpDatabase();
        expect(dump, isNot(contains(secret)));
        expect(dump, isNot(contains(base64Of(secret))));
      },
    );

    test('the stored hash is a PBKDF2 record, not the secret', () async {
      await localAuth.register(
        username: 'amara',
        email: 'amara@example.com',
        password: 'correct-horse',
      );

      final db = await appDb.database;
      final raw = await db.rawQuery(
        "SELECT password_hash FROM local_users WHERE username = 'amara'",
      );
      final hash = raw.single['password_hash'] as String;

      expect(hash, startsWith(r'pbkdf2_sha256$'));
      expect(LocalCredentialHasher.verify('correct-horse', hash), isTrue);
    });

    test('a server-backed session stores no local password', () async {
      await localAuth.saveRemoteSession(
        username: 'kofi',
        email: 'kofi@example.com',
        accessToken: 'eyJ.access',
        refreshToken: 'eyJ.refresh',
      );

      final db = await appDb.database;
      final raw = await db.rawQuery(
        "SELECT password_hash FROM local_users WHERE username = 'kofi'",
      );
      expect(raw.single['password_hash'], isNull);

      // With no local credential, offline sign-in is not offered.
      await expectLater(
        localAuth.login(username: 'kofi', password: 'anything'),
        throwsA(isA<Exception>()),
      );
    });

    test('a remote user profile uses its local row id for lookup', () async {
      await localAuth.register(
        username: 'first-local-user',
        email: 'first@example.com',
        password: 'secret123',
      );
      await localAuth.saveRemoteSession(
        username: 'kofi',
        email: 'kofi@example.com',
        accessToken: 'eyJ.access',
        refreshToken: 'eyJ.refresh',
      );

      final user = await localAuth.getMe();

      expect(user.username, 'kofi');
      expect(user.id, isNot(42));
    });

    test('a username that does not exist is refused', () async {
      await expectLater(
        localAuth.login(username: 'nobody', password: 'x'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('OfflineUserRepository', () {
    test(
      'a queued registration keeps its password out of the database',
      () async {
        const secret = 'QueuedSecret!42';
        await offlineUsers.saveUser(
          username: 'queued',
          email: 'queued@example.com',
          password: secret,
        );

        expect(await dumpDatabase(), isNot(contains(secret)));
      },
    );

    test('the password is readable back for replay', () async {
      await offlineUsers.saveUser(
        username: 'queued',
        email: 'queued@example.com',
        password: 'QueuedSecret!42',
      );

      final pending = await offlineUsers.getPendingUsers();
      expect(pending, hasLength(1));

      final secret = await offlineUsers.readPendingPassword(pending.single.id!);
      expect(secret, 'QueuedSecret!42');
    });

    test('syncing drops the stored password', () async {
      final user = await offlineUsers.saveUser(
        username: 'queued',
        email: 'queued@example.com',
        password: 'QueuedSecret!42',
      );

      await offlineUsers.markSynced(user.id!, 99);

      expect(await offlineUsers.readPendingPassword(user.id!), isNull);
      expect(
        secureValues.values,
        isNot(contains('QueuedSecret!42')),
        reason: 'a synced account must not leave its secret behind',
      );
    });

    test('clearAll drops every stored password', () async {
      final a = await offlineUsers.saveUser(
        username: 'a',
        email: 'a@example.com',
        password: 'SecretA',
      );
      final b = await offlineUsers.saveUser(
        username: 'b',
        email: 'b@example.com',
        password: 'SecretB',
      );

      await offlineUsers.clearAll();

      expect(await offlineUsers.getPendingUsers(), isEmpty);
      expect(await offlineUsers.readPendingPassword(a.id!), isNull);
      expect(await offlineUsers.readPendingPassword(b.id!), isNull);
      expect(secureValues.values, isNot(contains('SecretA')));
      expect(secureValues.values, isNot(contains('SecretB')));
    });

    test(
      'a failed registration keeps its password so it can be retried',
      () async {
        final user = await offlineUsers.saveUser(
          username: 'queued',
          email: 'queued@example.com',
          password: 'QueuedSecret!42',
        );

        await offlineUsers.markFailed(user.id!, 'network down');

        expect(
          await offlineUsers.readPendingPassword(user.id!),
          'QueuedSecret!42',
        );
      },
    );
  });
}
