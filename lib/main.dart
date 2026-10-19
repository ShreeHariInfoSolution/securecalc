import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'src/app.dart';
import 'src/core/config/app_config.dart';
import 'src/core/config/app_preferences.dart';
import 'src/core/config/environment.dart';
import 'src/features/chat/domain/services/deeplink/deep_link_handler.dart';
import 'src/features/chat/domain/services/local_chat_storage.dart';
import 'src/features/chat/domain/services/push_service.dart';
import 'src/features/chat/domain/services/server_api_service.dart';
import 'src/features/chat/domain/services/server_chat_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase App & Background Notification Handler
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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
