import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../theme/font_size_controller.dart';
import '../theme/theme_controller.dart';
import '../../features/calculator/domain/calculator_logic.dart';

/// Centralized persistent settings manager using SharedPreferences.
class AppPreferences {
  AppPreferences._();

  static late SharedPreferences _prefs;

  static const String _keyThemeMode = 'PREF_THEME_MODE';
  static const String _keyFontScale = 'PREF_FONT_SCALE';
  static const String _keyPasscode = 'PREF_SECRET_PASSCODE';
  static const String _keyDummyCode = 'PREF_DUMMY_CODE';
  static const String _keyPanicShake = 'PREF_PANIC_SHAKE';
  static const String _keyDisguiseTitle = 'PREF_DISGUISE_TITLE';
  static const String _keyScreenshotPrevent = 'PREF_PREVENT_SCREENSHOTS';
  static const String _keyDisappearingTimer = 'PREF_DISAPPEARING_TIMER';
  static const String deviceIdKey = 'deviceId';
  static const String _keyDeviceId = 'PREF_DEVICE_ID';
  static const String _keyDisplayName = 'PREF_DISPLAY_NAME';
  static const String _keyProfileImagePath = 'PREF_PROFILE_IMAGE_PATH';
  static const String _keyShowOnlineStatus = 'PREF_SHOW_ONLINE_STATUS';
  static const String _keyHasConsented = 'PREF_HAS_CONSENTED';

  /// Flag indicating if an image/camera picker is currently open to prevent lifecycle route pop.
  static bool isPickerActive = false;

  /// Flag indicating if security settings/flags are being modified to prevent lifecycle route pop.
  static bool isChangingSettings = false;

  static const MethodChannel _securityChannel =
      MethodChannel('com.shis.securecalc/security');

  /// Initializes SharedPreferences and restores saved settings.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    // 1. Restore Theme Mode
    final savedThemeIndex = _prefs.getInt(_keyThemeMode);
    if (savedThemeIndex != null && savedThemeIndex < ThemeMode.values.length) {
      ThemeController.instance.value = ThemeMode.values[savedThemeIndex];
    }

    // 2. Restore Font Scale
    final savedFontScale = _prefs.getDouble(_keyFontScale) ?? 1.0;
    FontSizeController.instance.value = savedFontScale;

    // 3. Restore Secret Passcode
    final savedPasscode = _prefs.getString(_keyPasscode);
    if (savedPasscode != null && savedPasscode.isNotEmpty) {
      CalculatorLogic.secretPasscode = savedPasscode;
    }

    // 4. Restore Dummy / Fake Crash Passcode
    final savedDummy = _prefs.getString(_keyDummyCode);
    if (savedDummy != null) {
      CalculatorLogic.dummyCode = savedDummy;
    }

    // 5. Restore/Initialize Device Identity
    final existingId = _prefs.getString(_keyDeviceId) ?? _prefs.getString(deviceIdKey);
    if (existingId == null || existingId.isEmpty) {
      final newId = 'device_${const Uuid().v4()}';
      await _prefs.setString(_keyDeviceId, newId);
      await _prefs.setString(deviceIdKey, newId);
    }

    await updateSecureFlag();
  }

  // Setters
  static Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setInt(_keyThemeMode, mode.index);
  }

  static Future<void> setFontScale(double scale) async {
    await _prefs.setDouble(_keyFontScale, scale);
  }

  static Future<void> setPasscode(String code) async {
    await _prefs.setString(_keyPasscode, code);
  }

  static Future<void> setDummyCode(String code) async {
    await _prefs.setString(_keyDummyCode, code);
  }

  static String getDummyCode() => _prefs.getString(_keyDummyCode) ?? '';

  static Future<void> setPanicShake(bool enabled) async {
    await _prefs.setBool(_keyPanicShake, enabled);
  }

  static bool getPanicShake() => _prefs.getBool(_keyPanicShake) ?? true;

  static Future<void> setDisguiseTitle(bool enabled) async {
    await _prefs.setBool(_keyDisguiseTitle, enabled);
  }

  static bool getDisguiseTitle() => _prefs.getBool(_keyDisguiseTitle) ?? true;

  static Future<void> setPreventScreenshots(bool enabled) async {
    isChangingSettings = true;
    try {
      await _prefs.setBool(_keyScreenshotPrevent, enabled);
      await updateSecureFlag();
    } finally {
      Future.delayed(const Duration(milliseconds: 1000), () {
        isChangingSettings = false;
      });
    }
  }

  static bool getPreventScreenshots() =>
      _prefs.getBool(_keyScreenshotPrevent) ?? true;

  static Future<void> setDisappearingTimer(String value) async {
    await _prefs.setString(_keyDisappearingTimer, value);
  }

  static String getDisappearingTimer() =>
      _prefs.getString(_keyDisappearingTimer) ?? '24 hours';

  static Future<void> setDeviceId(String id) async {
    await _prefs.setString(_keyDeviceId, id);
    await _prefs.setString(deviceIdKey, id);
  }

  static String? getDeviceIdSync() {
    return _prefs.getString(_keyDeviceId) ?? _prefs.getString(deviceIdKey);
  }

  static Future<void> setDisplayName(String name) async {
    await _prefs.setString(_keyDisplayName, name);
  }

  /// Removes the values tied to the currently signed-in account.
  static Future<void> clearAccountProfile() async {
    await _prefs.remove(_keyDisplayName);
    await _prefs.remove(_keyProfileImagePath);
    await _prefs.remove(_keyShowOnlineStatus);
  }

  static String getDisplayName() {
    final saved = _prefs.getString(_keyDisplayName);
    if (saved != null && saved.trim().isNotEmpty) {
      return saved.trim();
    }
    return 'Profile';
  }

  static Future<void> setProfileImagePath(String path) async {
    await _prefs.setString(_keyProfileImagePath, path);
  }

  static String? getProfileImagePath() {
    return _prefs.getString(_keyProfileImagePath);
  }

  static bool getShowOnlineStatus() =>
      _prefs.getBool(_keyShowOnlineStatus) ?? true;

  static Future<void> setShowOnlineStatus(bool enabled) async {
    await _prefs.setBool(_keyShowOnlineStatus, enabled);
  }

  static bool getHasConsented() =>
      _prefs.getBool(_keyHasConsented) ?? false;

  static Future<void> setHasConsented(bool value) async {
    await _prefs.setBool(_keyHasConsented, value);
  }

  static Future<void> updateSecureFlag() async {
    try {
      final prevent = getPreventScreenshots();
      await _securityChannel.invokeMethod('setSecureFlag', {'enable': prevent});
    } catch (_) {}
  }
}
