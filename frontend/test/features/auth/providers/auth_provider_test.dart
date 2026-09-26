import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/database/models/offline_user.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';
import 'package:griot_ai/features/auth/providers/auth_provider.dart';
import 'package:griot_ai/features/auth/repositories/auth_repository.dart';
import 'package:griot_ai/features/auth/repositories/offline_auth_repository.dart';

// --- Mocks ---

class MockAuthRepository extends Mock implements AuthRepository {}

class MockOfflineAuthRepository extends Mock implements OfflineAuthRepository {}

// --- Helpers ---

const _fakeUser = UserModel(id: 1, username: 'tester', role: UserRole.visitor);
const _tokenPair = TokenPair(accessToken: 'access', refreshToken: 'refresh');

void main() {
  setUpAll(() {
    registerFallbackValue(const AuthState());
    registerFallbackValue(UserRole.visitor);
  });

  group('AuthNotifier', () {
    late MockAuthRepository mockRepo;
    late MockOfflineAuthRepository mockOfflineRepo;
    late ProviderContainer container;

    setUp(() {
      mockRepo = MockAuthRepository();
      mockOfflineRepo = MockOfflineAuthRepository();
      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(mockRepo),
          offlineAuthProvider.overrideWithValue(mockOfflineRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    AuthState? readState() => container.read(authProvider).value;

    // --- Build (session check) ---

    test('should be unauthenticated when no session exists', () async {
      when(() => mockRepo.isAuthenticated).thenAnswer((_) async => false);

      await container.read(authProvider.future);

      expect(readState()?.status, AuthStatus.unauthenticated);
    });

    test('should be authenticated when valid session exists', () async {
      when(() => mockRepo.isAuthenticated).thenAnswer((_) async => true);
      when(() => mockRepo.getMe()).thenAnswer((_) async => _fakeUser);

      await container.read(authProvider.future);

      expect(readState()?.status, AuthStatus.authenticated);
      expect(readState()?.user?.username, 'tester');
    });

    test('should fallback to unauthenticated when getMe fails', () async {
      when(() => mockRepo.isAuthenticated).thenAnswer((_) async => true);
      when(() => mockRepo.getMe()).thenThrow(Exception('expired'));
      when(() => mockRepo.refreshTokens())
          .thenAnswer((_) async => _tokenPair);
      when(() => mockRepo.clearTokens()).thenAnswer((_) async {});

      await container.read(authProvider.future);

      expect(readState()?.status, AuthStatus.unauthenticated);
    });

    // --- Login ---

    test('should login successfully', () async {
      when(() => mockRepo.isAuthenticated).thenAnswer((_) async => false);
      when(() => mockRepo.login(
            username: any(named: 'username'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => _tokenPair);
      when(() => mockRepo.getMe()).thenAnswer((_) async => _fakeUser);

      await container.read(authProvider.future);

      await container
          .read(authProvider.notifier)
          .login(username: 'tester', password: 'pass123');

      expect(readState()?.status, AuthStatus.authenticated);
      expect(readState()?.user?.username, 'tester');
    });

    test('should set error state on login failure', () async {
      when(() => mockRepo.isAuthenticated).thenAnswer((_) async => false);
      when(() => mockRepo.login(
            username: any(named: 'username'),
            password: any(named: 'password'),
          )).thenThrow(Exception('Invalid credentials'));

      await container.read(authProvider.future);

      await container
          .read(authProvider.notifier)
          .login(username: 'tester', password: 'wrong');

      expect(readState()?.status, AuthStatus.error);
      expect(readState()?.errorMessage, isNotNull);
    });

    // --- Logout ---

    test('should logout and return to unauthenticated', () async {
      when(() => mockRepo.isAuthenticated).thenAnswer((_) async => true);
      when(() => mockRepo.getMe()).thenAnswer((_) async => _fakeUser);
      when(() => mockRepo.logout()).thenAnswer((_) async {});

      await container.read(authProvider.future);
      expect(readState()?.status, AuthStatus.authenticated);

      await container.read(authProvider.notifier).logout();

      expect(readState()?.status, AuthStatus.unauthenticated);
    });

    // --- Register ---

    group('register', () {
      test(
          'should not queue an offline registration when the account already '
          'exists on the server', () async {
        when(() => mockRepo.isAuthenticated).thenAnswer((_) async => false);
        await container.read(authProvider.future);

        when(() => mockRepo.register(
              username: any(named: 'username'),
              email: any(named: 'email'),
              password: any(named: 'password'),
              firstName: any(named: 'firstName'),
              lastName: any(named: 'lastName'),
              role: any(named: 'role'),
            )).thenThrow(
          RegistrationSignInFailedException(user: _fakeUser),
        );

        final status = await container
            .read(authProvider.notifier)
            .register(username: 'tester', email: 'tester@example.com', password: 'pass123');

        expect(status, AuthStatus.error);
        verifyNever(() => mockOfflineRepo.register(
              username: any(named: 'username'),
              email: any(named: 'email'),
              password: any(named: 'password'),
              firstName: any(named: 'firstName'),
              lastName: any(named: 'lastName'),
              role: any(named: 'role'),
            ));
        expect(readState()?.status, isNot(AuthStatus.pendingSync));
        expect(
          readState()?.errorMessage,
          allOf(contains('already created'), contains('Sign in')),
        );
        expect(readState()?.errorMessage, isNot(contains('Exception:')));
      });

      test('should queue an offline registration when the server is unreachable',
          () async {
        when(() => mockRepo.isAuthenticated).thenAnswer((_) async => false);
        await container.read(authProvider.future);

        when(() => mockRepo.register(
              username: any(named: 'username'),
              email: any(named: 'email'),
              password: any(named: 'password'),
              firstName: any(named: 'firstName'),
              lastName: any(named: 'lastName'),
              role: any(named: 'role'),
            )).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/api/auth/register/'),
            type: DioExceptionType.connectionError,
          ),
        );
        when(() => mockOfflineRepo.register(
              username: any(named: 'username'),
              email: any(named: 'email'),
              password: any(named: 'password'),
              firstName: any(named: 'firstName'),
              lastName: any(named: 'lastName'),
              role: any(named: 'role'),
            )).thenAnswer((_) async => const OfflineUser(
              username: 'tester',
              email: 'tester@example.com',
              password: 'pass123',
            ));

        final status = await container
            .read(authProvider.notifier)
            .register(username: 'tester', email: 'tester@example.com', password: 'pass123');

        expect(status, AuthStatus.pendingSync);
        expect(readState()?.status, AuthStatus.pendingSync);
      });
    });

    // --- Clear error ---

    test('clearError should reset error state', () async {
      when(() => mockRepo.isAuthenticated).thenAnswer((_) async => false);
      await container.read(authProvider.future);

      when(() => mockRepo.login(
            username: any(named: 'username'),
            password: any(named: 'password'),
          )).thenThrow(Exception('fail'));

      await container
          .read(authProvider.notifier)
          .login(username: 'x', password: 'y');
      expect(readState()?.status, AuthStatus.error);

      container.read(authProvider.notifier).clearError();
      // Wait for state propagation
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final afterClear = readState();
      expect(afterClear?.status, AuthStatus.unauthenticated);
      expect(afterClear?.errorMessage, isNull);
    });
  });
}
