import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:african_teller/app.dart';
import 'package:african_teller/core/theme/app_colors.dart';

void main() {
  testWidgets('App shell renders the landing screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AfricanTellerApp()));

    // Landing branding is visible.
    expect(find.text('AFRICAN TELLER'), findsOneWidget);

    // Design tokens match the Ancient Manuscript palette.
    expect(AppColors.terracotta.toARGB32(), 0xFFC85A32);
    expect(AppColors.ochre.toARGB32(), 0xFFD99B26);
    expect(AppColors.savannahGreen.toARGB32(), 0xFF2D5A27);
    expect(AppColors.parchment.toARGB32(), 0xFFF4EFE6);
    expect(AppColors.charcoal.toARGB32(), 0xFF222222);

    // Region cards from the landing grid render (first is visible above
    // the fold, the last requires scrolling in the test viewport).
    expect(find.text('Bamoun'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Grassfields'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Grassfields'), findsOneWidget);
  });
}
