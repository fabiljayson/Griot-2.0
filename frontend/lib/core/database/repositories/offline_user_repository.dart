import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../../security/secure_storage_factory.dart';
import '../app_database.dart';
import '../models/offline_user.dart';

/// Data-access layer for the `offline_users` table.
///
/// Manages user registrations that were created offline and need to be
/// synced to the server when connectivity is restored.
///
/// A queued registration still has to hand its plaintext password to the
/// server on replay, so that value is kept in platform secure storage
/// (Keychain / Keystore) under a key derived from the row id. The SQLite row
/// holds only non-secret metadata. Deleting the row without clearing the secure
/// key would strand a credential that nothing references, so
/// [markSynced], [markFailed] and [clearAll] all remove it.
class OfflineUserRepository {
  OfflineUserRepository({
    AppDatabase? database,
    FlutterSecureStorage? secureStorage,
  })  : _database = database ?? AppDatabase.instance,
        _storage = secureStorage ?? SecureStorageFactory.instance;

  final AppDatabase _database;
  final FlutterSecureStorage _storage;

  static const _passwordKeyPrefix = 'pending_registration_password_';

  String _passwordKey(int userId) => '$_passwordKeyPrefix$userId';

  Future<Database> get _db async => _database.database;

  /// Save a new offline user registration.
  ///
  /// [password] is written to secure storage under the new row's id and is not
  /// stored in the database.
  Future<OfflineUser> saveUser({
    required String username,
    required String email,
    required String password,
    String firstName = '',
    String lastName = '',
    String role = 'visitor',
    String institution = '',
  }) async {
    final db = await _db;
    final user = OfflineUser(
      username: username,
      email: email,
      firstName: firstName,
      lastName: lastName,
      role: role,
      institution: institution,
      createdAt: DateTime.now(),
    );

    final id = await db.insert(
      'offline_users',
      user.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _storage.write(key: _passwordKey(id), value: password);

    return user.copyWith(id: id);
  }

  /// The plaintext password for a queued registration, or null if it is gone.
  ///
  /// Null means the registration cannot be replayed — the row may predate the
  /// v8 migration that moved secrets out of the database, or the secure entry
  /// may have been cleared. Callers should surface that to the user instead of
  /// sending an empty password to the server.
  Future<String?> readPendingPassword(int userId) =>
      _storage.read(key: _passwordKey(userId));

  /// Get all pending user registrations.
  ///
  /// Any registration stuck in `syncing` from a previous run (e.g. the app
  /// was killed mid-sync) is reset back to `pending` so it isn't stranded
  /// forever and gets retried on the next sync.
  Future<List<OfflineUser>> getPendingUsers() async {
    final db = await _db;

    // Crash recovery: reset registrations stuck in 'syncing' from a previous
    // sync attempt so they get replayed on the next sync.
    await db.update(
      'offline_users',
      {'status': OfflineUserStatus.pending.value},
      where: 'status = ?',
      whereArgs: [OfflineUserStatus.syncing.value],
    );

    final rows = await db.query(
      'offline_users',
      where: 'status = ?',
      whereArgs: [OfflineUserStatus.pending.value],
      orderBy: 'created_at ASC',
    );
    return rows.map(OfflineUser.fromMap).toList();
  }

  /// Get a user by ID.
  Future<OfflineUser?> getUser(int userId) async {
    final db = await _db;
    final rows = await db.query(
      'offline_users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflineUser.fromMap(rows.first);
  }

  /// Get a user by username.
  Future<OfflineUser?> getUserByUsername(String username) async {
    final db = await _db;
    final rows = await db.query(
      'offline_users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflineUser.fromMap(rows.first);
  }

  /// Mark a user as syncing.
  Future<void> markSyncing(int userId) async {
    final db = await _db;
    await db.update(
      'offline_users',
      {'status': OfflineUserStatus.syncing.value},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Mark a user as synced with the server user ID.
  ///
  /// The registration is now redundant, so its stored password is dropped —
  /// the account exists on the server with its own hashed copy.
  Future<void> markSynced(int userId, int serverUserId) async {
    final db = await _db;
    await db.update(
      'offline_users',
      {
        'status': OfflineUserStatus.synced.value,
        'server_user_id': serverUserId,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    await _storage.delete(key: _passwordKey(userId));
  }

  /// Mark a user as failed with an error message.
  ///
  /// The password is kept so a transient failure can still be retried, but only
  /// while the failure is one the sync loop will retry. Callers that consider
  /// the registration unrecoverable should delete the row, which drops it.
  Future<void> markFailed(int userId, String errorMessage) async {
    final db = await _db;
    await db.update(
      'offline_users',
      {
        'status': OfflineUserStatus.failed.value,
        'error_message': errorMessage,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Get count of pending users.
  Future<int> getPendingCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM offline_users WHERE status = 'pending'",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Check if a username is already registered offline.
  Future<bool> isUsernameRegistered(String username) async {
    final user = await getUserByUsername(username);
    return user != null;
  }

  /// Check if an email is already registered offline.
  Future<bool> isEmailRegistered(String email) async {
    final db = await _db;
    final rows = await db.query(
      'offline_users',
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Clear all offline users (for logout or manual sync reset).
  ///
  /// Also removes every stored pending password, since the rows that referenced
  /// them are gone.
  Future<void> clearAll() async {
    final db = await _db;
    final rows = await db.query('offline_users', columns: ['id']);
    for (final row in rows) {
      await _storage.delete(key: _passwordKey(row['id'] as int));
    }
    await db.delete('offline_users');
  }
}
