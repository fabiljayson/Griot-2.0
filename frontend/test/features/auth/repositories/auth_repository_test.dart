import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/database/app_database.dart';
import 'package:griot_ai/core/database/repositories/local_auth_repository.dart';
import 'package:griot_ai/core/database/repositories/offline_user_repository.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/auth/repositories/auth_repository.dart';
import 'package:griot_ai/features/auth/repositories/server_auth_repository.dart';

class _MockServer extends Mock implements ServerAuthRepository {}

class _MockLocal extends Mock implements LocalAuthRepository {}

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockOfflineUsers extends Mock implements OfflineUserRepository {}

RequestOptions _options() => RequestOptions(path: '/api/auth/token/');

DioException _dio({
  int? statusCode,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  return DioException(
    requestOptions: _options(),
    type: type,
    response: statusCode == null
        ? null
        : Response(requestOptions: _options(), statusCode: statusCode),
  );
}

const _profileJson = {
  'id': 11,
  'username': 'nova',
  'email': 'nova@example.com',
  'first_name': 'Nova',
  'last_name': 'Kuma',
  'role': 'contributor',
  'role_display': 'Contributor',
  'institution': '',
  'date_joined': '2026-09-22T00:00:00Z',
};

const _realTokens = TokenPair(
  accessToken: 'eyJ.access.1',
  refreshToken: 'eyJ.refresh.1',
);

void _stubSaveRemoteSession(_MockLocal local) {
  when(
    () => local.saveRemoteSession(
      username: 'nova',
      email: 'nova@example.com',
      firstName: 'Nova',
      lastName: 'Kuma',
      role: UserRole.contributor,
      institution: '',
      accessToken: 'eyJ.access.1',
      refreshToken: 'eyJ.refresh.1',
    ),
  ).thenAnswer((_) async {});
}

void main() {
  late _MockServer server;
  late _MockLocal local;
  late AuthRepository repo;

  setUp(() {
    server = _MockServer();
    local = _MockLocal();
    repo = AuthRepository(localAuth: local, server: server);
  });

  group('login', () {
    test(
      'should persist a real session and return the JWT pair when online',
      () async {
        _stubSaveRemoteSession(local);
        when(
          () => server.login(username: 'nova', password: 'secret123'),
        ).thenAnswer((_) async => _realTokens);
        when(
          () => server.me('eyJ.access.1'),
        ).thenAnswer((_) async => _profileJson);

        final tokens = await repo.login(
          username: 'nova',
          password: 'secret123',
        );

        expect(tokens.accessToken, 'eyJ.access.1');
        expect(tokens.refreshToken, 'eyJ.refresh.1');
        verify(
          () => local.saveRemoteSession(
            username: 'nova',
            email: 'nova@example.com',
            firstName: 'Nova',
            lastName: 'Kuma',
            role: UserRole.contributor,
            institution: '',
            accessToken: 'eyJ.access.1',
            refreshToken: 'eyJ.refresh.1',
          ),
        ).called(1);
      },
    );

    test(
      'should surface server connection errors without local login',
      () async {
        when(
          () => server.login(username: 'nova', password: 'secret123'),
        ).thenThrow(_dio(type: DioExceptionType.connectionError));

        await expectLater(
          repo.login(username: 'nova', password: 'secret123'),
          throwsA(isA<DioException>()),
        );

        verifyNever(() => local.login(username: 'nova', password: 'secret123'));
      },
    );

    test(
      'should surface invalid credentials on 401 with no local account',
      () async {
        when(
          () => server.login(username: 'nova', password: 'wrong'),
        ).thenThrow(_dio(statusCode: 401));
        when(() => local.clearTokens()).thenAnswer((_) async {});

        expect(
          () => repo.login(username: 'nova', password: 'wrong'),
          throwsA(isA<InvalidCredentialsException>()),
        );
      },
    );

    test('a 401 must not be rescued by a matching local account, so a revoked '
        'server account cannot keep signing in on a cached device', () async {
      when(
        () => server.login(username: 'nova', password: 'pass'),
      ).thenThrow(_dio(statusCode: 401));
      when(
        () => local.login(username: 'nova', password: 'pass'),
      ).thenAnswer((_) async => const UserModel(id: 5, username: 'nova'));
      when(() => local.clearTokens()).thenAnswer((_) async {});

      await expectLater(
        repo.login(username: 'nova', password: 'pass'),
        throwsA(isA<InvalidCredentialsException>()),
      );

      // The local credential is never consulted, so a cached offline account
      // cannot override the server's refusal.
      verifyNever(() => local.login(username: 'nova', password: 'pass'));
    });

    test('a 401 clears any cached session for the rejected user', () async {
      when(
        () => server.login(username: 'nova', password: 'pass'),
      ).thenThrow(_dio(statusCode: 401));
      when(() => local.clearTokens()).thenAnswer((_) async {});

      await expectLater(
        repo.login(username: 'nova', password: 'pass'),
        throwsA(isA<InvalidCredentialsException>()),
      );

      verify(() => local.clearTokens()).called(1);
    });
  });

  group('register', () {
    test('should create the account and persist the real session', () async {
      _stubSaveRemoteSession(local);
      when(
        () => server.register(
          username: 'nova',
          email: 'nova@example.com',
          password: 'secret123',
          firstName: 'Nova',
          lastName: 'Kuma',
          role: UserRole.contributor,
        ),
      ).thenAnswer((_) async => _profileJson);
      when(
        () => server.login(username: 'nova', password: 'secret123'),
      ).thenAnswer((_) async => _realTokens);

      final user = await repo.register(
        username: 'nova',
        email: 'nova@example.com',
        password: 'secret123',
        firstName: 'Nova',
        lastName: 'Kuma',
        role: UserRole.contributor,
      );

      expect(user.id, 11);
      expect(user.role, UserRole.contributor);
      verify(
        () => local.saveRemoteSession(
          username: 'nova',
          email: 'nova@example.com',
          firstName: 'Nova',
          lastName: 'Kuma',
          role: UserRole.contributor,
          institution: '',
          accessToken: _realTokens.accessToken,
          refreshToken: _realTokens.refreshToken,
        ),
      ).called(1);
    });

    test(
      'should surface server connection errors without local registration',
      () async {
        when(
          () => server.register(
            username: 'nova',
            email: 'nova@example.com',
            password: 'secret123',
            firstName: '',
            lastName: '',
            role: UserRole.visitor,
          ),
        ).thenThrow(_dio(type: DioExceptionType.connectionError));

        expect(
          () => repo.register(
            username: 'nova',
            email: 'nova@example.com',
            password: 'secret123',
          ),
          throwsA(isA<DioException>()),
        );
      },
    );

    test('should report a sign-in failure, not an unreachable server, when the '
        'account was already created', () async {
      when(
        () => server.register(
          username: 'nova',
          email: 'nova@example.com',
          password: 'secret123',
          firstName: 'Nova',
          lastName: 'Kuma',
          role: UserRole.contributor,
        ),
      ).thenAnswer((_) async => _profileJson);
      when(
        () => server.login(username: 'nova', password: 'secret123'),
      ).thenThrow(_dio(type: DioExceptionType.receiveTimeout));

      await expectLater(
        repo.register(
          username: 'nova',
          email: 'nova@example.com',
          password: 'secret123',
          firstName: 'Nova',
          lastName: 'Kuma',
          role: UserRole.contributor,
        ),
        throwsA(
          isA<RegistrationSignInFailedException>()
              .having((e) => e.user.email, 'email', 'nova@example.com')
              .having((e) => e.cause, 'cause', isA<DioException>()),
        ),
      );
    });
  });

  group('refreshTokens', () {
    test('should not call the server for synthetic tokens', () async {
      when(() => local.refreshToken).thenAnswer((_) async => 'local_refresh_5');
      when(() => local.refreshTokens()).thenAnswer((_) async {});
      when(() => local.accessToken).thenAnswer((_) async => 'local_token_5');

      final tokens = await repo.refreshTokens();

      verifyNever(() => server.refresh('local_refresh_5'));
      expect(tokens.accessToken, 'local_token_5');
    });

    test(
      'persists the rotated refresh token the server issues',
      () async {
        when(() => local.refreshToken).thenAnswer((_) async => 'eyJ.refresh.1');
        when(() => server.refresh('eyJ.refresh.1')).thenAnswer(
          (_) async => const TokenPair(
            accessToken: 'eyJ.access.2',
            refreshToken: 'eyJ.refresh.2',
          ),
        );
        when(
          () => local.saveTokenPair(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
          ),
        ).thenAnswer((_) async {});

        final tokens = await repo.refreshTokens();

        expect(tokens.accessToken, 'eyJ.access.2');
        expect(
          tokens.refreshToken,
          'eyJ.refresh.2',
          reason: 'the server blacklists the presented refresh token '
              '(ROTATE_REFRESH_TOKENS); returning the old one would '
              'guarantee a 401 on the next refresh',
        );
        verify(
          () => local.saveTokenPair(
            accessToken: 'eyJ.access.2',
            refreshToken: 'eyJ.refresh.2',
          ),
        ).called(1);
        verifyNever(() => local.saveAccessToken(any()));
      },
    );

    test(
      'keeps the current refresh token when the server does not rotate',
      () async {
        when(() => local.refreshToken).thenAnswer((_) async => 'eyJ.refresh.1');
        when(() => server.refresh('eyJ.refresh.1')).thenAnswer(
          (_) async => const TokenPair(
            accessToken: 'eyJ.access.2',
            refreshToken: '',
          ),
        );
        when(
          () => local.saveTokenPair(
            accessToken: any(named: 'accessToken'),
            refreshToken: any(named: 'refreshToken'),
          ),
        ).thenAnswer((_) async {});

        final tokens = await repo.refreshTokens();

        expect(tokens.refreshToken, 'eyJ.refresh.1');
        verify(
          () => local.saveTokenPair(
            accessToken: 'eyJ.access.2',
            refreshToken: 'eyJ.refresh.1',
          ),
        ).called(1);
      },
    );
  });

  group('logout', () {
    late _MockAppDatabase database;
    late _MockOfflineUsers offlineUsers;
    late AuthRepository repo;

    setUp(() {
      database = _MockAppDatabase();
      offlineUsers = _MockOfflineUsers();
      repo = AuthRepository(
        localAuth: local,
        server: server,
        database: database,
        offlineUsers: offlineUsers,
      );

      when(() => local.logout()).thenAnswer((_) async {});
      when(() => offlineUsers.clearAll()).thenAnswer((_) async {});
      when(() => database.wipeUserScopedData()).thenAnswer((_) async {});
    });

    test(
      'revokes the refresh token server-side before clearing local state',
      () async {
        when(() => local.refreshToken)
            .thenAnswer((_) async => 'eyJ.refresh.1');
        when(() => server.logout('eyJ.refresh.1')).thenAnswer((_) async {});

        await repo.logout();

        // Revocation has to happen while the token still exists locally —
        // clearing first throws away the only credential that can blacklist
        // it. Verify the order, not just the calls.
        verifyInOrder([
          () => server.logout('eyJ.refresh.1'),
          () => local.logout(),
        ]);
        verify(() => offlineUsers.clearAll()).called(1);
        verify(() => database.wipeUserScopedData()).called(1);
      },
    );

    test('skips the server call for synthetic offline sessions', () async {
      when(() => local.refreshToken).thenAnswer((_) async => 'local_refresh_7');

      await repo.logout();

      verifyNever(() => server.logout(any()));
      verify(() => local.logout()).called(1);
    });

    test('skips the server call when there is no token to revoke', () async {
      when(() => local.refreshToken).thenAnswer((_) async => null);

      await repo.logout();

      verifyNever(() => server.logout(any()));
      verify(() => local.logout()).called(1);
    });

    test(
      'still signs the reader out when the revocation request fails',
      () async {
        when(() => local.refreshToken)
            .thenAnswer((_) async => 'eyJ.refresh.1');
        when(() => server.logout(any())).thenAnswer(
          (_) async => throw DioException(
            requestOptions: RequestOptions(path: '/api/auth/logout/'),
            type: DioExceptionType.connectionError,
          ),
        );

        await repo.logout();

        // Offline logout must not strand the reader in a signed-in UI with
        // dead tokens; the token simply expires server-side instead.
        verify(() => local.logout()).called(1);
        verify(() => offlineUsers.clearAll()).called(1);
        verify(() => database.wipeUserScopedData()).called(1);
      },
    );
  });
}
