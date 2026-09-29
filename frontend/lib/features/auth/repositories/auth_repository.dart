import 'package:dio/dio.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/repositories/local_auth_repository.dart';
import '../../../core/database/repositories/offline_user_repository.dart';
import '../models/user_model.dart';
import 'server_auth_repository.dart';

/// Thrown when the backend rejected login credentials AND no matching local
/// account exists to fall back on.
class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException();

  @override
  String toString() => 'Invalid username or password.';
}

/// Thrown when the account was created on the backend but the follow-up
/// sign-in did not complete.
///
/// The account exists at this point, so callers must never re-post the
/// registration: the offline/pending-sync path does exactly that, and the
/// replay used to come back as 'A user with this email already exists.' for
/// an email the user had never used before.
class RegistrationSignInFailedException implements Exception {
  const RegistrationSignInFailedException({required this.user, this.cause});

  /// The account as the backend now holds it.
  final UserModel user;

  /// The underlying failure, kept for logging rather than for display.
  final Object? cause;

  @override
  String toString() => 'Account created, but sign-in did not complete.';
}

/// Repository handling authentication.
///
/// Auth is online-first: when the backend is reachable, real JWT pairs are
/// obtained from `/api/auth/token/` and stored in secure storage so
/// authenticated endpoints (TTS narration, gamification, …) work. When the
/// server is unreachable the legacy local SQLite/secure-storage session is
/// used so the app remains usable offline.
class AuthRepository {
  AuthRepository({
    LocalAuthRepository? localAuth,
    ServerAuthRepository? server,
    AppDatabase? database,
    OfflineUserRepository? offlineUsers,
  }) : _local = localAuth ?? LocalAuthRepository(),
       _server = server ?? ServerAuthRepository(),
       _database = database ?? AppDatabase.instance,
       _offlineUsers = offlineUsers ?? OfflineUserRepository();

  final LocalAuthRepository _local;
  final ServerAuthRepository _server;
  final AppDatabase _database;
  final OfflineUserRepository _offlineUsers;

  // --- Token management ---

  /// Check if the user has a stored access token.
  Future<bool> get isAuthenticated => _local.isAuthenticated;

  /// Get the stored access token (real JWT or synthetic offline marker).
  Future<String?> get accessToken => _local.accessToken;

  /// Get the stored refresh token.
  Future<String?> get refreshToken => _local.refreshToken;

  /// Clear all stored tokens.
  Future<void> clearTokens() => _local.clearTokens();

  /// Whether the stored session carries a real backend JWT.
  Future<bool> get hasServerSession => _local.hasServerSession;

  // --- Authentication ---

  /// Login with username and password.
  ///
  /// The backend is authoritative. Only when it is genuinely unreachable — no
  /// network, DNS failure, timeout — does this fall back to the offline
  /// SQLite account, so a reader who registered without connectivity can still
  /// get in.
  ///
  /// A 401 is a decision, not an outage. The server reached, read the
  /// credentials, and refused them; honouring a matching local account anyway
  /// would let someone whose server account was disabled, deleted, or had its
  /// password changed continue to sign in on a device that cached the old
  /// credential. A revocation on the server has to be revocation everywhere, so
  /// this path returns [InvalidCredentialsException] and lets the caller sign
  /// the reader out.
  Future<TokenPair> login({
    required String username,
    required String password,
  }) async {
    try {
      final tokens = await _server.login(
        username: username,
        password: password,
      );

      final profile = await _server.me(tokens.accessToken);
      await _local.saveRemoteSession(
        serverUserId: profile['id'] as int? ?? 0,
        username: username,
        email: profile['email'] as String? ?? '',
        firstName: profile['first_name'] as String? ?? '',
        lastName: profile['last_name'] as String? ?? '',
        role: UserRole.fromString(profile['role'] as String? ?? 'visitor'),
        institution: profile['institution'] as String? ?? '',
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return tokens;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // Server-side rejection is final. Clear any local session so a stale
        // cached credential cannot be used after the reader is turned away.
        await _local.clearTokens();
        throw const InvalidCredentialsException();
      }

      if (_isServerUnreachable(e)) {
        // Offline: fall back to the local account.
        await _local.login(username: username, password: password);
        return _localPair();
      }

      rethrow;
    }
  }

