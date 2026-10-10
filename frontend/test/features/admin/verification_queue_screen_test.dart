import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/admin/models/verification_models.dart';
import 'package:griot_ai/features/admin/providers/admin_provider.dart';
import 'package:griot_ai/features/admin/screens/verification_queue_screen.dart';
import 'package:griot_ai/features/admin/services/admin_api_service.dart';

import '../../support/admin_fixtures.dart';

/// Captures what the screen asked to record, so the tests assert on the
/// decision the reviewer actually expressed rather than on a network call.
class RecordingVerificationNotifier extends VerificationActionNotifier {
  RecordingVerificationNotifier({this.shouldFail = false})
      : super(
          // The methods are overridden below, so the client is never
          // exercised; the constructor still requires one to keep production
          // wiring explicit (the bare singleton carries no auth interceptor).
          AdminApiService(dio: Dio()),
        );

  final bool shouldFail;
  final decisions = <Map<String, Object?>>[];
  final sourceToggles = <Map<String, Object?>>[];

  @override
  Future<bool> decide({
    required String slug,
    required VerifyAction action,
    String notes = '',
    Map<String, dynamic>? evidence,
  }) async {
    decisions.add({
      'slug': slug,
      'action': action,
      'notes': notes,
      'evidence': evidence,
    });
    return !shouldFail;
  }

  @override
  Future<bool> confirmSource({
    required String slug,
    required int sourceId,
    bool isVerified = true,
  }) async {
    sourceToggles.add({
      'slug': slug,
      'sourceId': sourceId,
      'isVerified': isVerified,
    });
    return !shouldFail;
  }
}

