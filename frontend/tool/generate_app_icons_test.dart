import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/widgets/griot_logo.dart';

/// Generates every launcher/app icon PNG for Android, iOS and web by
/// rasterising the [GriotMark] widget at the exact target pixel size.
///
/// Run explicitly (it lives outside `test/`, so the normal suite skips it):
///   flutter test tool/generate_app_icons_test.dart
void main() {
  final targets = <({String path, int size, double scale})>[
    // --- Android legacy launcher mipmaps --------------------------------
    (path: 'android/app/src/main/res/mipmap-mdpi/ic_launcher.png', size: 48, scale: 1.0),
    (path: 'android/app/src/main/res/mipmap-hdpi/ic_launcher.png', size: 72, scale: 1.0),
    (path: 'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', size: 96, scale: 1.0),
    (path: 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', size: 144, scale: 1.0),
    (path: 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', size: 192, scale: 1.0),

    // --- iOS AppIcon.appiconset -----------------------------------------
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png', size: 20, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png', size: 40, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png', size: 60, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png', size: 29, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png', size: 58, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png', size: 87, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png', size: 40, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png', size: 80, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png', size: 120, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png', size: 120, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png', size: 180, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png', size: 76, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png', size: 152, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png', size: 167, scale: 1.0),
    (path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png', size: 1024, scale: 1.0),

    // --- Web PWA / favicon ----------------------------------------------
    (path: 'web/favicon.png', size: 32, scale: 1.0),
    (path: 'web/icons/Icon-192.png', size: 192, scale: 1.0),
    (path: 'web/icons/Icon-512.png', size: 512, scale: 1.0),
    // Maskable icons keep the mark inside the PWA safe zone.
    (path: 'web/icons/Icon-maskable-192.png', size: 192, scale: 0.72),
    (path: 'web/icons/Icon-maskable-512.png', size: 512, scale: 0.72),
  ];

  for (final target in targets) {
    testWidgets('generate ${target.path} (${target.size}px)', (tester) async {
      // Size the test view to the exact icon dimensions at dpr 1.0 so the
      // capture below yields a pixel-perfect PNG.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = Size.square(target.size.toDouble());
      addTearDown(tester.view.reset);

      final key = UniqueKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: GriotMark(
            size: target.size.toDouble(),
            borderRadius: target.size * 0.24,
          ),
        ),
      );

      // Wait for image to load
      await tester.pumpAndSettle();

      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final image = await boundary.toImage();
      expect(image.width, target.size);
      expect(image.height, target.size);

      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(target.path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());

      debugPrint('Wrote ${target.path} (${image.width}x${image.height})');
    });
  }
}
