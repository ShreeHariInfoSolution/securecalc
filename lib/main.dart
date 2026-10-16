import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app.dart';
import 'src/core/config/app_config.dart';
import 'src/core/config/app_preferences.dart';
import 'src/core/config/environment.dart';
import 'src/core/ui/vault_page_route.dart';
import 'src/features/chat/domain/entities/chat_conversation.dart';
import 'src/features/chat/domain/services/deeplink/deep_link_handler.dart';
import 'src/features/chat/domain/services/local_chat_storage.dart';
import 'src/features/chat/domain/services/push_service.dart';
import 'src/features/chat/domain/services/server_api_service.dart';
import 'src/features/chat/domain/services/server_chat_manager.dart';
import 'src/features/chat/presentation/pages/chat_detail_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase App & Background Notification Handler
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[Firebase] Initialize error: $e');
  }

  // Initialize App Configuration & Saved Preferences
  AppConfig.initialize(kReleaseMode ? Environment.prod : Environment.dev);
  await AppPreferences.init();
  await LocalChatStorage.instance.init();

  // Initialize Server REST API & Socket Manager
  await ServerApiService.instance.init();
  await ServerChatManager.instance.init();

  // Initialize Push Notification Service
  await PushService.instance.init(
    baseUrl: ServerApiService.baseUrl,
    getAuthToken: () async => ServerApiService.instance.authToken,
    isChatOpen: (chatId) =>
        ServerChatManager.instance.activeChatId == chatId.toString(),
    onOpenChat: _handleOpenChatNotification,
  );

  if (ServerApiService.instance.authToken != null) {
    await PushService.instance.registerAfterLogin();
  }

  // Start buffering deep links securely in the background
  DeepLinkHandler.instance.startListening();

  // Render UI immediately
  runApp(const SynqChatApp());

  // Apply orientation lock asynchronously after initial frame
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
}

void _handleOpenChatNotification(int chatId) async {
  try {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (ServerApiService.instance.authToken == null) return;

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

    if (targetConv != null && nav.mounted) {
      nav.push(
        VaultPageRoute(
          builder: (_) => ChatDetailPage(conversation: targetConv!),
        ),
      );
    }
  } catch (e) {
    debugPrint('[Push] Error opening chat $chatId: $e');
  }
}
