import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_conversation.dart';
import 'package:securecalc/src/features/chat/presentation/pages/bot_chat_detail_page.dart';
import 'package:securecalc/src/features/chat/presentation/pages/chat_detail_page.dart';

import '../../../../core/config/app_preferences.dart';
import '../../../../../firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_chat_storage.dart';
import 'call_kit_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_chat_manager.dart';

final FlutterLocalNotificationsPlugin _local =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'chat', // must match default_notification_channel_id in AndroidManifest
  'Messages',
  importance: Importance.high,
);

bool _localReady = false;
bool _onTapRegistered = false;
int _badgeCount = 0;

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  debugPrint(
    '[Push Diagnostic BACKGROUND TAP] Local notification tapped in background: ${notificationResponse.payload}',
  );
}

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

  if (Platform.isIOS) {
    try {
      const securityChannel = MethodChannel('com.shis.securecalc/security');
      await securityChannel.invokeMethod('updateBadgeCount', {'count': _badgeCount});
      debugPrint('[Push Diagnostic] Native iOS badge updated to $_badgeCount');
    } catch (e) {
      debugPrint('[Push Diagnostic ERROR] Native iOS badge update failed: $e');
    }
  }
}

/// Plays the currently configured app-side notification sound.
Future<void> playNotificationSound() async {
  try {
    final soundKey = AppPreferences.getNotificationSound();
    final soundFileName = AppPreferences.getNotificationSoundFileName(soundKey);
    final player = AudioPlayer();
    await player.play(
      AssetSource('sounds/$soundFileName'),
      mode: PlayerMode.lowLatency,
    );
  } catch (e) {
    debugPrint('[Push Diagnostic] Error playing notification sound: $e');
  }
}

Future<void> _ensureLocalInit({
  void Function(NotificationResponse)? onTap,
}) async {
  if (_localReady && (_onTapRegistered || onTap == null)) return;
  debugPrint(
    '[Push Diagnostic] Initializing local notification plugin (onTap provided: ${onTap != null})...',
  );
  const init = InitializationSettings(
    android: AndroidInitializationSettings('@drawable/ic_notification'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,
      defaultPresentSound: true,
      defaultPresentBadge: true,
    ),
  );
  await _local.initialize(
    init,
    onDidReceiveNotificationResponse: (response) {
      debugPrint('[Push Diagnostic] Local notification response received: ${response.payload}');
      PushService.instance.clearAllNotifications();
      if (onTap != null) {
        onTap(response);
      } else {
        PushService.instance._openFromPayload(response.payload);
      }
    },
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
  await _local
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_channel);
  _localReady = true;
  if (onTap != null) {
    _onTapRegistered = true;
  }
  debugPrint(
    '[Push Diagnostic] Local notification plugin initialized successfully.',
  );
}

