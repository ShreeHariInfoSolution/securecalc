import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/config/app_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/font_size_controller.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/keyboard_dismiss_observer.dart';
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
  static const _securityChannel = MethodChannel('com.shis.securecalc/security');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _securityChannel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') {
        _handleScreenshotTaken();
      }
    });
  }

  void _handleScreenshotTaken() {
    hideKeyboardNow();
    _lockToCalculator();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(PushService.instance.clearBadge());
      if (ServerApiService.instance.authToken != null) {
        SocketChatService.instance.connect();
        unawaited(ServerChatManager.instance.syncChats());
      }
      return;
    }

    // Lock back to Calculator on inactive (Recents App Switcher / Swipe Up / Screen Lock), paused, or hidden.
    // ALWAYS reset picker flags and lock to Calculator immediately to protect Recents snapshot buffer,
    // UNLESS a call is currently active or ringing.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      AppPreferences.isPickerActive = false;
      if (CallService.instance.state != CallState.idle) {
        return;
      }
      _lockToCalculator();
      return;
    }

    if (state == AppLifecycleState.inactive) {
      if (CallService.instance.state != CallState.idle) {
        return;
      }
      if (!AppPreferences.isChangingSettings) {
        _lockToCalculator();
      }
    }
  }

  void _lockToCalculator() {
    hideKeyboardNow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CallService.instance.isCalculatorVisibleNotifier.value = true;
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
    });
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
              navigatorObservers: [KeyboardDismissObserver()],
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
