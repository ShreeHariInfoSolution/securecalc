import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/app.dart';
import 'src/core/config/app_config.dart';
import 'src/core/config/app_preferences.dart';
import 'src/core/config/environment.dart';

import 'src/features/chat/domain/services/local_chat_storage.dart';
import 'src/features/chat/domain/services/server_api_service.dart';
import 'src/features/chat/domain/services/server_chat_manager.dart';

// Wi-Fi Local P2P direct socket disabled per server API integration preference
// import 'src/features/chat/domain/services/p2p_chat_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize App Configuration & Saved Preferences (Default to Production in release mode)
  AppConfig.initialize(kReleaseMode ? Environment.prod : Environment.dev);
  await AppPreferences.init();
  await LocalChatStorage.instance.init();

  // Initialize Server REST API & Socket Manager (https://synqerp.com/calculatorchat/api)
  await ServerApiService.instance.init();
  await ServerChatManager.instance.init();

  // Wi-Fi P2P Socket Chat commented out per instruction
  // await P2pChatService.instance.initializeSocket();

  // Render UI immediately
  runApp(const SynqChatApp());

  // Apply orientation lock asynchronously after initial frame
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,

    DeviceOrientation.portraitDown,
  ]);
}
