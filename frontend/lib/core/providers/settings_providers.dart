import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Current theme mode. A persisted preference (shared_preferences) is
/// added with the onboarding flow in Phase 7.
class SettingsController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  /// Flip between light and dark. If currently following the system,
  /// resolve the system brightness first so the toggle is deterministic.
  void toggleDarkMode({Brightness? systemBrightness}) {
    final current = state == ThemeMode.system
        ? (systemBrightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light)
        : state;
    state = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void set(ThemeMode mode) => state = mode;
}

final settingsProvider =
    NotifierProvider<SettingsController, ThemeMode>(SettingsController.new);
