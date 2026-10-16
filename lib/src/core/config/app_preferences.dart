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

  static SharedPreferences? _prefs;

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
  static const String _keyNotificationSound = 'PREF_NOTIFICATION_SOUND';

  static final ValueNotifier<bool> edgePanelEnabledNotifier =
      ValueNotifier<bool>(true);
  static final ValueNotifier<double> edgePanelYNotifier = ValueNotifier<double>(
    0.28,
  );
  static final ValueNotifier<int> chatBubbleColorNotifier = ValueNotifier<int>(
    0xFF007AFF,
  ); // Default iOS Blue
  static final ValueNotifier<String> chatWallpaperNotifier =
      ValueNotifier<String>('default');
  static final ValueNotifier<String> notificationSoundNotifier =
      ValueNotifier<String>('sound_1');

  /// Flag indicating if an image/camera picker is currently open to prevent lifecycle route pop.
  static bool isPickerActive = false;

  /// Flag indicating if security settings/flags are being modified to prevent lifecycle route pop.
  static bool isChangingSettings = false;

  static const MethodChannel _securityChannel = MethodChannel(
    'com.shis.securecalc/security',
  );

  /// Initializes SharedPreferences and restores saved settings.
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs;
    if (p == null) return;

    // 1. Restore Theme Mode
    final savedThemeIndex = p.getInt(_keyThemeMode);
    if (savedThemeIndex != null && savedThemeIndex < ThemeMode.values.length) {
      ThemeController.instance.value = ThemeMode.values[savedThemeIndex];
    }

    // 2. Restore Font Scale
    final savedFontScale = p.getDouble(_keyFontScale) ?? 1.0;
    FontSizeController.instance.value = savedFontScale;

    // 3. Restore Secret Passcode
    final savedPasscode = p.getString(_keyPasscode);
    if (savedPasscode != null && savedPasscode.isNotEmpty) {
      CalculatorLogic.secretPasscode = savedPasscode;
    }

    // 4. Restore Duress / Decoy Passcode (default "4321")
    final savedDuress = p.getString(_keyDuressPasscode);
    if (savedDuress != null && savedDuress.isNotEmpty) {
      CalculatorLogic.duressPasscode = savedDuress;
    } else {
      CalculatorLogic.duressPasscode = '4321';
    }

    // 5. Restore Edge Panel Settings
    edgePanelEnabledNotifier.value = p.getBool(_keyEdgePanelEnabled) ?? true;
    edgePanelYNotifier.value = p.getDouble(_keyEdgePanelY) ?? 0.28;

    // 6. Restore/Initialize Device Identity
    String? existingId = p.getString(_keyDeviceId) ?? p.getString(deviceIdKey);
    final hardwareId = await getSystemHardwareDeviceId();
    if (hardwareId != null && hardwareId.isNotEmpty) {
      existingId = hardwareId;
    } else if (existingId == null || existingId.isEmpty) {
      existingId = 'device_${const Uuid().v4()}';
    }
    await p.setString(_keyDeviceId, existingId);
    await p.setString(deviceIdKey, existingId);

    await updateSecureFlag();

    displayNameNotifier.value = getDisplayName();
    profileImagePathNotifier.value = getProfileImagePath();

    // Restore Chat Customizations (Default Bubble Color: Blue 0xFF007AFF)
    final savedBubbleColor = p.getInt(_keyChatBubbleColor) ?? 0xFF007AFF;
    chatBubbleColorNotifier.value = savedBubbleColor;
    chatWallpaperNotifier.value =
        p.getString(_keyChatWallpaperType) ?? 'default';
    notificationSoundNotifier.value = getNotificationSound();
  }

  // Setters & Helpers
  static Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    final p = await _getPrefs();
    await p.setInt(_keyThemeMode, mode.index);
  }

  static Future<void> setFontScale(double scale) async {
    final p = await _getPrefs();
    await p.setDouble(_keyFontScale, scale);
  }

  static Future<void> setPasscode(String code) async {
    final p = await _getPrefs();
    await p.setString(_keyPasscode, code);
  }

  static Future<void> setDuressPasscode(String code) async {
    final p = await _getPrefs();
    await p.setString(_keyDuressPasscode, code);
    CalculatorLogic.duressPasscode = code;
  }

  static String getDuressPasscode() =>
      _prefs?.getString(_keyDuressPasscode) ?? '4321';

  static Future<void> setPanicShake(bool enabled) async {
    final p = await _getPrefs();
    await p.setBool(_keyPanicShake, enabled);
  }

  static bool getPanicShake() => _prefs?.getBool(_keyPanicShake) ?? true;

  static Future<void> setDisguiseTitle(bool enabled) async {
    final p = await _getPrefs();
    await p.setBool(_keyDisguiseTitle, enabled);
  }

  static bool getDisguiseTitle() => _prefs?.getBool(_keyDisguiseTitle) ?? true;

  static Future<void> setEdgePanelEnabled(bool enabled) async {
    final p = await _getPrefs();
    await p.setBool(_keyEdgePanelEnabled, enabled);
    edgePanelEnabledNotifier.value = enabled;
  }

  static bool getEdgePanelEnabled() =>
      _prefs?.getBool(_keyEdgePanelEnabled) ?? true;

  static Future<void> setEdgePanelY(double relativeY) async {
    final p = await _getPrefs();
    await p.setDouble(_keyEdgePanelY, relativeY);
    edgePanelYNotifier.value = relativeY;
  }

  static double getEdgePanelY() => _prefs?.getDouble(_keyEdgePanelY) ?? 0.28;

  static Future<void> setPreventScreenshots(bool enabled) async {
    isChangingSettings = true;
    try {
      final p = await _getPrefs();
      await p.setBool(_keyScreenshotPrevent, enabled);
      await updateSecureFlag();
    } finally {
      Future.delayed(const Duration(milliseconds: 1000), () {
        isChangingSettings = false;
      });
    }
  }

  static bool getPreventScreenshots() =>
      _prefs?.getBool(_keyScreenshotPrevent) ?? true;

  static Future<void> setDisappearingTimer(String value) async {
    final p = await _getPrefs();
    await p.setString(_keyDisappearingTimer, value);
  }

  static String getDisappearingTimer() =>
      _prefs?.getString(_keyDisappearingTimer) ?? '24 hours';

  static Future<String?> getSystemHardwareDeviceId() async {
    try {
      final String? id = await _securityChannel.invokeMethod<String>(
        'getSystemDeviceId',
      );
      if (id != null && id.isNotEmpty) {
        return id;
      }
    } catch (e) {
      debugPrint('[AppPreferences] Get system hardware device ID failed: $e');
    }
    return null;
  }

  static Future<void> setDeviceId(String id) async {
    final p = await _getPrefs();
    await p.setString(_keyDeviceId, id);
    await p.setString(deviceIdKey, id);
  }

  static final ValueNotifier<String> displayNameNotifier =
      ValueNotifier<String>('Profile');
  static final ValueNotifier<String?> profileImagePathNotifier =
      ValueNotifier<String?>(null);

  static String? getDeviceIdSync() {
    return _prefs?.getString(_keyDeviceId) ?? _prefs?.getString(deviceIdKey);
  }

  static Future<void> setDisplayName(String name) async {
    final clean = name.trim();
    final p = await _getPrefs();
    await p.setString(_keyDisplayName, clean);
    displayNameNotifier.value = clean.isNotEmpty ? clean : 'Profile';
  }

  /// Removes the values tied to the currently signed-in account.
  static Future<void> clearAccountProfile() async {
    final p = await _getPrefs();
    await p.remove(_keyDisplayName);
    await p.remove(_keyProfileImagePath);
    await p.remove(_keyShowOnlineStatus);
    displayNameNotifier.value = 'Profile';
    profileImagePathNotifier.value = null;
  }

  static String getDisplayName() {
    final saved = _prefs?.getString(_keyDisplayName);
    if (saved != null && saved.trim().isNotEmpty) {
      return saved.trim();
    }
    return 'Profile';
  }

  static Future<void> setProfileImagePath(String path) async {
    final p = await _getPrefs();
    await p.setString(_keyProfileImagePath, path);
    profileImagePathNotifier.value = path;
  }

  static String? getProfileImagePath() {
    return _prefs?.getString(_keyProfileImagePath);
  }

  static bool getShowOnlineStatus() =>
      _prefs?.getBool(_keyShowOnlineStatus) ?? true;

  static Future<void> setShowOnlineStatus(bool enabled) async {
    final p = await _getPrefs();
    await p.setBool(_keyShowOnlineStatus, enabled);
  }

  static bool getHasConsented() => _prefs?.getBool(_keyHasConsented) ?? false;

  static Future<void> setHasConsented(bool value) async {
    final p = await _getPrefs();
    await p.setBool(_keyHasConsented, value);
  }

  static bool getAutoDownloadImages() =>
      _prefs?.getBool(_keyAutoDownloadImages) ?? true;

  static Future<void> setAutoDownloadImages(bool enabled) async {
    final p = await _getPrefs();
    await p.setBool(_keyAutoDownloadImages, enabled);
  }

  static bool getAutoDownloadVideos() =>
      _prefs?.getBool(_keyAutoDownloadVideos) ?? true;

  static Future<void> setAutoDownloadVideos(bool enabled) async {
    final p = await _getPrefs();
    await p.setBool(_keyAutoDownloadVideos, enabled);
  }

  static bool getAutoDownloadDocs() =>
      _prefs?.getBool(_keyAutoDownloadDocs) ?? true;

  static Future<void> setAutoDownloadDocs(bool enabled) async {
    final p = await _getPrefs();
    await p.setBool(_keyAutoDownloadDocs, enabled);
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
      final perChat = _prefs?.getInt('${_keyChatBubbleColor}_$chatId');
      if (perChat != null) return Color(perChat);
    }
    final colorInt = _prefs?.getInt(_keyChatBubbleColor) ?? 0xFF007AFF;
    return Color(colorInt);
  }

  static Future<void> setChatBubbleColor(Color color, {String? chatId}) async {
    final val = color.toARGB32();
    final p = await _getPrefs();
    if (chatId != null && chatId.isNotEmpty) {
      await p.setInt('${_keyChatBubbleColor}_$chatId', val);
    } else {
      await p.setInt(_keyChatBubbleColor, val);
    }
    chatBubbleColorNotifier.value = val;
  }

  static String getWallpaperType({String? chatId}) {
    if (chatId != null && chatId.isNotEmpty) {
      final perChat = _prefs?.getString('${_keyChatWallpaperType}_$chatId');
      if (perChat != null) return perChat;
    }
    return _prefs?.getString(_keyChatWallpaperType) ?? 'default';
  }

  static String? getWallpaperPath({String? chatId}) {
    if (chatId != null && chatId.isNotEmpty) {
      final perChat = _prefs?.getString('${_keyChatWallpaperPath}_$chatId');
      if (perChat != null && perChat.isNotEmpty) return perChat;
    }
    return _prefs?.getString(_keyChatWallpaperPath);
  }

  static double getWallpaperDim({String? chatId}) {
    if (chatId != null && chatId.isNotEmpty) {
      final perChat = _prefs?.getDouble('${_keyChatWallpaperDim}_$chatId');
      if (perChat != null) return perChat;
    }
    return _prefs?.getDouble(_keyChatWallpaperDim) ?? 0.15;
  }

  static Future<void> setChatWallpaper({
    required String type,
    String? customPath,
    double dim = 0.15,
    String? chatId,
  }) async {
    final p = await _getPrefs();
    if (chatId != null && chatId.isNotEmpty) {
      if (type == 'default' && (customPath == null || customPath.isEmpty)) {
        await p.remove('${_keyChatWallpaperType}_$chatId');
        await p.remove('${_keyChatWallpaperPath}_$chatId');
        await p.remove('${_keyChatWallpaperDim}_$chatId');
      } else {
        await p.setString('${_keyChatWallpaperType}_$chatId', type);
        if (customPath != null && customPath.isNotEmpty) {
          await p.setString(
            '${_keyChatWallpaperPath}_$chatId',
            customPath,
          );
        } else {
          await p.remove('${_keyChatWallpaperPath}_$chatId');
        }
        await p.setDouble('${_keyChatWallpaperDim}_$chatId', dim);
      }
    } else {
      await p.setString(_keyChatWallpaperType, type);
      if (customPath != null && customPath.isNotEmpty) {
        await p.setString(_keyChatWallpaperPath, customPath);
      } else {
        await p.remove(_keyChatWallpaperPath);
      }
      await p.setDouble(_keyChatWallpaperDim, dim);
    }
    chatWallpaperNotifier.value =
        '$type:${DateTime.now().millisecondsSinceEpoch}';
  }

  static const Map<String, Map<String, String>> notificationSounds = {
    'sound_1': {'name': 'Tone 1 - Chime', 'file': 'sound_1.wav'},
    'sound_2': {'name': 'Tone 2 - Gaming Lock', 'file': 'sound_2.wav'},
    'sound_3': {'name': 'Tone 3 - Interface Start', 'file': 'sound_3.wav'},
    'sound_4': {'name': 'Tone 4 - Interface Back', 'file': 'sound_4.wav'},
    'sound_5': {'name': 'Tone 5 - Pop Alert', 'file': 'sound_5.mp3'},
  };

  static String getNotificationSound() {
    return _prefs?.getString(_keyNotificationSound) ?? 'sound_1';
  }

  static String getNotificationSoundFileName([String? soundKey]) {
    final key = soundKey ?? getNotificationSound();
    return notificationSounds[key]?['file'] ?? '$key.wav';
  }

  static String getNotificationSoundLabel([String? soundKey]) {
    final key = soundKey ?? getNotificationSound();
    return notificationSounds[key]?['name'] ?? 'Tone 1 - Chime';
  }

  static Future<void> setNotificationSound(String sound) async {
    final p = await _getPrefs();
    await p.setString(_keyNotificationSound, sound);
    notificationSoundNotifier.value = sound;
  }
}
