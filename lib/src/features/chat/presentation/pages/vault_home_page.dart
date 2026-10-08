import 'package:flutter/material.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';
import 'package:securecalc/src/features/auth/presentation/pages/auth_page.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
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
  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ServerApiService.instance.authToken != null;

    if (!isAuthenticated) {
      return AuthPage(
        onAuthSuccess: () {
          setState(() {});
        },
      );
    }

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
