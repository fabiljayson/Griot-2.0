import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/auth/models/user_model.dart';

/// Locks the client-side mirror of the backend's media-generation gate.
///
/// The API requires Contributor-or-above **and** either authorship or a
/// manager/admin role (`web/views.py::can_generate_media`,
/// `media_app/views.py::VideoGenerationViewSet.create`). Role alone is not
/// enough, which is why the story menu hides the entry on another author's
/// story: it could only ever 403.
void main() {
  UserModel userFor(UserRole role, {int id = 1}) =>
      UserModel(id: id, username: 'amara', role: role);

  const ownStoryAuthorId = 1;

  group('canContribute', () {
    test('is false for a Visitor and true from Contributor upwards', () {
      expect(userFor(UserRole.visitor).canContribute, isFalse);
      expect(userFor(UserRole.contributor).canContribute, isTrue);
      expect(userFor(UserRole.institutionManager).canContribute, isTrue);
      expect(userFor(UserRole.admin).canContribute, isTrue);
    });
  });

  group('canGenerateMediaFor', () {
    test('Visitor may never generate media, even on their own story', () {
      expect(
        userFor(
          UserRole.visitor,
        ).canGenerateMediaFor(authorId: ownStoryAuthorId),
        isFalse,
      );
    });

    test('Contributor may generate media only for their own story', () {
      final contributor = userFor(UserRole.contributor);

      expect(
        contributor.canGenerateMediaFor(authorId: ownStoryAuthorId),
        isTrue,
        reason: 'a Contributor owns their own submissions',
      );
      expect(
        contributor.canGenerateMediaFor(authorId: 99),
        isFalse,
        reason: 'role alone is not sufficient — ownership is also required',
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
          user.canGenerateMediaFor(authorId: 99),
          isTrue,
          reason: '${role.label} may act as moderator on any story',
        );
      }
    });
  });
}
