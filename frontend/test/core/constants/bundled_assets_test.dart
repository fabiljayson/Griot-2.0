import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:griot_ai/core/constants/story_assets.dart';
import 'package:griot_ai/features/discover/models/region_model.dart';

/// Guards the asset-bundling bug that made 20 bundled images invisible.
///
/// Flutter's `flutter: assets:` directory entries are **not recursive**, so a
/// directory such as `assets/imagery/` bundles nothing from
/// `assets/imagery/stories/` — the files are dropped silently, the app builds
/// and runs, and every image falls back to a placeholder. These tests fail the
/// build the moment a subdirectory stops being declared, or a referenced file
/// disappears from disk.
void main() {
  late String pubspec;
  late Set<String> declaredDirs;

  setUpAll(() {
    pubspec = File('pubspec.yaml').readAsStringSync();
    declaredDirs = _declaredAssetDirs(pubspec);
  });

  group('flutter assets declaration', () {
    test('declares the asset directories it needs', () {
      expect(declaredDirs, contains('assets/logo/'));
      expect(declaredDirs, contains('assets/fonts/'));
    });

    test('does not declare a directory that is missing from disk', () {
      for (final dir in declaredDirs) {
        expect(
          Directory(dir).existsSync(),
          isTrue,
          reason: 'pubspec declares $dir but it does not exist',
        );
      }
    });

    test('declares every directory that actually holds assets', () {
      // A directory containing files must be declared, or Flutter silently
      // omits its contents from the bundle.
      final onDisk = _directoriesContainingFiles('assets');

      final undeclared = onDisk.difference(declaredDirs);
      expect(
        undeclared,
        isEmpty,
        reason:
            'These directories contain assets but are not listed under '
            '`flutter: assets:` in pubspec.yaml — Flutter asset entries are '
            'not recursive, so their files would be dropped from the bundle: '
            '${undeclared.join(', ')}',
      );
    });
  });

  group('referenced assets exist', () {
    test('every bundled story cover is on disk and declared', () {
      expect(StoryCoverAssets.all, isNotEmpty);

      for (final path in StoryCoverAssets.all) {
        _expectBundled(path, declaredDirs);
      }
    });

    test('every region image is on disk and declared', () {
      expect(Regions.all, isNotEmpty);

      for (final region in Regions.all) {
        _expectBundled(region.imageAsset, declaredDirs);
      }
    });

    test('story covers and region art never share a file accidentally', () {
      final covers = StoryCoverAssets.all.toSet();
      final regionArt = Regions.all.map((r) => r.imageAsset).toSet();
      expect(covers.intersection(regionArt), isEmpty);
    });
  });
}

void _expectBundled(String path, Set<String> declaredDirs) {
  expect(File(path).existsSync(), isTrue, reason: '$path is missing on disk');
  expect(
    declaredDirs.any(path.startsWith),
    isTrue,
    reason: '$path is not covered by any declared asset directory',
  );
}

/// Directory entries listed under the pubspec's `flutter: assets:` section,
/// normalised with a trailing slash.
Set<String> _declaredAssetDirs(String pubspec) {
  final dirs = <String>{};
  var inAssets = false;

  for (final rawLine in pubspec.split('\n')) {
    final line = rawLine.trimRight();

    if (line.startsWith('  assets:')) {
      inAssets = true;
      continue;
    }

    if (!inAssets) continue;

    // The section ends at the next top-level key (e.g. `  fonts:`).
    if (line.isNotEmpty && !line.startsWith('    ') && !line.startsWith('  - ')) {
      if (!line.startsWith('  #')) inAssets = false;
      continue;
    }

    final entry = line.trim();
    if (!entry.startsWith('- ')) continue;

    final value = entry.substring(2).trim();
    if (value.endsWith('/')) dirs.add(value);
  }

  return dirs;
}

/// Every directory under [root] (recursively) that directly contains a file.
Set<String> _directoriesContainingFiles(String root) {
  final result = <String>{};

  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is! File) continue;
    final dir = entity.parent.path.replaceAll(r'\', '/');
    result.add(dir.endsWith('/') ? dir : '$dir/');
  }

  return result;
}
