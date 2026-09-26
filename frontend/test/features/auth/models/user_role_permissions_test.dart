import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/auth/models/user_model.dart';

/// Locks the client-side mirror of the backend's media-generation gate.
///
/// The API opens generation on any **published** story to every signed-in
/// user, and reserves drafts for the author and the managing roles
/// (`media_app/views.py::VideoGenerationViewSet.create`). The client gate has
/// to agree in both directions: stricter and it hides a working action,
/// looser and it offers one that can only ever 403.
void main() {
  UserModel userFor(UserRole role, {int id = 1}) =>
      UserModel(id: id, username: 'amara', role: role);

  const ownStoryAuthorId = 1;
  const someoneElse = 99;

  group('canContribute', () {
    test('is false for a Visitor and true from Contributor upwards', () {
      expect(userFor(UserRole.visitor).canContribute, isFalse);
      expect(userFor(UserRole.contributor).canContribute, isTrue);
      expect(userFor(UserRole.institutionManager).canContribute, isTrue);
      expect(userFor(UserRole.admin).canContribute, isTrue);
    });
  });

  group('canGenerateMediaFor', () {
    test('Visitor may generate media for a published story', () {
      expect(
        userFor(UserRole.visitor).canGenerateMediaFor(
          authorId: someoneElse,
          isPublished: true,
        ),
        isTrue,
        reason: 'a published story is open to every signed-in user',
      );
    });

    test('Visitor may not generate media for another author\'s draft', () {
      expect(
        userFor(UserRole.visitor).canGenerateMediaFor(
          authorId: someoneElse,
          isPublished: false,
        ),
        isFalse,
      );
    });

    test('any role may generate media for their own story', () {
      for (final role in UserRole.values) {
        expect(
          userFor(role).canGenerateMediaFor(
            authorId: ownStoryAuthorId,
            isPublished: false,
          ),
          isTrue,
          reason: '$role owns their own story, draft or not',
        );
      }
    });

    test('Contributor may not generate media for another author\'s draft', () {
      expect(
        userFor(UserRole.contributor).canGenerateMediaFor(
          authorId: someoneElse,
          isPublished: false,
        ),
        isFalse,
        reason: 'a draft stays private until it is published',
      );
    });

    test('Manager and Admin may generate media for any story', () {
      for (final role in [UserRole.institutionManager, UserRole.admin]) {
        final user = userFor(role);
        expect(
          user.canGenerateMediaFor(authorId: ownStoryAuthorId),
          isTrue,
          reason: '${role.label} owns their own story',
        );
        expect(
          user.canGenerateMediaFor(
            authorId: someoneElse,
            isPublished: false,
          ),
          isTrue,
          reason: '${role.label} may act as moderator on any story',
        );
      }
    });
  });
}
