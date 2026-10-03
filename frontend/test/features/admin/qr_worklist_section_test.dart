import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/theme/app_icons.dart';
import 'package:griot_ai/features/admin/models/qr_worklist_models.dart';
import 'package:griot_ai/features/admin/providers/admin_provider.dart';
import 'package:griot_ai/features/admin/widgets/qr_worklist_section.dart';

/// An empty-but-not-yet-populated worklist: the catalog has rows, this page
/// does not. Used to keep the dashboard tests off the network.
const emptyQrWorklist = QrWorklist(total: 0, generated: 0);

QrWorklistEntry _entry({
  String slug = 'kenkeni-drum',
  String title = 'Kenkeni Drum',
  bool hasQrCode = false,
  int scanTotal = 0,
  String museumName = 'Foumban Royal Museum',
}) => QrWorklistEntry(
  id: 1,
  slug: slug,
  title: title,
  category: 'instrument',
  museumName: museumName,
  deepLink: 'https://africanteller.org/artifact/$slug',
  scanTotal: scanTotal,
  hasQrCode: hasQrCode,
);

/// Records what the section asked for instead of calling the API.
class _RecordingQrNotifier extends QrGenerationNotifier {
  _RecordingQrNotifier(this.result);

  final QrWorklistGeneration result;

  /// One entry per call: the slugs passed, or `[]` for "everything missing".
  final calls = <List<String>>[];

  @override
  Future<QrWorklistGeneration?> generateOne(String slug) async {
    calls.add([slug]);
    state = const QrGenerationState();
    return result;
  }

