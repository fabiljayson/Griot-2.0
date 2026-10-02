import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:griot_ai/features/audio/widgets/audio_playback_indicator.dart';

List<double> _barScales(WidgetTester tester) => tester
    .widgetList<Transform>(find.byType(Transform))
    .map((transform) => transform.transform.storage[5])
    .toList();

void main() {
  testWidgets('equalizer animates while audio is playing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AudioPlaybackIndicator(isPlaying: true)),
      ),
    );

    final initialScales = _barScales(tester);
    await tester.pump(const Duration(milliseconds: 260));

    expect(_barScales(tester), isNot(initialScales));
    expect(tester.takeException(), isNull);
  });

  testWidgets('equalizer settles when audio is paused', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AudioPlaybackIndicator(isPlaying: false)),
      ),
    );

    final pausedScales = _barScales(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(_barScales(tester), pausedScales);
    expect(tester.takeException(), isNull);
  });

  testWidgets('equalizer respects reduced-motion settings', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: AudioPlaybackIndicator(isPlaying: true)),
        ),
      ),
    );

    final initialScales = _barScales(tester);
    await tester.pump(const Duration(milliseconds: 600));

    expect(_barScales(tester), initialScales);
    expect(tester.takeException(), isNull);
  });
}
