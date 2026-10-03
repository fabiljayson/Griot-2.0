import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/features/admin/models/moderation_models.dart';
import 'package:griot_ai/features/admin/providers/admin_provider.dart';
import 'package:griot_ai/features/admin/screens/consent_review_screen.dart';
import 'package:griot_ai/features/stories/models/story_model.dart';

import '../../support/admin_fixtures.dart';

/// Captures what the screen asked to record, so the tests assert on the
/// decision the moderator actually expressed rather than on a network call.
class RecordingConsentNotifier extends ConsentActionNotifier {
  RecordingConsentNotifier({this.shouldFail = false});

  final bool shouldFail;
  final recorded = <Map<String, Object?>>[];

  @override
  Future<bool> record({
    required String slug,
    required String status,
    required String basis,
    String? rightsHolder,
    String? licence,
  }) async {
    recorded.add({
      'slug': slug,
      'status': status,
      'basis': basis,
      'rightsHolder': rightsHolder,
      'licence': licence,
    });
    return !shouldFail;
  }
}

Future<RecordingConsentNotifier> pumpReview(
  WidgetTester tester, {
  List<ConsentReviewStory>? queue,
  bool shouldFail = false,
}) async {
  final notifier = RecordingConsentNotifier(shouldFail: shouldFail);
  final stories = queue ??
      adminConsentQueueJson()
          .map(ConsentReviewStory.fromJson)
          .toList();

  // Two cards plus their forms need more than the 600px default surface.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consentQueueProvider.overrideWith((ref) async => stories),
        consentActionProvider.overrideWith((ref) => notifier),
      ],
      child: const MaterialApp(home: ConsentReviewScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  testWidgets('lists every story awaiting a decision', (tester) async {
    await pumpReview(tester);

    expect(find.text('The Baobab and the Drum'), findsOneWidget);
    expect(find.text('A Tale Without a Source'), findsOneWidget);
    expect(find.text('2 stories need a decision'), findsOneWidget);
  });

  testWidgets('shows the provenance the decision is actually about', (
    tester,
  ) async {
    await pumpReview(tester);

    // A moderator pressing "granted" is signing for a tradition. If the card
    // hides where the text came from and who holds the rights, the record can
    // be made without reading any of it.
    expect(find.text('Transcribed from an oral telling'), findsOneWidget);
    expect(
      find.textContaining("Recorded in Foumban in 2019"),
      findsOneWidget,
    );
    expect(find.text('The Bamoun council of elders'), findsOneWidget);
    expect(find.text('CC BY-NC 4.0'), findsOneWidget);
    expect(find.text('Northwest'), findsOneWidget);
  });

  testWidgets('distinguishes an unasked story from one awaiting an answer', (
    tester,
  ) async {
    await pumpReview(tester);

    expect(find.text('Awaiting answer'), findsOneWidget);
    expect(find.text('Not requested'), findsOneWidget);
  });

  testWidgets('an empty queue says so without claiming everything is fine', (
    tester,
  ) async {
    await pumpReview(tester, queue: const []);

    expect(find.text('Nothing awaiting a decision'), findsOneWidget);
    expect(find.textContaining('or none has been asked yet'), findsOneWidget);
  });

  testWidgets('refuses to record a decision with no basis', (tester) async {
    final notifier = await pumpReview(tester);

    await tester.tap(find.text('Record decision').first);
    await tester.pumpAndSettle();

    // Basis is prefilled empty on the fixture, so submitting as-is must fail.
    await tester.tap(find.text('Record').last);
    await tester.pumpAndSettle();

    expect(find.text('Record the basis for this decision.'), findsOneWidget);
    expect(notifier.recorded, isEmpty);
    expect(find.text('Record the community’s answer'), findsOneWidget);
  });

  testWidgets('records the decision with its basis', (tester) async {
    final notifier = await pumpReview(tester);

    await tester.tap(find.text('Record decision').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Basis (required)'),
      'Agreed by the family elder in Foumban.',
    );
    await tester.tap(find.text('Record').last);
    await tester.pumpAndSettle();

    expect(notifier.recorded, hasLength(1));
    expect(notifier.recorded.single['slug'], 'the-baobab-and-the-drum');
    expect(notifier.recorded.single['basis'],
        'Agreed by the family elder in Foumban.');
    // The pre-filled rights holder travels with it; an emptied one must send
    // nothing rather than blanking the record.
    expect(notifier.recorded.single['rightsHolder'],
        'The Bamoun council of elders');
    expect(notifier.recorded.single['licence'], 'cc_by_nc');
  });

  testWidgets('an empty rights holder leaves the existing value alone', (
    tester,
  ) async {
    final queue = [
      ConsentReviewStory.fromJson({
        ...adminConsentQueueJson()[1],
        'rights_holder': '',
      }),
    ];
    final notifier = await pumpReview(tester, queue: queue);

    await tester.tap(find.text('Record decision'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Basis (required)'),
      'Elder agreed.',
    );
    await tester.tap(find.text('Record').last);
    await tester.pumpAndSettle();

    expect(notifier.recorded.single['rightsHolder'], isNull);
  });

  testWidgets('warns that withholding on a published story archives it', (
    tester,
  ) async {
    await pumpReview(tester);

    await tester.tap(find.text('Record decision').first);
    await tester.pumpAndSettle();

    // The queue's first story is published, so choosing "withheld" has a
    // consequence beyond the field: it takes the story down.
    await tester.tap(find.byType(DropdownButton<StoryConsent>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consent withheld').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('archives it immediately'), findsOneWidget);
  });

  testWidgets('does not warn about archiving for an unpublished story', (
    tester,
  ) async {
    await pumpReview(tester);

    await tester.tap(find.text('Record decision').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<StoryConsent>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consent withheld').last);
    await tester.pumpAndSettle();

    // The second queued story is a draft: withholding leaves it a draft, and
    // saying otherwise would cry wolf on every decision of this kind.
    expect(find.textContaining('archives it immediately'), findsNothing);
  });

  testWidgets('a failed save keeps the moderator\'s words on screen', (
    tester,
  ) async {
    await pumpReview(tester, shouldFail: true);

    await tester.tap(find.text('Record decision').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Basis (required)'),
      'The elder agreed on condition we name them.',
    );
    await tester.tap(find.text('Record').last);
    await tester.pumpAndSettle();

    // The basis is the whole point of the record. Losing it to a failed
    // request would mean re-interviewing somebody for a field that was already
    // filled in.
    expect(find.text('Record the community’s answer'), findsOneWidget);
    expect(
      find.text('The elder agreed on condition we name them.'),
      findsOneWidget,
    );
    expect(find.byType(Text), findsWidgets);
  });
}