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
      serverUserId: 11,
      username: 'nova',
      email: 'nova@example.com',
      firstName: 'Nova',
      lastName: 'Kuma',
      role: UserRole.contributor,
      institution: '',
      password: 'secret123',
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
        when(() => server.login(username: 'nova', password: 'secret123'))
            .thenAnswer((_) async => _realTokens);
        when(() => server.me('eyJ.access.1')).thenAnswer(
          (_) async => _profileJson,
        );

        final tokens = await repo.login(
          username: 'nova',
          password: 'secret123',
        );

        expect(tokens.accessToken, 'eyJ.access.1');
        expect(tokens.refreshToken, 'eyJ.refresh.1');
        verify(
          () => local.saveRemoteSession(
            serverUserId: 11,
            username: 'nova',
            email: 'nova@example.com',
            firstName: 'Nova',
            lastName: 'Kuma',
            role: UserRole.contributor,
            institution: '',
            password: 'secret123',
            accessToken: 'eyJ.access.1',
            refreshToken: 'eyJ.refresh.1',
          ),
        ).called(1);
      },
    );

    test('should fall back to the local account when offline', () async {
      when(() => server.login(username: 'nova', password: 'secret123'))
          .thenThrow(_dio(type: DioExceptionType.connectionError));
      when(() => local.login(username: 'nova', password: 'secret123'))
          .thenAnswer((_) async => const UserModel(id: 5, username: 'nova'));
      when(() => local.accessToken).thenAnswer((_) async => 'local_token_5');
      when(() => local.refreshToken).thenAnswer((_) async => 'local_refresh_5');

      final tokens = await repo.login(username: 'nova', password: 'secret123');

      expect(tokens.accessToken, 'local_token_5');
      expect(tokens.refreshToken, 'local_refresh_5');
      verify(() => local.login(username: 'nova', password: 'secret123'))
          .called(1);
    });

    test('should surface invalid credentials on 401 with no local account',
        () async {
      when(() => server.login(username: 'nova', password: 'wrong'))
          .thenThrow(_dio(statusCode: 401));
      when(() => local.login(username: 'nova', password: 'wrong'))
          .thenThrow(Exception('Invalid username or password'));

      expect(
        () => repo.login(username: 'nova', password: 'wrong'),
        throwsA(isA<InvalidCredentialsException>()),
      );
    });

    test('should keep working on 401 when a matching local account exists',
        () async {
      when(() => server.login(username: 'nova', password: 'pass'))
          .thenThrow(_dio(statusCode: 401));
      when(() => local.login(username: 'nova', password: 'pass'))
          .thenAnswer((_) async => const UserModel(id: 5, username: 'nova'));
      when(() => local.accessToken).thenAnswer((_) async => 'local_token_5');
      when(() => local.refreshToken).thenAnswer((_) async => 'local_refresh_5');

      final tokens = await repo.login(username: 'nova', password: 'pass');

      expect(tokens.accessToken, 'local_token_5');
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
      when(() => server.login(username: 'nova', password: 'secret123'))
          .thenAnswer((_) async => _realTokens);

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
          serverUserId: 11,
          username: 'nova',
          email: 'nova@example.com',
          firstName: 'Nova',
          lastName: 'Kuma',
          role: UserRole.contributor,
          institution: '',
          password: 'secret123',
          accessToken: _realTokens.accessToken,
          refreshToken: _realTokens.refreshToken,
        ),
      ).called(1);
    });

    test('should rethrow a server unreachable error for the offline path',
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

    test('should refresh a real session and persist the new access token',
        () async {
      when(() => local.refreshToken).thenAnswer((_) async => 'eyJ.refresh.1');
      when(() => server.refresh('eyJ.refresh.1')).thenAnswer(
        (_) async => const TokenPair(
          accessToken: 'eyJ.access.2',
          refreshToken: 'eyJ.refresh.1',
        ),
      );
      when(() => local.saveAccessToken('eyJ.access.2')).thenAnswer((_) async {});

      final tokens = await repo.refreshTokens();

      expect(tokens.accessToken, 'eyJ.access.2');
      verify(() => local.saveAccessToken('eyJ.access.2')).called(1);
    });
  });
}