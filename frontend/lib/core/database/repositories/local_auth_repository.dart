import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/auth/models/user_model.dart';
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
        _storage = secureStorage ?? const FlutterSecureStorage();

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
  Future<void> saveRemoteSession({
    required int serverUserId,
    required String username,
    required String email,
    String firstName = '',
    String lastName = '',
    UserRole role = UserRole.visitor,
    String institution = '',
    required String password,
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
        'password': password,
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
  Future<UserModel> login({
    required String username,
    required String password,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'local_users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw Exception('Invalid username or password');
    }

    final row = rows.first;
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
      'password': password,
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

    final db = await _db;
    await db.delete(
      'local_users',
      where: 'id = ?',
      whereArgs: [int.parse(userIdStr)],
    );
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
