import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/database/repositories/local_auth_repository.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/auth/repositories/auth_repository.dart';
import 'package:griot_ai/features/auth/repositories/server_auth_repository.dart';

class _MockServer extends Mock implements ServerAuthRepository {}

class _MockLocal extends Mock implements LocalAuthRepository {}

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
      'should refresh a real session and persist the new access token',
      () async {
        when(() => local.refreshToken).thenAnswer((_) async => 'eyJ.refresh.1');
        when(() => server.refresh('eyJ.refresh.1')).thenAnswer(
          (_) async => const TokenPair(
            accessToken: 'eyJ.access.2',
            refreshToken: 'eyJ.refresh.1',
          ),
        );
        when(
          () => local.saveAccessToken('eyJ.access.2'),
        ).thenAnswer((_) async {});

        final tokens = await repo.refreshTokens();

        expect(tokens.accessToken, 'eyJ.access.2');
        verify(() => local.saveAccessToken('eyJ.access.2')).called(1);
      },
    );
  });
}
