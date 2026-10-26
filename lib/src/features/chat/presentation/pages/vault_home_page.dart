import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';
import 'package:securecalc/src/features/calculator/presentation/pages/calculator_page.dart';
import 'package:securecalc/src/features/calling/domain/services/device_identity_service.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';

import '../../domain/services/deeplink/deep_link_handler.dart';
import '../../domain/services/push_service.dart';
import '../../domain/services/server_chat_manager.dart';
import 'conversation_list_page.dart';

class VaultHomePage extends StatefulWidget {
  final bool isDuressMode;

  const VaultHomePage({super.key, this.isDuressMode = false});

  @override
  State<VaultHomePage> createState() => _VaultHomePageState();
}

class _VaultHomePageState extends State<VaultHomePage> {
  bool _isLoggingIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final isAuthenticated = ServerApiService.instance.authToken != null;
    if (!isAuthenticated) {
      setState(() {
        _isLoggingIn = true;
      });

      try {
        final deviceId = await DeviceIdentityService.instance.getDeviceId();
        debugPrint('====== DEVICE LOGIN ATTEMPT ======');
        debugPrint('Device ID: $deviceId');
        debugPrint('==================================');
        if (deviceId.isNotEmpty) {
          await ServerApiService.instance.deviceLogin(deviceId);
          await ServerChatManager.instance.init();
        }
      } catch (e) {
        debugPrint('Device login failed: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isLoggingIn = false;
          });
          DeepLinkHandler.instance.init(context);
          PushService.instance.initVault(context);
        }
      }
    } else {
      await ServerChatManager.instance.init();
      if (mounted) {
        DeepLinkHandler.instance.init(context);
        PushService.instance.initVault(context);
      }
    }
  }

  @override
  void dispose() {
    DeepLinkHandler.instance.dispose();
    PushService.instance.disposeVault();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoggingIn) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        FocusManager.instance.primaryFocus?.unfocus();
        FocusScope.of(context).unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, animation, secondaryAnimation) =>
                const CalculatorPage(),
          ),
          (route) => false,
        );
      },
      child: ShakePanicWrapper(
        child: VaultEdgePanelWrapper(
          isDuressMode: widget.isDuressMode,
          /*
          // VaultDashboardPage commented out - opening Chat list directly
          child: VaultDashboardPage(
            isDuressMode: widget.isDuressMode,
            onOpenChat: () {
              Navigator.of(context).push(
                VaultPageRoute(
                  builder: (context) => VaultEdgePanelWrapper(
                    isDuressMode: widget.isDuressMode,
                    child: ConversationListPage(
                      isDuressMode: widget.isDuressMode,
                    ),
                  ),
                ),
              );
            },
            onOpenSettings: () {
              Navigator.of(context).push(
                VaultPageRoute(
                  builder: (context) => const VaultEdgePanelWrapper(
                    child: SecretSettingsPage(),
                  ),
                ),
              );
            },
          ),
          */
          child: ConversationListPage(isDuressMode: widget.isDuressMode),
        ),
      ),
    );
  }
}
