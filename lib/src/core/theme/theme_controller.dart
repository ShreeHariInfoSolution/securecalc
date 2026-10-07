import 'package:flutter/material.dart';
import '../config/app_preferences.dart';

/// Reactive Theme Controller managing Light, Dark, and System modes with persistence.
class ThemeController extends ValueNotifier<ThemeMode> {
  static final ThemeController instance = ThemeController._();

  ThemeController._() : super(ThemeMode.system);

  void setThemeMode(ThemeMode mode) {
    value = mode;
    AppPreferences.setThemeMode(mode);
  }

  String get currentModeName {
    switch (value) {
      case ThemeMode.system:
        return 'System Default';
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.dark:
        return 'Dark Mode';
    }
  }
}
