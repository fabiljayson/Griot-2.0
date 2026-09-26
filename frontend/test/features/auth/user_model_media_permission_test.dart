import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/features/auth/models/user_model.dart';

/// The media endpoints let any signed-in user render a *published* story and
/// reserve drafts for the author and the managing roles. The client gate must
/// agree, otherwise the UI either hides a working action or offers one that
/// can only ever 403.
void main() {
  UserModel userWithRole(UserRole role, {int id = 1}) => UserModel(
    id: id,
    username: 'user$id',
    role: role,
  );

  group('UserModel.canGenerateMediaFor', () {
    test('should let any signed-in user generate for a published story', () {
      final reader = userWithRole(UserRole.visitor);

      expect(
        reader.canGenerateMediaFor(authorId: 99, isPublished: true),
        isTrue,
      );
    });

    test('should let any signed-in user generate for their own draft', () {
      final author = userWithRole(UserRole.visitor, id: 7);

      expect(author.canGenerateMediaFor(authorId: 7, isPublished: false), isTrue);
    });

    test('should block a non-author from someone else\'s draft', () {
      final reader = userWithRole(UserRole.visitor, id: 7);

      expect(
        reader.canGenerateMediaFor(authorId: 99, isPublished: false),
        isFalse,
      );
    });

    test('should let managers and admins into any story', () {
      for (final role in [UserRole.institutionManager, UserRole.admin]) {
        expect(
          userWithRole(role, id: 7).canGenerateMediaFor(
            authorId: 99,
            isPublished: false,
          ),
          isTrue,
          reason: '$role should be allowed',
        );
      }
    });

    test('should not require the contributor role', () {
      // The API has no such requirement; gating on it hid the feature from
      // ordinary visitors of published stories.
      expect(userWithRole(UserRole.visitor).canContribute, isFalse);
      expect(
        userWithRole(UserRole.visitor).canGenerateMediaFor(
          authorId: 99,
          isPublished: true,
        ),
        isTrue,
      );
    });

    test('should default to closed when publication is unspecified', () {
      expect(
        userWithRole(UserRole.visitor, id: 7).canGenerateMediaFor(authorId: 99),
        isFalse,
      );
    });
  });
}
