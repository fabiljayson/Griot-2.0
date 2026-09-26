import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/notifications/models/notification_model.dart';

/// The inbox is server-authored, so parsing is the only place a message can be
/// misrepresented. These pin the defensive defaults: a partial payload must
/// degrade, never crash the list.
void main() {
  group('NotificationModel.fromJson', () {
    test('reads a complete message', () {
      final model = NotificationModel.fromJson({
        'id': 12,
        'kind': 'new_story',
        'title': 'A new story has arrived',
        'body': 'The Sacred Forest of Foreke-Dschang',
        'story': 4,
        'story_title': 'The Sacred Forest of Foreke-Dschang',
        'story_slug': 'the-sacred-forest-of-foreke-dschang',
        'is_read': false,
        'created_at': '2026-03-11T09:30:00Z',
      });

      expect(model.id, 12);
      expect(model.kind, NotificationKind.newStory);
      expect(model.storyId, 4);
      expect(model.storySlug, 'the-sacred-forest-of-foreke-dschang');
      expect(model.isRead, isFalse);
      expect(model.hasStory, isTrue);
      expect(model.createdAt.isUtc, isFalse, reason: 'rendered in local time');
    });

    test('an announcement has no story and says so', () {
      final model = NotificationModel.fromJson({
        'id': 3,
        'kind': 'announcement',
        'title': 'Scheduled maintenance',
        'body': 'Tonight at 22:00.',
        'story': null,
        'story_title': null,
        'story_slug': null,
        'is_read': true,
        'created_at': '2026-03-11T09:30:00Z',
      });

      expect(model.hasStory, isFalse);
      expect(model.storySlug, isEmpty);
    });

    test('falls back rather than throwing on a sparse payload', () {
      final model = NotificationModel.fromJson({'id': 7});

      expect(model.id, 7);
      expect(model.kind, NotificationKind.system);
      expect(model.title, isEmpty);
      expect(model.body, isEmpty);
      expect(model.isRead, isFalse);
      expect(model.hasStory, isFalse);
    });

    test('an unread message that is not marked read reads as unread', () {
      // The default has to be the safe-for-attention state: a missing key must
      // not silently mark someone's message as dealt with.
      final model = NotificationModel.fromJson({'id': 8, 'is_read': null});

      expect(model.isRead, isFalse);
    });

    test('an unparsable timestamp does not break the row', () {
      final model = NotificationModel.fromJson({
        'id': 9,
        'created_at': 'not-a-date',
      });

      expect(model.id, 9);
    });
  });

  group('NotificationModel.copyWith', () {
    test('marks read without touching anything else', () {
      final original = NotificationModel.fromJson({
        'id': 4,
        'kind': 'trending',
        'title': 'This week in stories',
        'body': 'The one everyone finished',
        'story_slug': 'a-tale',
        'is_read': false,
        'created_at': '2026-03-11T09:30:00Z',
      });

      final read = original.copyWith(isRead: true);

      expect(read.isRead, isTrue);
      expect(read.id, original.id);
      expect(read.title, original.title);
      expect(read.body, original.body);
      expect(read.storySlug, original.storySlug);
      expect(read.createdAt, original.createdAt);
    });
  });

  group('NotificationKind', () {
    test('covers every kind the API can send', () {
      // A new server-side kind must not silently fall through to the system
      // glyph, so the constants are asserted individually.
      expect(NotificationKind.newStory, isNotEmpty);
      expect(NotificationKind.trending, isNotEmpty);
      expect(NotificationKind.streak, isNotEmpty);
      expect(NotificationKind.badge, isNotEmpty);
      expect(NotificationKind.announcement, isNotEmpty);
      expect(NotificationKind.system, isNotEmpty);
    });
  });
}