  @override
  Future<QrWorklistGeneration?> generateAllMissing() async {
    calls.add(const []);
    state = const QrGenerationState();
    return result;
  }
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required QrWorklist worklist,
  QrWorklistGeneration? result,
  _RecordingQrNotifier? notifier,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final recorder =
      notifier ?? _RecordingQrNotifier(result ?? const QrWorklistGeneration());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        qrWorklistProvider.overrideWith((ref) async => worklist),
        qrGenerationProvider.overrideWith((ref) => recorder),
      ],
      child: const MaterialApp(home: Scaffold(body: QrWorklistSection())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('QrWorklist.fromJson', () {
    test('reads rows, counts and the truncation flag', () {
      final worklist = QrWorklist.fromJson({
        'artifacts': [
          {
            'id': 3,
            'slug': 'kenkeni-drum',
            'title': 'Kenkeni Drum',
            'category': 'instrument',
            'museum_name': 'Foumban Royal Museum',
            'is_published': true,
            'qr_deep_link': 'https://africanteller.org/artifact/kenkeni-drum',
            'scan_total': 12,
            'has_qr_code': false,
          },
        ],
        'total': 134,
        'generated': 40,
        'truncated': true,
      });

      expect(worklist.entries, hasLength(1));
      expect(worklist.entries.first.title, 'Kenkeni Drum');
      expect(worklist.entries.first.scanTotal, 12);
      expect(worklist.total, 134);
      expect(worklist.generated, 40);
      expect(worklist.truncated, isTrue);
    });

    test('tolerates a payload with nothing in it', () {
      final worklist = QrWorklist.fromJson(const {});
      expect(worklist.entries, isEmpty);
      expect(worklist.total, 0);
      expect(worklist.truncated, isFalse);
    });

    test('unlabelled holds only the rows with no code', () {
      final worklist = QrWorklist(
        entries: [
          _entry(slug: 'a', title: 'A'),
          _entry(slug: 'b', title: 'B', hasQrCode: true),
        ],
        total: 2,
      );
      expect(
        worklist.unlabelled.map((entry) => entry.slug),
        ['a'],
      );
    });
  });

  group('QrWorklistGeneration.fromJson', () {
    test('reads generated, missing and skipped', () {
      final result = QrWorklistGeneration.fromJson({
        'generated': ['a', 'b'],
        'missing': ['gone'],
        'skipped': false,
      });
      expect(result.generated, ['a', 'b']);
      expect(result.missing, ['gone']);
      expect(result.skipped, isFalse);
    });

    test('a skipped batch reports itself as empty', () {
      final result = QrWorklistGeneration.fromJson(const {
        'generated': <String>[],
        'missing': <String>[],
        'skipped': true,
      });
      expect(result.generated, isEmpty);
      expect(result.skipped, isTrue);
    });
  });

  group('QrWorklistSection', () {
    testWidgets('shows the objects that still have no code first', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        worklist: QrWorklist(
          entries: [
            _entry(slug: 'kenkeni-drum', title: 'Kenkeni Drum'),
            _entry(
              slug: 'lobe-falls',
              title: 'Lobe Falls',
              hasQrCode: true,
            ),
          ],
          total: 2,
        ),
      );

      expect(find.text('QR code worklist'), findsOneWidget);
      expect(find.text('Kenkeni Drum'), findsOneWidget);
      expect(find.text('No code yet'), findsOneWidget);
      expect(find.text('Ready to print'), findsOneWidget);
      // One of two rows is still unlabelled.
      expect(find.text('1 of 2 still unlabelled'), findsOneWidget);
    });

    testWidgets('shows the deep link the code will encode', (tester) async {
      await _pumpSection(
        tester,
        worklist: QrWorklist(entries: [_entry()], total: 1),
      );
      expect(
        find.text('https://africanteller.org/artifact/kenkeni-drum'),
        findsOneWidget,
      );
    });

    testWidgets('says so when the worklist is not the whole catalog', (
      tester,
    ) async {
      await _pumpSection(
        tester,
        worklist: QrWorklist(entries: [_entry()], total: 134, truncated: true),
      );
      expect(
        find.textContaining('the catalog is larger than this worklist'),
        findsOneWidget,
      );
    });

    testWidgets('says so when there is nothing to label', (tester) async {
      await _pumpSection(
        tester,
        worklist: QrWorklist(entries: [], total: 0),
      );
      expect(find.text('No artifacts to label yet.'), findsOneWidget);
    });

    testWidgets('generating one row asks for that slug only', (tester) async {
      final notifier = _RecordingQrNotifier(
        const QrWorklistGeneration(generated: ['kenkeni-drum']),
      );
      await _pumpSection(
        tester,
        worklist: QrWorklist(entries: [_entry()], total: 1),
        notifier: notifier,
      );

      await tester.tap(find.byIcon(AppIcons.qr_code_scanner).last);
      await tester.pumpAndSettle();

      expect(notifier.calls, [
        ['kenkeni-drum'],
      ]);
      expect(find.textContaining('QR code generated for'), findsOneWidget);
    });

    testWidgets('regenerating an existing code still passes its slug', (
      tester,
    ) async {
      final notifier = _RecordingQrNotifier(
        const QrWorklistGeneration(generated: ['kenkeni-drum']),
      );
      await _pumpSection(
        tester,
        worklist: QrWorklist(
          entries: [_entry(hasQrCode: true)],
          total: 1,
        ),
        notifier: notifier,
      );

      await tester.tap(find.byIcon(AppIcons.refresh).last);
      await tester.pumpAndSettle();

      expect(notifier.calls, [
        ['kenkeni-drum'],
      ]);
    });

    testWidgets('the bulk button sends no slugs, meaning "everything missing"', (
      tester,
    ) async {
      final notifier = _RecordingQrNotifier(
        const QrWorklistGeneration(generated: ['a', 'b', 'c']),
      );
      await _pumpSection(
        tester,
        worklist: QrWorklist(entries: [_entry()], total: 1),
        notifier: notifier,
      );

      await tester.tap(find.text('Generate all missing'));
      await tester.pumpAndSettle();

      expect(notifier.calls, [
        <String>[],
      ]);
      expect(find.text('3 QR codes generated.'), findsOneWidget);
    });

    testWidgets('reports a stale row instead of hiding it', (tester) async {
      final notifier = _RecordingQrNotifier(
        const QrWorklistGeneration(generated: ['a'], missing: ['gone']),
      );
      await _pumpSection(
        tester,
        worklist: QrWorklist(entries: [_entry()], total: 1),
        notifier: notifier,
      );

      await tester.tap(find.text('Generate all missing'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 could not be found'), findsOneWidget);
    });

    testWidgets('a completed catalogue is reported, not a silent no-op', (
      tester,
    ) async {
      final notifier = _RecordingQrNotifier(
        const QrWorklistGeneration(skipped: true),
      );
      await _pumpSection(
        tester,
        worklist: QrWorklist(entries: [_entry(hasQrCode: true)], total: 1),
        notifier: notifier,
      );

      await tester.tap(find.text('Generate all missing'));
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing to generate — every artifact already has a code.'),
        findsOneWidget,
      );
    });
  });
}