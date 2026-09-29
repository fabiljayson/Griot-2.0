import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/auth/models/user_model.dart';
import '../../security/local_credential_hasher.dart';
import '../../security/secure_storage_factory.dart';
import '../app_database.dart';

/// Repository for local authentication against the SQLite database.
///
/// All login, registration, and profile operations happen locally — no
/// network requests are made.
class LocalAuthRepository {
  LocalAuthRepository({
    AppDatabase? database,
    FlutterSecureStorage? secureStorage,
  })  : _database = database ?? AppDatabase.instance,
        _storage = secureStorage ?? SecureStorageFactory.instance;

  final AppDatabase _database;
  final FlutterSecureStorage _storage;

  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyCurrentUserId = 'current_user_id';

  Future<Database> get _db async => _database.database;

  // ── Token helpers (synthetic, for UI compatibility) ──

  Future<bool> get isAuthenticated async {
    final userId = await _storage.read(key: _keyCurrentUserId);
    return userId != null && userId.isNotEmpty;
  }

  Future<String?> get accessToken => _storage.read(key: _keyAccessToken);
  Future<String?> get refreshToken => _storage.read(key: _keyRefreshToken);

  Future<void> _saveSyntheticTokens(int userId) async {
    // Synthetic JWT-like tokens so the UI and interceptor logic works.
    await _storage.write(key: _keyAccessToken, value: 'local_token_$userId');
    await _storage.write(key: _keyRefreshToken, value: 'local_refresh_$userId');
    await _storage.write(key: _keyCurrentUserId, value: '$userId');
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyCurrentUserId);
  }

  /// Whether the stored tokens are a real backend JWT pair (as opposed to
  /// the synthetic `local_token_*` markers used for offline-only sessions).
  Future<bool> get hasServerSession async {
    final token = await _storage.read(key: _keyAccessToken);
    return token != null &&
        token.isNotEmpty &&
        !token.startsWith('local_');
  }

  /// Persist a real backend session so authenticated API calls (e.g. TTS
  /// narration) can present a valid JWT.
  ///
  /// Synchronises the matching `local_users` row so offline browsing and
  /// profiles keep working, then stores the real token pair.
  ///
  /// The account was just authenticated against the server, which is where the
  /// credential is actually authoritative, so [password] is only used to
  /// refresh the local hash and is never written to the database.
  Future<void> saveRemoteSession({
    required int serverUserId,
    required String username,
    required String email,
    String firstName = '',
    String lastName = '',
    UserRole role = UserRole.visitor,
    String institution = '',
    required String accessToken,
    required String refreshToken,
  }) async {
    final db = await _db;

    final existing = await db.query(
      'local_users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );

    final fields = {
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'role': role.value,
      'institution': institution,
    };

    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await db.update(
        'local_users',
        fields,
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.insert('local_users', {
        'username': username,
        // A server-backed account authenticates with its JWT, so no local
        // password is set — `password_hash` stays NULL and offline login for
        // this row is not offered.
        'password_hash': null,
        ...fields,
      });
    }

    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(key: _keyCurrentUserId, value: '$serverUserId');
  }

  /// Replace the existing access token (after a successful refresh).
  Future<void> saveAccessToken(String accessToken) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
  }

  // ── Authentication ──

  /// Login with username and password against the local `local_users` table.
  ///
  /// The row is fetched by username alone and the password is checked against
  /// the stored PBKDF2 hash, so the secret is never used as a `WHERE` value —
  /// which would both put it in the query log and make verification a plain
  /// string compare.
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'local_users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw Exception('Invalid username or password');
    }

    final row = rows.first;
    if (!LocalCredentialHasher.verify(password, row['password_hash'] as String?)) {
      // Covers a wrong password, an account that exists only on the server
      // (no local hash), and a row whose hash failed to parse.
      throw Exception('Invalid username or password');
    }

    final userId = row['id'] as int;
    await _saveSyntheticTokens(userId);

    return _rowToUser(row);
  }

  /// Register a new user locally.
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    UserRole role = UserRole.visitor,
  }) async {
    final db = await _db;

    // Check for duplicates.
    final existing = await db.query(
      'local_users',
      where: 'username = ? OR email = ?',
      whereArgs: [username, email],
    );
    if (existing.isNotEmpty) {
      throw Exception('Username or email already registered');
    }

    final id = await db.insert('local_users', {
      'username': username,
      'email': email,
      'password_hash': LocalCredentialHasher.hash(password),
      'first_name': firstName ?? '',
      'last_name': lastName ?? '',
      'role': role.value,
    });

    await _saveSyntheticTokens(id);

    return UserModel(
      id: id,
      username: username,
      email: email,
      firstName: firstName ?? '',
      lastName: lastName ?? '',
      role: role,
    );
  }

  /// Get the current user's profile from local storage.
  Future<UserModel> getMe() async {
    final userIdStr = await _storage.read(key: _keyCurrentUserId);
    if (userIdStr == null) throw Exception('No authenticated user');

    final db = await _db;
    final rows = await db.query(
      'local_users',
      where: 'id = ?',
      whereArgs: [int.parse(userIdStr)],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('User not found');

    return _rowToUser(rows.first);
  }

  /// Update the current user's profile.
  Future<UserModel> updateProfile({String? firstName, String? lastName}) async {
    final userIdStr = await _storage.read(key: _keyCurrentUserId);
    if (userIdStr == null) throw Exception('No authenticated user');
    final userId = int.parse(userIdStr);

    final updates = <String, dynamic>{};
    if (firstName != null) updates['first_name'] = firstName;
    if (lastName != null) updates['last_name'] = lastName;

    if (updates.isNotEmpty) {
      final db = await _db;
      await db.update(
        'local_users',
        updates,
        where: 'id = ?',
        whereArgs: [userId],
      );
    }

    return getMe();
  }

  /// Delete the current user's account.
  Future<void> deleteAccount() async {
    final userIdStr = await _storage.read(key: _keyCurrentUserId);
    if (userIdStr == null) throw Exception('No authenticated user');

    // A deleted account must leave as little behind as a signed-out one: the
    // old path removed only the `local_users` row and left gamification, quiz
    // attempts, pending registrations and queued requests on the device.
    await _database.wipeUserScopedData();
    await clearTokens();
  }

  /// Logout by clearing stored tokens.
  Future<void> logout() async {
    await clearTokens();
  }

  /// Refresh tokens is a no-op for local auth.
  Future<void> refreshTokens() async {
    // Synthetic tokens never expire.
  }

  // ── Helpers ──

  UserModel _rowToUser(Map<String, dynamic> row) {
    return UserModel(
      id: row['id'] as int,
      username: row['username'] as String,
      email: (row['email'] as String?) ?? '',
      firstName: (row['first_name'] as String?) ?? '',
      lastName: (row['last_name'] as String?) ?? '',
      role: UserRole.fromString((row['role'] as String?) ?? 'visitor'),
      institution: (row['institution'] as String?) ?? '',
    );
  }
}
