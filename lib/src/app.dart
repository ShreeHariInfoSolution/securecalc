import 'package:flutter/material.dart';
import 'core/config/app_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/font_size_controller.dart';
import 'core/theme/theme_controller.dart';
import 'features/calculator/presentation/pages/calculator_page.dart';

/// Global key to access root navigator state from lifecycle events.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Root application widget disguised as a Calculator app.
class SynqChatApp extends StatefulWidget {
  const SynqChatApp({super.key});

  @override
  State<SynqChatApp> createState() => _SynqChatAppState();
}

class _SynqChatAppState extends State<SynqChatApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (AppPreferences.isPickerActive || AppPreferences.isChangingSettings) return;

    // Instantly lock back to Calculator whenever app is minimized, sent to background, or becomes inactive/hidden
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
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
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(fontScale),
                  ),
                  child: child!,
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
