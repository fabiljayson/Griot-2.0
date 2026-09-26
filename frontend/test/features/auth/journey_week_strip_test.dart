import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/auth/widgets/profile/journey_block.dart';

/// The week strip is the one place the profile asserts *which days* the reader
/// was present, so it has to be derived from the real last active day. Two bugs
/// are pinned here, both of which showed activity that never happened:
///
///  1. lighting the last N weekday slots up to today, regardless of the stored
///     `last_active_date`, so a run that ended three weeks ago still looked
///     current;
///  2. mixing a weekday index with a count of days, so on a Monday a three-day
///     streak lit Tuesday and Wednesday — days that had not happened yet.
void main() {
  // A Wednesday, so the week is mid-way and bug 2 is at its most visible.
  final now = DateTime(2026, 3, 11, 9);

  List<bool> lit({
    required int streak,
    required DateTime? lastActive,
  }) => WeekStrip.litDays(
        streak: streak,
        lastActiveDate: lastActive,
        now: now,
      );

  group('WeekStrip.litDays', () {
    test('marks only the seven days ending today', () {
      // 2026-03-05 .. 2026-03-11
      expect(lit(streak: 3, lastActive: now), [
        false,
        false,
        false,
        false,
        true,
        true,
        true,
      ]);
    });

    test('a live run lights its last active day, not today', () {
      // Active yesterday, today not yet logged: the run is alive but at risk.
      expect(lit(streak: 3, lastActive: now.subtract(const Duration(days: 1))), [
        false,
        false,
        false,
        true,
        true,
        true,
        false,
      ]);
    });

    test('a stale run lights nothing', () {
      // Three-week-old run. The old implementation lit the last three slots,
      // which claimed the reader had been here this week.
      expect(
        lit(streak: 3, lastActive: now.subtract(const Duration(days: 21))),
        everyElement(isFalse),
      );
    });

    test('a missed run reports a streak of zero and lights nothing', () {
      expect(
        lit(streak: 0, lastActive: now),
        everyElement(isFalse),
      );
    });

    test('a never-active reader lights nothing', () {
      expect(lit(streak: 0, lastActive: null), everyElement(isFalse));
    });

    test('a run longer than the window fills it without overflowing', () {
      expect(
        lit(streak: 30, lastActive: now),
        everyElement(isTrue),
      );
    });

    test('a future last active date does not light today', () {
      // Clock skew, or a profile written by a server in a different zone. The
      // strip must not claim a day that has not happened.
      expect(
        lit(streak: 5, lastActive: now.add(const Duration(days: 2))),
        everyElement(isFalse),
      );
    });

    test('ignores the time of day on the last active date', () {
      // The backend stores a date, but a client that sends a datetime must not
      // shift the boundary by its clock value.
      final lateLastNight = DateTime(2026, 3, 10, 23, 59);
      expect(
        WeekStrip.litDays(
          streak: 2,
          lastActiveDate: lateLastNight,
          now: now,
        ),
        [false, false, false, false, true, true, false],
      );
    });
  });

  group('WeekStrip widget', () {
    testWidgets('labels each slot with its own weekday, ending today', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WeekStrip(streak: 1, lastActiveDate: null, activeToday: false),
          ),
        ),
      );

      // The widget reads the real clock, so the expectation is derived from it
      // rather than hard-coded to a date this test would eventually outlive.
      const initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      final today = DateTime.now();
      final expected = [
        for (var offset = 6; offset >= 0; offset--)
          initials[
              today.subtract(Duration(days: offset)).weekday - 1],
      ];

      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .toList();

      expect(labels, expected);
      expect(labels.last, initials[today.weekday - 1]);
    });
  });
}
