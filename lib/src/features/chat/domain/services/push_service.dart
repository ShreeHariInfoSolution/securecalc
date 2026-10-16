import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_conversation.dart';

import '../../../../core/config/app_preferences.dart';
import 'local_chat_storage.dart';

final FlutterLocalNotificationsPlugin _local =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'chat', // must match default_notification_channel_id in AndroidManifest
  'Messages',
  importance: Importance.high,
);

bool _localReady = false;
int _badgeCount = 0;

Future<void> _updateBadge(int count) async {
  _badgeCount = count < 0 ? 0 : count;
  try {
    if (await AppBadgePlus.isSupported()) {
      await AppBadgePlus.updateBadge(_badgeCount);
      debugPrint('[Push Diagnostic] App badge updated to $_badgeCount');
    }
  } catch (e) {
    debugPrint('[Push Diagnostic ERROR] Badge update failed: $e');
  }
}

Future<void> _ensureLocalInit({
  void Function(NotificationResponse)? onTap,
}) async {
  if (_localReady) return;
  debugPrint('[Push Diagnostic] Initializing local notification plugin...');
  const init = InitializationSettings(
    android: AndroidInitializationSettings('@drawable/ic_notification'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );
  await _local.initialize(init, onDidReceiveNotificationResponse: onTap);
  await _local
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_channel);
  _localReady = true;
  debugPrint(
    '[Push Diagnostic] Local notification plugin initialized successfully.',
  );
}

Future<void> _showLocal(RemoteMessage m) async {
  final d = m.data;
  final chatIdStr = (d['chat_id'] ?? d['chatId'] ?? d['id'])?.toString();
  if (chatIdStr != null) {
    try {
      final conversations =
          LocalChatStorage.instance.conversationsNotifier.value;
      final conversation = conversations
          .cast<ChatConversation?>()
          .firstWhere((c) => c?.id == chatIdStr, orElse: () => null);
      if (conversation != null &&
          (conversation.isMuted || conversation.isArchived)) {
        debugPrint(
          '[Push Diagnostic] Skipping notification for muted/archived chat: ${conversation.name}',
        );
        return;
      }
    } catch (e) {
      debugPrint('[Push Diagnostic] Muted chat check exception: $e');
    }
  }

  debugPrint(
    '[Push Diagnostic] Processing RemoteMessage: messageId=${m.messageId}, data=${m.data}, notificationTitle=${m.notification?.title}, notificationBody=${m.notification?.body}',
  );
  final title = d['title'] ?? m.notification?.title ?? 'New message';
  final body = d['body'] ?? m.notification?.body ?? 'You have a new message';

  await _showNotificationWithDetails(
    id: (m.messageId ?? DateTime.now().toIso8601String()).hashCode,
    title: title,
    body: body,
    payload: jsonEncode(d),
  );
}

Future<void> _showNotificationWithDetails({
  required int id,
  required String title,
  required String body,
  required String payload,
}) async {
  try {
    await _updateBadge(_badgeCount + 1);
  } catch (e) {
    debugPrint('[Push Diagnostic] Badge update exception: $e');
  }

  String soundKey = 'sound_1';
  String soundFileName = 'sound_1.wav';
  try {
    soundKey = AppPreferences.getNotificationSound();
    soundFileName = AppPreferences.getNotificationSoundFileName(soundKey);
  } catch (e) {
    debugPrint('[Push Diagnostic WARNING] Sound preference exception: $e');
  }

  final channelId = 'chat_sound_$soundKey';

  debugPrint(
    '[Push Diagnostic] Preparing notification ($id): title="$title", sound="$soundKey" ($soundFileName)',
  );

  try {
    final soundChannel = AndroidNotificationChannel(
      channelId,
      'Messages',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound(soundKey),
    );

    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(soundChannel);

    await _local.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          soundChannel.id,
          soundChannel.name,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          color: const Color(0xFF007AFF),
          sound: RawResourceAndroidNotificationSound(soundKey),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
          sound: soundFileName,
        ),
      ),
      payload: payload,
    );
    debugPrint('[Push Diagnostic] Local notification successfully presented.');
  } catch (e) {
    debugPrint(
      '[Push Diagnostic WARNING] Failed to show custom sound notification ($e). Falling back to default channel...',
    );
    try {
      const defaultChannel = AndroidNotificationChannel(
        'chat',
        'Messages',
        importance: Importance.high,
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(defaultChannel);

      await _local.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'chat',
            'Messages',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@drawable/ic_notification',
            color: Color(0xFF007AFF),
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBadge: true,
          ),
        ),
        payload: payload,
      );
      debugPrint('[Push Diagnostic] Fallback default notification presented.');
    } catch (err) {
      debugPrint('[Push Diagnostic ERROR] Fallback notification failed: $err');
    }
  }
}