Future<RecordingVerificationNotifier> pumpQueue(
  WidgetTester tester, {
  List<VerificationQueueEntry>? queue,
  bool shouldFail = false,
}) async {
  final notifier = RecordingVerificationNotifier(shouldFail: shouldFail);
  final stories = queue ??
      adminVerificationQueueJson()
          .map(VerificationQueueEntry.fromJson)
          .toList();

  // The evidence checklists and source rows need more than the 600px default
  // surface.
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verificationQueueProvider.overrideWith((ref) async => stories),
        verificationActionProvider.overrideWith((ref) => notifier),
      ],
      child: const MaterialApp(home: VerificationQueueScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  testWidgets('lists every story awaiting verification', (tester) async {
    await pumpQueue(tester);

    expect(find.text('The Baobab and the Drum'), findsOneWidget);
    expect(find.text('A Tale Without a Source'), findsOneWidget);
    expect(find.text('2 stories await verification'), findsOneWidget);
  });

  testWidgets('shows the evidence checklist with the score it produces', (
    tester,
  ) async {
    await pumpQueue(tester);

    // The levers behind the number have to be visible where the number is:
    // a reviewer approving from a score alone has not reviewed anything.
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Partially verified'), findsOneWidget);
    expect(find.text('Unverified'), findsWidgets);
    expect(find.text('Reliable/documented source'), findsNWidgets(2));
    expect(find.text('Cultural expert/reviewer validation'), findsNWidgets(2));
    // Three 25-point criteria per card, two cards.
    expect(find.text('+25'), findsNWidgets(6));
    expect(find.text('+15'), findsNWidgets(2));
    expect(find.text('+10'), findsNWidgets(2));
  });

  testWidgets('shows the declared provenance the decision is about', (
    tester,
  ) async {
    await pumpQueue(tester);

    expect(
      find.textContaining("Recorded in Foumban in 2019"),
      findsOneWidget,
    );
    expect(find.text('Seeded demonstration content.'), findsOneWidget);
    expect(find.text('In review by amina'), findsOneWidget);
  });

  testWidgets('shows sources with a confirm/undo control', (tester) async {
    await pumpQueue(tester);

    expect(find.text('Elder Njoya testimony'), findsOneWidget);
    expect(find.text('Tamara vol. II'), findsOneWidget);
    // The first source is already checked; the second is not, so the two
    // rows offer opposite controls.
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
  });

  testWidgets('confirming a source records which source and how', (
    tester,
  ) async {
    final notifier = await pumpQueue(tester);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(notifier.sourceToggles, hasLength(1));
    expect(notifier.sourceToggles.single['slug'], 'the-baobab-and-the-drum');
    expect(notifier.sourceToggles.single['sourceId'], 2);
    expect(notifier.sourceToggles.single['isVerified'], true);
  });

  testWidgets('undoing a verified source withdraws the check', (
    tester,
  ) async {
    final notifier = await pumpQueue(tester);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(notifier.sourceToggles.single['sourceId'], 1);
    expect(notifier.sourceToggles.single['isVerified'], false);
  });

  testWidgets('records an approval with the evidence it was based on', (
    tester,
  ) async {
    final notifier = await pumpQueue(tester);

    await tester.tap(find.text('Record decision').first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Approve'));
    await tester.pumpAndSettle();

    // Tick one previously-unconfirmed criterion; the two already confirmed
    // ones must not be re-sent as "changes".
    await tester.tap(
      find.widgetWithText(
        CheckboxListTile,
        'Cultural expert/reviewer validation',
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Reviewer notes'),
      'Elder confirmed the telling in person.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(notifier.decisions, hasLength(1));
    final decision = notifier.decisions.single;
    expect(decision['slug'], 'the-baobab-and-the-drum');
    expect(decision['action'], VerifyAction.approve);
    expect(decision['notes'], 'Elder confirmed the telling in person.');
    expect(decision['evidence'], {'expert_validated': true});
  });

  testWidgets('approving with no confirmed evidence is refused on screen', (
    tester,
  ) async {
    final notifier = await pumpQueue(tester);

    // The second story has nothing confirmed — approving it as-is is exactly
    // the zero-evidence record this workflow exists to prevent.
    await tester.tap(find.text('Record decision').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Approving needs at least one'), findsOneWidget);
    expect(notifier.decisions, isEmpty);
    // The sheet stays open: nothing was lost but the tap.
    expect(find.text('Record verification decision'), findsOneWidget);
  });

  testWidgets('warns that approving withheld consent will be refused', (
    tester,
  ) async {
    final queue = [
      VerificationQueueEntry.fromJson({
        ...adminVerificationQueueJson()[0],
        'consent_status': 'withheld',
        'trust_score': 0,
        // One criterion already confirmed, so the approval attempt reaches
        // the server-side consent rule rather than tripping the empty-
        // evidence guard first.
        'breakdown': [
          {
            'criterion': 'source_verified',
            'label': 'Reliable/documented source',
            'weight': 25,
            'confirmed': true,
          },
        ],
      }),
    ];
    final notifier = await pumpQueue(tester, queue: queue);

    await tester.tap(find.text('Record decision'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Approve'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('The community withheld consent'),
      findsOneWidget,
    );

    // The warning does not decide for the reviewer — the server refuses it,
    // and the sheet keeps every word written when it does.
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(notifier.decisions, hasLength(1));
  });

  testWidgets('a failed save keeps the reviewer\'s notes on screen', (
    tester,
  ) async {
    final notifier = await pumpQueue(tester, shouldFail: true);

    await tester.tap(find.text('Record decision').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Reviewer notes'),
      'Held until the archive reference arrives.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Start review'));
    await tester.pumpAndSettle();

    expect(find.text('Record verification decision'), findsOneWidget);
    expect(
      find.text('Held until the archive reference arrives.'),
      findsOneWidget,
    );
    expect(find.textContaining('Could not record the decision'), findsOneWidget);
    // The attempt reached the notifier; only the server refused it.
    expect(notifier.decisions, hasLength(1));
  });

  testWidgets('an empty queue says so without claiming all is documented', (
    tester,
  ) async {
    await pumpQueue(tester, queue: const []);

    expect(find.text('Nothing awaiting verification'), findsOneWidget);
    expect(
      find.textContaining('rejected or never submitted'),
      findsOneWidget,
    );
  });

  testWidgets('the intro never frames the score as a truth claim', (
    tester,
  ) async {
    await pumpQueue(tester);

    // The trust score measures documentation strength. Wording it as
    // likelihood of truth is the one claim the workflow must never make,
    // and the intro is where a reviewer reads what they are approving.
    expect(
      find.textContaining('never how likely'),
      findsOneWidget,
    );
    expect(
      find.textContaining('how well a story is documented'),
      findsOneWidget,
    );
  });
}