  /// Register a new account.
  ///
  /// Online: creates the account on the backend, signs in, and persists a
  /// real session before returning. Unreachable-server [DioException]s from
  /// the create call are rethrown so the caller's offline path
  /// (pending-sync) can handle them.
  ///
  /// Once the create call has returned, the account exists server-side. A
  /// failure in the sign-in step is therefore reported as
  /// [RegistrationSignInFailedException] rather than a transport error, so
  /// the caller never mistakes it for "the server is unreachable" and replays
  /// the registration.
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    UserRole role = UserRole.visitor,
  }) async {
    final userData = await _server.register(
      username: username,
      email: email,
      password: password,
      firstName: firstName ?? '',
      lastName: lastName ?? '',
      role: role,
    );

    final user = UserModel.fromJson(userData);

    // Auto sign-in to persist the real session.
    try {
      final tokens = await _server.login(
        username: user.username,
        password: password,
      );
      await _local.saveRemoteSession(
        serverUserId: user.id,
        username: user.username,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role,
        institution: user.institution,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } catch (e) {
      throw RegistrationSignInFailedException(user: user, cause: e);
    }
    return user;
  }

  /// Refresh the access token.
  ///
  /// Real sessions are refreshed against the backend endpoint. Synthetic
  /// (offline) tokens never expire, so refresh is a no-op for them.
  Future<TokenPair> refreshTokens() async {
    final refreshToken = await _local.refreshToken;

    final isSynthetic =
        refreshToken == null ||
        refreshToken.isEmpty ||
        refreshToken.startsWith('local_');
    if (isSynthetic) {
      await _local.refreshTokens();
      return _localPair();
    }

    final tokens = await _server.refresh(refreshToken);
    await _local.saveAccessToken(tokens.accessToken);
    return TokenPair(
      accessToken: tokens.accessToken,
      refreshToken: refreshToken,
    );
  }

  // --- Profile ---

  /// Get the current user's profile.
  Future<UserModel> getMe() => _local.getMe();

  /// Update the current user's profile.
  Future<UserModel> updateProfile({String? firstName, String? lastName}) =>
      _local.updateProfile(firstName: firstName, lastName: lastName);

  /// Delete the current user's account.
  Future<void> deleteAccount() => _local.deleteAccount();

  /// Logout by clearing stored tokens and everything tied to the account.
  ///
  /// Dropping the tokens alone left the reader's name, email, search history,
  /// queued requests and quiz history in the database, so the next person to
  /// open the app on a shared device saw them. [AppDatabase.wipeUserScopedData]
  /// clears the database side; [OfflineUserRepository.clearAll] drops the
  /// passwords held in secure storage for registrations still awaiting sync.
  ///
  /// Public content and per-story reading position are kept, so the library
  /// still works offline for whoever signs in next.
  ///
  /// Deliberately not the same path as [clearTokens]: a 401 is a recoverable
  /// expiry, and wiping a reader's offline state over a transient network
  /// error would be far worse than leaving it.
  Future<void> logout() async {
    // Tokens first: whatever the cleanup below does, the session must not
    // survive a sign-out, and each step is independent so one failure cannot
    // leave the rest undone.
    await _local.logout();
    await _offlineUsers.clearAll();
    await _database.wipeUserScopedData();
  }

  // --- Helpers ---

  Future<TokenPair> _localPair() async {
    // Local session: tokens are the synthetic markers held in secure storage.
    return TokenPair(
      accessToken: await _local.accessToken ?? '',
      refreshToken: await _local.refreshToken ?? '',
    );
  }

  bool _isServerUnreachable(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout;
  }
}
