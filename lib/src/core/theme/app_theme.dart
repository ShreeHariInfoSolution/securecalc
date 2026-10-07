import 'package:flutter/material.dart';

/// Pure iOS Style Application Theme setup using Material 3.
/// Matches Apple iOS Messages & System Blue specifications.
class AppTheme {
  AppTheme._();

  /// Primary Accent: iOS System Blue
  static const Color primaryColor = Color(0xFF007AFF);
  static const Color onlineGreen = Color(0xFF34C759);
  static const Color subtitleGrey = Color(0xFF8E8E93);

  /// Light Mode Palette
  static const Color lightBackground = Color(0xFFF2F2F7); // iOS Light Grouped
  static const Color lightSurface = Color(0xFFFFFFFF); // Pure White Cards
  static const Color lightBubbleMe = Color(0xFF007AFF); // iOS Blue iMessage Bubble
  static const Color lightBubbleOther = Color(0xFFE9E9EB); // iOS Light Grey Received Bubble

  /// Dark Mode Palette
  static const Color darkBackground = Color(0xFF000000); // True OLED Pitch Black
  static const Color darkSurface = Color(0xFF1C1C1E); // iOS Dark Card
  static const Color darkBubbleMe = Color(0xFF007AFF); // iOS Blue iMessage Bubble
  static const Color darkBubbleOther = Color(0xFF2C2C2E); // iOS Dark Grey Received Bubble

  /// iOS Light Style Palette
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
        primary: primaryColor,
        surface: lightSurface,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryColor),
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide.none,
        ),
      ),
    );
  }

  /// True OLED / AMOLED Dark Style Palette
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
        primary: primaryColor,
        surface: darkSurface,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: darkBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryColor),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide.none,
        ),
      ),
    );
  }
}
