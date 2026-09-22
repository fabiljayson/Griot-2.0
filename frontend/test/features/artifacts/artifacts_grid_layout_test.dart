import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:griot_ai/core/theme/app_theme.dart';
import 'package:griot_ai/features/artifacts/providers/artifacts_provider.dart';
import 'package:griot_ai/features/artifacts/screens/artifacts_screen.dart';
import 'package:griot_ai/features/artifacts/widgets/artifact_card.dart';
import 'package:griot_ai/features/qr_scanner/services/qr_api_service.dart';

class _MockQrApiService extends Mock implements QrApiService {}

/// Regression test for the "Artifacts overflowed by ~85px" bug.
///
/// The grid used a constant `mainAxisExtent: 300`. On a 1-column phone the
/// 4:3 cover eats ~246px and the category/title/culture/museum text block
/// needs ~140px more — the fixed cell clipped the text, which painted outside
/// the card. Cells are now sized from the column width + text scale.
void main() {
  testWidgets('ArtifactsScreen grid fits its cards on a 1-column phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mock = _MockQrApiService();
    when(() => mock.listArtifacts(page: any(named: 'page')))
        .thenAnswer((_) async => const [
          ArtifactModel(
            id: 1,
            title: 'The Sacred Royal Throne of the Bamileke Guardian Chiefs',
            category: 'sculpture',
            culture: 'Bamileke',
            region: 'West Region',
            museumName: 'Musée National de Douala',
          ),
        ]);
    when(() => mock.listArtifacts(page: 2)).thenAnswer((_) async => const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artifactsProvider.overrideWith((ref) => ArtifactsNotifier(apiService: mock)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ArtifactsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(ArtifactCard), findsOneWidget);
    expect(find.text('Musée National de Douala'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}