/// Runs in a separate isolate when the app is in background / killed.
/// MUST be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint(
    '[Push Diagnostic BACKGROUND] Handling background FCM message: messageId=${message.messageId}, data=${message.data}, title=${message.notification?.title}',
  );

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[Push Diagnostic BACKGROUND] Firebase init exception: $e');
  }

  try {
    await AppPreferences.init();
  } catch (e) {
    debugPrint('[Push Diagnostic BACKGROUND] AppPreferences init exception: $e');
  }

  try {
    await LocalChatStorage.instance.init();
  } catch (e) {
    debugPrint('[Push Diagnostic BACKGROUND] LocalChatStorage init exception: $e');
  }

  // If message has a notification payload, OS handles it natively when app is killed/background
  if (message.notification != null) {
    debugPrint('[Push Diagnostic BACKGROUND] Message has notification payload. Handled natively by OS.');
    if (Platform.isIOS) return;
  }

  await _ensureLocalInit();
  await _showLocal(message);
}

class PushService {
  PushService._();
  static final instance = PushService._();

  String baseUrl = 'https://synqerp.com/calculatorchat/api';
  Future<String?> Function()? getAuthToken;
  void Function(int chatId)? onOpenChat;
  bool Function(int chatId)? isChatOpen;

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  String? _token;

  String? get token => _token;

  /// Call once after Firebase.initializeApp()
  Future<void> init({
    required String baseUrl,
    required Future<String?> Function() getAuthToken,
    void Function(int chatId)? onOpenChat,
    bool Function(int chatId)? isChatOpen,
  }) async {
    this.baseUrl = baseUrl;
    this.getAuthToken = getAuthToken;
    this.onOpenChat = onOpenChat;
    this.isChatOpen = isChatOpen;

    debugPrint('[Push Diagnostic] Initializing PushService...');

    try {
      if (Platform.isAndroid) {
        final permStatus = await Permission.notification.request();
        debugPrint(
          '[Push Diagnostic] Android POST_NOTIFICATIONS status: $permStatus',
        );
      }

      final settings = await _fm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint(
        '[Push Diagnostic] Firebase Authorization Status: ${settings.authorizationStatus}',
      );

      await _ensureLocalInit(onTap: (r) => _openFromPayload(r.payload));

      await _fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // App in FOREGROUND
      FirebaseMessaging.onMessage.listen((m) async {
        debugPrint(
          '[Push Diagnostic FOREGROUND] Received FCM message: data=${m.data}, title=${m.notification?.title}',
        );
        final chatId = int.tryParse(
          '${m.data['chat_id'] ?? m.data['chatHeadId'] ?? ''}',
        );
        if (chatId != null && (this.isChatOpen?.call(chatId) ?? false)) {
          debugPrint(
            '[Push Diagnostic FOREGROUND] User is already inside chat $chatId. Suppressing notification banner.',
          );
          return;
        }
        await _showLocal(m);
      });

      // User tapped an OS-shown notification while app was in background
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        debugPrint(
          '[Push Diagnostic] Notification tapped from background: ${m.data}',
        );
        clearBadge();
        _openFromData(m.data);
      });

      // App was killed and opened by tapping an OS-shown notification
      final initial = await _fm.getInitialMessage();
      if (initial != null) {
        debugPrint(
          '[Push Diagnostic] App launched from killed state by FCM notification: ${initial.data}',
        );
        clearBadge();
        _openFromData(initial.data);
      }