Future<void> _showLocal(RemoteMessage m) async {
  final d = m.data;

  // 1. Suppress notification if message was sent by the current user
  final currentUserId = ServerApiService.instance.currentUserId?.toString();
  final senderId = (d['sender_id'] ??
          d['senderId'] ??
          d['sender_user_id'] ??
          d['from_id'] ??
          d['fromId'] ??
          d['user_id'] ??
          d['userId'])
      ?.toString();

  if (currentUserId != null &&
      senderId != null &&
      currentUserId == senderId) {
    debugPrint(
      '[Push Diagnostic] Suppressing notification for outgoing message sent by current user ($currentUserId)',
    );
    return;
  }

  // 2. Suppress notification if user is currently inside the active chat screen
  final chatIdStr = (d['chat_id'] ??
          d['chatId'] ??
          d['chat_head_id'] ??
          d['chatHeadId'] ??
          d['id'])
      ?.toString();
  final chatIdInt = int.tryParse(chatIdStr ?? '');

  if (chatIdInt != null &&
      (PushService.instance.isChatOpen?.call(chatIdInt) ?? false)) {
    debugPrint(
      '[Push Diagnostic] User is currently inside active chat $chatIdInt. Suppressing notification banner.',
    );
    return;
  }

  // 3. Suppress notification for muted or archived chats
  if (chatIdStr != null && chatIdStr.isNotEmpty) {
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
          autoCancel: true,
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
            autoCancel: true,
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

int? _extractChatIdFromData(Map<String, dynamic>? data) {
  if (data == null) return null;

  for (final key in ['chat_head_id', 'chat_id', 'chatId', 'chatHeadId', 'id']) {
    final val = data[key];
    if (val != null) {
      final parsed = int.tryParse(val.toString());
      if (parsed != null && parsed > 0) return parsed;
    }
  }

  final nested = data['data'] ?? data['payload'];
  if (nested is Map<String, dynamic>) {
    return _extractChatIdFromData(nested);
  } else if (nested is Map) {
    return _extractChatIdFromData(Map<String, dynamic>.from(nested));
  } else if (nested is String) {
    try {
      final decoded = jsonDecode(nested);
      if (decoded is Map<String, dynamic>) {
        return _extractChatIdFromData(decoded);
      } else if (decoded is Map) {
        return _extractChatIdFromData(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
  }

  return null;
}

String? _extractSenderIdFromData(Map<String, dynamic>? data) {
  if (data == null) return null;

  for (final key in [
    'sender_id',
    'senderId',
    'sender_user_id',
    'from_id',
    'fromId',
    'user_id',
    'userId'
  ]) {
    final val = data[key];
    if (val != null) {
      final str = val.toString().trim();
      if (str.isNotEmpty) return str;
    }
  }

  final nested = data['data'] ?? data['payload'];
  if (nested is Map<String, dynamic>) {
    return _extractSenderIdFromData(nested);
  } else if (nested is Map) {
    return _extractSenderIdFromData(Map<String, dynamic>.from(nested));
  } else if (nested is String) {
    try {
      final decoded = jsonDecode(nested);
      if (decoded is Map<String, dynamic>) {
        return _extractSenderIdFromData(decoded);
      } else if (decoded is Map) {
        return _extractSenderIdFromData(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
  }

  return null;
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
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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

  // Automatically report message as delivered via REST API in background
  try {
    final chatId = _extractChatIdFromData(message.data);
    final senderId = _extractSenderIdFromData(message.data);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('PREF_SERVER_AUTH_TOKEN');
    final currentUserId =
        prefs.getInt('PREF_SERVER_USER_ID')?.toString() ??
        prefs.getString('PREF_SERVER_USER_ID');

    if (chatId != null &&
        token != null &&
        token.isNotEmpty &&
        (currentUserId == null || senderId == null || currentUserId != senderId)) {
      final url = 'https://synqerp.com/calculatorchat/api/chats/delivered';
      final res = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'chat_head_id': chatId,
          'chat_id': chatId,
          'chatId': chatId,
        }),
      );
      debugPrint(
        '[Push Diagnostic BACKGROUND] Delivery API status (${res.statusCode}): ${res.body}',
      );
    }
  } catch (e) {
    debugPrint('[Push Diagnostic BACKGROUND] Delivery status update exception: $e');
  }

  // Handle Call push notifications
  final data = message.data;
  final type = data['type']?.toString();
  final rawCallId = data['call_id'] ?? data['callId'];
  final callId = int.tryParse(rawCallId?.toString() ?? '');

  if (type == 'incoming_call' || (callId != null && data['status'] == 'ringing')) {
    final chatHeadId = int.tryParse((data['chat_head_id'] ?? data['chatId'])?.toString() ?? '0') ?? 0;
    final callerId = int.tryParse((data['caller_id'] ?? data['sender_id'])?.toString() ?? '0') ?? 0;
    final callerName = data['caller_name']?.toString() ?? 'Incoming Call';
    final callType = data['call_type']?.toString() ?? 'voice';

    await CallKitService.instance.showIncomingCall(
      callId: callId!,
      chatHeadId: chatHeadId,
      callerId: callerId,
      callerName: callerName,
      callType: callType,
    );
    return;
  }

  if (type == 'call_ended' ||
      ['ended', 'cancelled', 'rejected', 'missed', 'busy'].contains(data['status'])) {
    if (callId != null) {
      await CallKitService.instance.endCall(callId.toString());
    } else {
      await CallKitService.instance.clearAll();
    }
    return;
  }

  // If message has a notification payload, OS handles it natively when app is killed/background
  if (message.notification != null) {
    debugPrint('[Push Diagnostic BACKGROUND] Message has notification payload. Handled natively by OS.');
    return;
  }

  await _ensureLocalInit();
  await _showLocal(message);
}

class PushService {
  PushService._();
  static final instance = PushService._();

  static const _securityChannel = MethodChannel('com.shis.securecalc/security');

  String baseUrl = 'https://synqerp.com/calculatorchat/api';
  Future<String?> Function()? getAuthToken;
  void Function(int chatId)? onOpenChat;
  bool Function(int chatId)? isChatOpen;
  String? Function()? getActiveChatId;

  bool _isVaultReady = false;
  BuildContext? _vaultContext;
  int? _pendingChatId;

  FirebaseMessaging get _fm => FirebaseMessaging.instance;
  String? _token;

  String? get token => _token;

  Future<void> updateNativeActiveChatId(String? chatId) async {
    if (!Platform.isIOS) return;
    try {
      await _securityChannel.invokeMethod('updateActiveChatId', {
        'activeChatId': chatId,
      });
      debugPrint('[Push Diagnostic] Updated native iOS activeChatId: $chatId');
    } catch (e) {
      debugPrint('[Push Diagnostic ERROR] Failed to update native activeChatId: $e');
    }
  }

  Future<void> updateNativeCurrentUserId(String? userId) async {
    if (!Platform.isIOS) return;
    try {
      await _securityChannel.invokeMethod('updateCurrentUserId', {
        'currentUserId': userId,
      });
      debugPrint('[Push Diagnostic] Updated native iOS currentUserId: $userId');
    } catch (e) {
      debugPrint('[Push Diagnostic ERROR] Failed to update native currentUserId: $e');
    }
  }

  /// Call this when the vault is fully unlocked and authenticated (e.g. in VaultHomePage).
  void initVault(BuildContext context) {
    _isVaultReady = true;
    _vaultContext = context;

    if (_pendingChatId != null) {
      final chatId = _pendingChatId!;
      _pendingChatId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          _navigateToChat(context, chatId);
        }
      });
    }
  }

  void disposeVault() {
    _isVaultReady = false;
    _vaultContext = null;
  }

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
    ServerChatManager.instance.onActiveChatIdChanged =
        (val) => unawaited(updateNativeActiveChatId(val));

    debugPrint('[Push Diagnostic] Initializing PushService...');

    try {
      await updateNativeCurrentUserId(
        ServerApiService.instance.currentUserId?.toString(),
      );
      await updateNativeActiveChatId(
        getActiveChatId?.call(),
      );

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

      await _ensureLocalInit(onTap: (r) {
        clearAllNotifications();
        _openFromPayload(r.payload);
      });

      CallKitService.instance.initListener();

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

        final msgType = m.data['type']?.toString();
        if (msgType == 'incoming_call' || msgType == 'call_ended') {
          debugPrint('[Push Diagnostic FOREGROUND] Call FCM event ($msgType). Handled by CallService/CallKit.');
          return;
        }

        final chatId = _extractChatIdFromData(m.data);
        final senderId = _extractSenderIdFromData(m.data);
        final currentUserId = ServerApiService.instance.currentUserId?.toString();

        // Report message as delivered to server
        if (chatId != null &&
            (currentUserId == null || senderId == null || currentUserId != senderId)) {
          unawaited(ServerApiService.instance.markDeliveredREST(chatId: chatId));
        }

        if (currentUserId != null &&
            senderId != null &&
            currentUserId == senderId) {
          debugPrint(
            '[Push Diagnostic FOREGROUND] Message was sent by current user. Suppressing notification.',
          );
          return;
        }

        if (chatId != null && (this.isChatOpen?.call(chatId) ?? false)) {
          debugPrint(
            '[Push Diagnostic FOREGROUND] User is already inside chat $chatId. Suppressing notification banner.',
          );
          return;
        }
        if (Platform.isIOS && m.notification != null) {
          debugPrint(
            '[Push Diagnostic FOREGROUND] iOS notification presented natively via APNs banner.',
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
        clearAllNotifications();
        _openFromData(m.data);
      });

      // App was killed and opened by tapping an OS-shown notification
      final initial = await _fm.getInitialMessage();
      if (initial != null) {
        debugPrint(
          '[Push Diagnostic] App launched from killed state by FCM notification: ${initial.data}',
        );
        clearAllNotifications();
        _openFromData(initial.data);
      }

      // App was killed and opened by tapping a local notification
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        debugPrint(
          '[Push Diagnostic] App launched from local notification tap.',
        );
        clearAllNotifications();
        _openFromPayload(launch!.notificationResponse?.payload);
      }

      // Token rotates sometimes: keep the server in sync
      _fm.onTokenRefresh.listen((t) {
        debugPrint('[Push Diagnostic] FCM token refreshed: $t');
        _token = t;
        _register(t);
      });

      _token = await _safeGetFcmToken();
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
    if (Platform.isIOS) {
      try {
        final apns = await _fm.getAPNSToken();
        debugPrint('APNs Token Present: ${apns != null && apns.isNotEmpty}');
        if (apns != null) debugPrint('APNs Token: $apns');
      } catch (e) {
        debugPrint('APNs Token Error: $e');
      }
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

  /// Clears app icon notification count (badge) and cancels all delivered notifications in OS notification center.
  Future<void> clearAllNotifications() async {
    try {
      await _ensureLocalInit();
      await _local.cancelAll();
      await _updateBadge(0);

      if (Platform.isIOS) {
        try {
          await _securityChannel.invokeMethod('clearAllNotifications');
          debugPrint('[Push Diagnostic] Native iOS notifications cleared via MethodChannel.');
        } catch (e) {
          debugPrint('[Push Diagnostic ERROR] Native iOS notification clear failed: $e');
        }
      } else if (Platform.isAndroid) {
        try {
          await _securityChannel.invokeMethod('clearAllNotifications');
          debugPrint('[Push Diagnostic] Native Android notifications cleared via MethodChannel.');
        } catch (e) {
          debugPrint('[Push Diagnostic ERROR] Native Android notification clear failed: $e');
        }
      }

      debugPrint('[Push Diagnostic] Cleared all local and native notifications and badge count.');
    } catch (e) {
      debugPrint('[Push Diagnostic ERROR] Failed to clear all notifications: $e');
    }
  }

  /// Clears app icon notification count (badge) when app is opened or user views messages.
  Future<void> clearBadge() async {
    await clearAllNotifications();
  }

  /// Updates the app icon badge count directly to the total unread messages count.
  Future<void> updateBadgeTo(int count) async {
    await _updateBadge(count);
  }

  Future<String?> _safeGetFcmToken() async {
    if (Platform.isIOS) {
      debugPrint('[Push Diagnostic] Checking iOS APNs Token status...');
      String? apnsToken;
      for (int i = 0; i < 15; i++) {
        try {
          apnsToken = await _fm.getAPNSToken();
          if (apnsToken != null && apnsToken.isNotEmpty) {
            debugPrint('[Push Diagnostic] APNs Token ready (attempt ${i + 1}): $apnsToken');
            break;
          }
        } catch (e) {
          debugPrint(
            '[Push Diagnostic] APNs check attempt ${i + 1} warning: $e',
          );
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      if (apnsToken == null) {
        debugPrint(
          '[Push Diagnostic WARNING] APNs Token is null after waiting 15s. Ensure Push Notification capability is added in Xcode and APNs key is uploaded in Firebase.',
        );
      }
    }

    for (int retry = 0; retry < 5; retry++) {
      try {
        final token = await _fm.getToken();
        if (token != null && token.isNotEmpty) {
          return token;
        }
      } catch (e) {
        debugPrint(
          '[Push Diagnostic ERROR] Failed to obtain FCM Token (attempt ${retry + 1}): $e',
        );
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  /// Call right AFTER a successful login (needs the JWT).
  Future<void> registerAfterLogin() async {
    try {
      debugPrint('[Push Diagnostic] registerAfterLogin called.');
      await updateNativeCurrentUserId(
        ServerApiService.instance.currentUserId?.toString(),
      );
      _token ??= await _safeGetFcmToken();
      if (_token != null) {
        await _register(_token!);
      } else {
        debugPrint('[Push Diagnostic WARNING] FCM token still null, starting background retry listener...');
        _startBackgroundTokenRegistration();
      }
    } catch (e) {
      debugPrint('[Push Diagnostic ERROR] Register after login error: $e');
    }
  }

  void _startBackgroundTokenRegistration() {
    int attempts = 0;
    Timer.periodic(const Duration(seconds: 4), (timer) async {
      attempts++;
      _token ??= await _safeGetFcmToken();
      if (_token != null) {
        await _register(_token!);
        timer.cancel();
      } else if (attempts >= 8) {
        timer.cancel();
        debugPrint('[Push Diagnostic ERROR] Background token registration retries exhausted.');
      }
    });
  }

  /// Call on logout BEFORE you clear the JWT.
  Future<void> unregisterOnLogout() async {
    try {
      debugPrint('[Push Diagnostic] unregisterOnLogout called.');
      await updateNativeCurrentUserId(null);
      await updateNativeActiveChatId(null);
      final t = _token ?? await _safeGetFcmToken();
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

  /// Call when user changes notification sound in settings
  Future<void> updateNotificationSound(String soundKey) async {
    try {
      debugPrint('[Push Diagnostic] Updating device notification sound to: $soundKey');
      final soundFileName = AppPreferences.getNotificationSoundFileName(soundKey);

      // 1. Send update request to PUT /auth/notification-sound REST API
      await ServerApiService.instance.updateNotificationSoundREST(soundFileName);

      // 2. Re-register FCM token with updated sound preference
      final t = _token ?? await _safeGetFcmToken();
      if (t != null) {
        await _register(t);
      }
    } catch (e) {
      debugPrint('[Push Diagnostic ERROR] Failed to update notification sound: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      final jwt = await getAuthToken?.call();
      final soundKey = AppPreferences.getNotificationSound();
      final soundFileName = AppPreferences.getNotificationSoundFileName(soundKey);

      debugPrint('[Push Diagnostic] Registering FCM token to server...');
      debugPrint('[Push Diagnostic] Endpoint: $baseUrl/devices');
      debugPrint(
        '[Push Diagnostic] Platform: ${Platform.isIOS ? 'ios' : 'android'}, Sound: $soundFileName ($soundKey)',
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
          'sound': soundFileName,
          'sound_key': soundKey,
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
    clearAllNotifications();
    if (payload == null) return;
    try {
      _openFromData(Map<String, dynamic>.from(jsonDecode(payload)));
    } catch (_) {}
  }

  void _openFromData(Map<String, dynamic> data) {
    debugPrint(
      '[Push Diagnostic] Opening chat screen from notification data: $data',
    );
    clearAllNotifications();
    final id = int.tryParse('${data['chat_id'] ?? data['chatHeadId'] ?? ''}');

    if (id != null) {
      _pendingChatId = id;
    }

    if (_isVaultReady && _vaultContext != null && _vaultContext!.mounted) {
      if (_pendingChatId != null) {
        final chatId = _pendingChatId!;
        _pendingChatId = null;
        _navigateToChat(_vaultContext!, chatId);
      }
    } else {
      debugPrint(
        '[Push Diagnostic] Vault is currently locked on Calculator screen. Stored pending chatId $id for navigation after passcode unlock.',
      );
    }
  }

  Future<void> _navigateToChat(BuildContext context, int chatId) async {
    try {
      if (!context.mounted) return;
      if (ServerApiService.instance.authToken == null) return;
      if (isChatOpen?.call(chatId) ?? false) return;

      onOpenChat?.call(chatId);

      final conversations = await LocalChatStorage.instance.loadConversations();
      final match = conversations.cast<ChatConversation?>().firstWhere(
        (c) => c?.id == chatId.toString(),
        orElse: () => null,
      );

      ChatConversation? targetConv = match;

      if (targetConv == null) {
        final serverChat = await ServerApiService.instance.getChatDetails(chatId);
        if (serverChat != null) {
          final peer = serverChat.members.firstWhere(
            (m) => m.id != ServerApiService.instance.currentUserId,
            orElse: () => serverChat.members.first,
          );
          targetConv = ChatConversation(
            id: serverChat.id.toString(),
            name: serverChat.isGroup
                ? (serverChat.groupName ?? 'Group')
                : peer.name,
            avatarUrl: serverChat.isGroup
                ? (serverChat.groupAvatar ?? '')
                : (peer.avatar ?? ''),
            lastMessage: '',
            lastMessageTime: '',
            unreadCount: 0,
            isOnline: peer.isOnline,
            isGroup: serverChat.isGroup,
            messages: const [],
          );
        }
      }

      if (targetConv != null && context.mounted) {
        if (targetConv.id == 'assistant' || targetConv.id == 'bot') {
          BotChatDetailPage.open(context, conversation: targetConv);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => VaultEdgePanelWrapper(
                child: ChatDetailPage(conversation: targetConv!),
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[Push] Error opening chat $chatId: $e');
    }
  }
}
