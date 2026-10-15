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
  static const String _keyDuressPasscode = 'PREF_DURESS_PASSCODE';
  static const String _keyPanicShake = 'PREF_PANIC_SHAKE';
  static const String _keyDisguiseTitle = 'PREF_DISGUISE_TITLE';
  static const String _keyScreenshotPrevent = 'PREF_PREVENT_SCREENSHOTS';
  static const String _keyDisappearingTimer = 'PREF_DISAPPEARING_TIMER';
  static const String _keyEdgePanelEnabled = 'PREF_EDGE_PANEL_ENABLED';
  static const String _keyEdgePanelY = 'PREF_EDGE_PANEL_Y';
  static const String deviceIdKey = 'deviceId';
  static const String _keyDeviceId = 'PREF_DEVICE_ID';
  static const String _keyDisplayName = 'PREF_DISPLAY_NAME';
  static const String _keyProfileImagePath = 'PREF_PROFILE_IMAGE_PATH';
  static const String _keyShowOnlineStatus = 'PREF_SHOW_ONLINE_STATUS';
  static const String _keyHasConsented = 'PREF_HAS_CONSENTED';
  static const String _keyAutoDownloadImages = 'PREF_AUTO_DOWNLOAD_IMAGES';
  static const String _keyAutoDownloadVideos = 'PREF_AUTO_DOWNLOAD_VIDEOS';
  static const String _keyAutoDownloadDocs = 'PREF_AUTO_DOWNLOAD_DOCS';
  static const String _keyChatBubbleColor = 'PREF_CHAT_BUBBLE_COLOR';
  static const String _keyChatWallpaperType = 'PREF_CHAT_WALLPAPER_TYPE';
  static const String _keyChatWallpaperPath = 'PREF_CHAT_WALLPAPER_PATH';
  static const String _keyChatWallpaperDim = 'PREF_CHAT_WALLPAPER_DIM';

  static final ValueNotifier<bool> edgePanelEnabledNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<double> edgePanelYNotifier =
      ValueNotifier<double>(0.28);
  static final ValueNotifier<int> chatBubbleColorNotifier =
      ValueNotifier<int>(0xFF007AFF); // Default iOS Blue
  static final ValueNotifier<String> chatWallpaperNotifier =
      ValueNotifier<String>('default');

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

    // 4. Restore Duress / Decoy Passcode (default "4321")
    final savedDuress = _prefs.getString(_keyDuressPasscode);
    if (savedDuress != null && savedDuress.isNotEmpty) {
      CalculatorLogic.duressPasscode = savedDuress;
    } else {
      CalculatorLogic.duressPasscode = '4321';
    }

    // 5. Restore Edge Panel Settings
    edgePanelEnabledNotifier.value = _prefs.getBool(_keyEdgePanelEnabled) ?? true;
    edgePanelYNotifier.value = _prefs.getDouble(_keyEdgePanelY) ?? 0.28;

    // 6. Restore/Initialize Device Identity
    String? existingId = _prefs.getString(_keyDeviceId) ?? _prefs.getString(deviceIdKey);
    final hardwareId = await getSystemHardwareDeviceId();
    if (hardwareId != null && hardwareId.isNotEmpty) {
      existingId = hardwareId;
    } else if (existingId == null || existingId.isEmpty) {
      existingId = 'device_${const Uuid().v4()}';
    }
    await _prefs.setString(_keyDeviceId, existingId);
    await _prefs.setString(deviceIdKey, existingId);

    await updateSecureFlag();

    displayNameNotifier.value = getDisplayName();
    profileImagePathNotifier.value = getProfileImagePath();

    // Restore Chat Customizations (Default Bubble Color: Blue 0xFF007AFF)
    final savedBubbleColor = _prefs.getInt(_keyChatBubbleColor) ?? 0xFF007AFF;
    chatBubbleColorNotifier.value = savedBubbleColor;
    chatWallpaperNotifier.value = _prefs.getString(_keyChatWallpaperType) ?? 'default';
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

  static Future<void> setDuressPasscode(String code) async {
    await _prefs.setString(_keyDuressPasscode, code);
    CalculatorLogic.duressPasscode = code;
  }

  static String getDuressPasscode() =>
      _prefs.getString(_keyDuressPasscode) ?? '4321';

  static Future<void> setPanicShake(bool enabled) async {
    await _prefs.setBool(_keyPanicShake, enabled);
  }

  static bool getPanicShake() => _prefs.getBool(_keyPanicShake) ?? true;

  static Future<void> setDisguiseTitle(bool enabled) async {
    await _prefs.setBool(_keyDisguiseTitle, enabled);
  }

  static bool getDisguiseTitle() => _prefs.getBool(_keyDisguiseTitle) ?? true;

  static Future<void> setEdgePanelEnabled(bool enabled) async {
    await _prefs.setBool(_keyEdgePanelEnabled, enabled);
    edgePanelEnabledNotifier.value = enabled;
  }

  static bool getEdgePanelEnabled() =>
      _prefs.getBool(_keyEdgePanelEnabled) ?? true;

  static Future<void> setEdgePanelY(double relativeY) async {
    await _prefs.setDouble(_keyEdgePanelY, relativeY);
    edgePanelYNotifier.value = relativeY;
  }

  static double getEdgePanelY() =>
      _prefs.getDouble(_keyEdgePanelY) ?? 0.28;

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

  static Future<String?> getSystemHardwareDeviceId() async {
    try {
      final String? id = await _securityChannel.invokeMethod<String>('getSystemDeviceId');
      if (id != null && id.isNotEmpty) {
        return id;
      }
    } catch (e) {
      debugPrint('[AppPreferences] Get system hardware device ID failed: $e');
    }
    return null;
  }

  static Future<void> setDeviceId(String id) async {
    await _prefs.setString(_keyDeviceId, id);
    await _prefs.setString(deviceIdKey, id);
  }

  static final ValueNotifier<String> displayNameNotifier =
      ValueNotifier<String>('Profile');
  static final ValueNotifier<String?> profileImagePathNotifier =
      ValueNotifier<String?>(null);

  static String? getDeviceIdSync() {
    return _prefs.getString(_keyDeviceId) ?? _prefs.getString(deviceIdKey);
  }

  static Future<void> setDisplayName(String name) async {
    final clean = name.trim();
    await _prefs.setString(_keyDisplayName, clean);
    displayNameNotifier.value = clean.isNotEmpty ? clean : 'Profile';
  }

  /// Removes the values tied to the currently signed-in account.
  static Future<void> clearAccountProfile() async {
    await _prefs.remove(_keyDisplayName);
    await _prefs.remove(_keyProfileImagePath);
    await _prefs.remove(_keyShowOnlineStatus);
    displayNameNotifier.value = 'Profile';
    profileImagePathNotifier.value = null;
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
    profileImagePathNotifier.value = path;
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

  static bool getAutoDownloadImages() =>
      _prefs.getBool(_keyAutoDownloadImages) ?? true;

  static Future<void> setAutoDownloadImages(bool enabled) async {
    await _prefs.setBool(_keyAutoDownloadImages, enabled);
  }

  static bool getAutoDownloadVideos() =>
      _prefs.getBool(_keyAutoDownloadVideos) ?? true;

  static Future<void> setAutoDownloadVideos(bool enabled) async {
    await _prefs.setBool(_keyAutoDownloadVideos, enabled);
  }

  static bool getAutoDownloadDocs() =>
      _prefs.getBool(_keyAutoDownloadDocs) ?? true;

  static Future<void> setAutoDownloadDocs(bool enabled) async {
    await _prefs.setBool(_keyAutoDownloadDocs, enabled);
  }

  static Future<void> updateSecureFlag() async {
    try {
      final prevent = getPreventScreenshots();
      await _securityChannel.invokeMethod('setSecureFlag', {'enable': prevent});
    } catch (_) {}
  }

  // --- Chat Customizations: Bubble Color & Wallpaper ---
  static Color getChatBubbleColor({String? chatId}) {
    if (chatId != null && chatId.isNotEmpty) {
      final perChat = _prefs.getInt('${_keyChatBubbleColor}_$chatId');
      if (perChat != null) return Color(perChat);
    }
    final colorInt = _prefs.getInt(_keyChatBubbleColor) ?? 0xFF007AFF;
    return Color(colorInt);
  }

  static Future<void> setChatBubbleColor(Color color, {String? chatId}) async {
    final val = color.value;
    if (chatId != null && chatId.isNotEmpty) {
      await _prefs.setInt('${_keyChatBubbleColor}_$chatId', val);
    }
    await _prefs.setInt(_keyChatBubbleColor, val);
    chatBubbleColorNotifier.value = val;
  }

  static String getWallpaperType({String? chatId}) {
    if (chatId != null && chatId.isNotEmpty) {
      final perChat = _prefs.getString('${_keyChatWallpaperType}_$chatId');
      if (perChat != null) return perChat;
    }
    return _prefs.getString(_keyChatWallpaperType) ?? 'default';
  }

  static String? getWallpaperPath({String? chatId}) {
    if (chatId != null && chatId.isNotEmpty) {
      final perChat = _prefs.getString('${_keyChatWallpaperPath}_$chatId');
      if (perChat != null && perChat.isNotEmpty) return perChat;
    }
    return _prefs.getString(_keyChatWallpaperPath);
  }

  static double getWallpaperDim({String? chatId}) {
    if (chatId != null && chatId.isNotEmpty) {
      final perChat = _prefs.getDouble('${_keyChatWallpaperDim}_$chatId');
      if (perChat != null) return perChat;
    }
    return _prefs.getDouble(_keyChatWallpaperDim) ?? 0.15;
  }

  static Future<void> setChatWallpaper({
    required String type,
    String? customPath,
    double dim = 0.15,
    String? chatId,
  }) async {
    if (chatId != null && chatId.isNotEmpty) {
      await _prefs.setString('${_keyChatWallpaperType}_$chatId', type);
      if (customPath != null) {
        await _prefs.setString('${_keyChatWallpaperPath}_$chatId', customPath);
      }
      await _prefs.setDouble('${_keyChatWallpaperDim}_$chatId', dim);
    }
    await _prefs.setString(_keyChatWallpaperType, type);
    if (customPath != null) {
      await _prefs.setString(_keyChatWallpaperPath, customPath);
    }
    await _prefs.setDouble(_keyChatWallpaperDim, dim);
    chatWallpaperNotifier.value = '$type:${DateTime.now().millisecondsSinceEpoch}';
  }
}
