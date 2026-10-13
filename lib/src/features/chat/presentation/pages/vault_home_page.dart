import 'package:flutter/material.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import 'package:securecalc/src/features/calling/domain/services/device_identity_service.dart';
import '../../domain/services/deeplink/deep_link_handler.dart';
import '../../../../core/ui/vault_page_route.dart';
import 'conversation_list_page.dart';
import 'secret_settings_page.dart';
import 'vault_dashboard_page.dart';

class VaultHomePage extends StatefulWidget {
  final bool isDuressMode;

  const VaultHomePage({
    super.key,
    this.isDuressMode = false,
  });

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
        }
      }
    } else {
      await ServerChatManager.instance.init();
      if (mounted) {
        DeepLinkHandler.instance.init(context);
      }
    }
  }

  @override
  void dispose() {
    DeepLinkHandler.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoggingIn) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    // You can optionally check _error here and show a retry button, 
    // but currently we will just let it pass or show error state if strictly needed.
    // However, since prompt specifies "direct background direct log in... properly no nothing to add",
    // we'll proceed to the Vault wrapper.

    return ShakePanicWrapper(
      child: VaultEdgePanelWrapper(
        isDuressMode: widget.isDuressMode,
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
      ),
    );
  }
}