      // App was killed and opened by tapping a local notification
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        debugPrint(
          '[Push Diagnostic] App launched from local notification tap.',
        );
        clearBadge();
        _openFromPayload(launch!.notificationResponse?.payload);
      }

      // Token rotates sometimes: keep the server in sync
      _fm.onTokenRefresh.listen((t) {
        debugPrint('[Push Diagnostic] FCM token refreshed: $t');
        _token = t;
        _register(t);
      });

      _token = await _fm.getToken();
      debugPrint('[Push Diagnostic] FCM Token obtained: $_token');

      if (_token != null) {
        await _register(_token!);
      }

      await printDiagnostics();
    } catch (e, stack) {
      debugPrint(
        '[Push Diagnostic ERROR] PushService init exception: $e\n$stack',
      );
    }
  }

  /// Triggers a test local notification instantly to verify system notification popups and sounds.
  Future<void> showTestNotification() async {
    debugPrint('[Push Diagnostic] Triggering manual test notification...');
    await _ensureLocalInit();
    await _showNotificationWithDetails(
      id: 88888,
      title: 'Test Notification',
      body: 'Push Notification service is working properly!',
      payload: jsonEncode({'chat_id': '1'}),
    );
  }

  /// Prints out comprehensive diagnostic info to console.
  Future<void> printDiagnostics() async {
    debugPrint('================= PUSH DIAGNOSTICS =================');
    debugPrint('Base URL: $baseUrl');
    final jwt = await getAuthToken?.call();
    debugPrint('JWT Token Present: ${jwt != null && jwt.isNotEmpty}');
    if (jwt != null && jwt.isNotEmpty) {
      debugPrint(
        'JWT Snippet: ${jwt.substring(0, math.min(15, jwt.length))}...',
      );
    }
    debugPrint('FCM Token: $_token');
    try {
      final settings = await _fm.getNotificationSettings();
      debugPrint(
        'FCM Permission AuthorizationStatus: ${settings.authorizationStatus}',
      );
    } catch (e) {
      debugPrint('FCM Permission Check Error: $e');
    }
    debugPrint('Is Local Notifications Plugin Initialized: $_localReady');
    debugPrint('====================================================');
  }

  /// Clears app icon notification count (badge) when app is opened or user views messages.
  Future<void> clearBadge() async {
    await _updateBadge(0);
  }

  /// Call right AFTER a successful login (needs the JWT).
  Future<void> registerAfterLogin() async {
    try {
      debugPrint('[Push Diagnostic] registerAfterLogin called.');
      _token ??= await _fm.getToken();
      if (_token != null) await _register(_token!);
    } catch (e) {
      debugPrint('[Push Diagnostic ERROR] Register after login error: $e');
    }
  }

  /// Call on logout BEFORE you clear the JWT.
  Future<void> unregisterOnLogout() async {
    try {
      debugPrint('[Push Diagnostic] unregisterOnLogout called.');
      final t = _token ?? await _fm.getToken();
      if (t != null) {
        final jwt = await getAuthToken?.call();
        if (jwt != null) {
          final res = await http.delete(
            Uri.parse('$baseUrl/devices'),
            headers: _headers(jwt),
            body: jsonEncode({'token': t}),
          );
          debugPrint(
            '[Push Diagnostic] Unregister device token response (${res.statusCode}): ${res.body}',
          );
        }
      }
      await _fm.deleteToken();
      _token = null;
    } catch (e) {
      debugPrint('[Push Diagnostic ERROR] Unregister on logout error: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      final jwt = await getAuthToken?.call();
      debugPrint('[Push Diagnostic] Registering FCM token to server...');
      debugPrint('[Push Diagnostic] Endpoint: $baseUrl/devices');
      debugPrint(
        '[Push Diagnostic] Platform: ${Platform.isIOS ? 'ios' : 'android'}',
      );
      debugPrint('[Push Diagnostic] Token: $token');
      if (jwt == null || jwt.isEmpty) {
        debugPrint(
          '[Push Diagnostic WARNING] Cannot register device token: JWT token is NULL or empty.',
        );
        return;
      }
      final response = await http.post(
        Uri.parse('$baseUrl/devices'),
        headers: _headers(jwt),
        body: jsonEncode({
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        }),
      );
      debugPrint(
        '[Push Diagnostic] Device token registration response (${response.statusCode}): ${response.body}',
      );
    } catch (e) {
      debugPrint('[Push Diagnostic ERROR] Register token error: $e');
    }
  }

  Map<String, String> _headers(String? jwt) => {
    'Content-Type': 'application/json',
    if (jwt != null) 'Authorization': 'Bearer $jwt',
  };

  void _openFromPayload(String? payload) {
    if (payload == null) return;
    try {
      _openFromData(Map<String, dynamic>.from(jsonDecode(payload)));
    } catch (_) {}
  }

  void _openFromData(Map<String, dynamic> data) {
    debugPrint(
      '[Push Diagnostic] Opening chat screen from notification data: $data',
    );
    final id = int.tryParse('${data['chat_id'] ?? data['chatHeadId'] ?? ''}');
    if (id != null) onOpenChat?.call(id);
  }
}
