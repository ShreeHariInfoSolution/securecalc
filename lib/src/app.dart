import 'dart:async';

import 'package:flutter/material.dart';

import 'core/config/app_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/font_size_controller.dart';
import 'core/theme/theme_controller.dart';
import 'features/calculator/presentation/pages/calculator_page.dart';
import 'features/chat/domain/services/call_service.dart';
import 'features/chat/domain/services/push_service.dart';
import 'features/chat/domain/services/server_api_service.dart';
import 'features/chat/domain/services/server_chat_manager.dart';
import 'features/chat/domain/services/socket_chat_service.dart';
import 'features/chat/presentation/widgets/global_call_overlay.dart';

/// Global key to access root navigator state from lifecycle events.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Root application widget disguised as a Calculator app.
class SynqChatApp extends StatefulWidget {
  const SynqChatApp({super.key});

  @override
  State<SynqChatApp> createState() => _SynqChatAppState();
}

class _SynqChatAppState extends State<SynqChatApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (AppPreferences.isPickerActive || AppPreferences.isChangingSettings) {
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(PushService.instance.clearBadge());
      if (ServerApiService.instance.authToken != null) {
        SocketChatService.instance.connect();
        unawaited(ServerChatManager.instance.syncChats());
      }
    }

    // Lock back to Calculator when app is minimized, sent to background, inactive, or in Recents App switcher.
    // Preserves active call state in CallService & GlobalCallOverlay while locking secret routes.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lockToCalculator();
    }
  }

  void _lockToCalculator() {
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) {
            return const CalculatorPage();
          },
        ),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    CallService.instance.hangUp();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: FontSizeController.instance,
      builder: (context, fontScale, child) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeController.instance,
          builder: (context, themeMode, child) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Calculator',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(fontScale)),
                  child: GlobalCallOverlay(child: child!),
                );
              },
              home: const CalculatorPage(),
            );
          },
        );
      },
    );
  }
}
