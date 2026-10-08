import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/vault_motion.dart';
import '../../../../core/ui/vault_page_route.dart';
import '../../../../core/widgets/shake_panic_wrapper.dart';
import '../../../calculator/presentation/pages/calculator_page.dart';
import '../../../private_folder/presentation/pages/private_folder_page.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/services/local_chat_storage.dart';
import '../widgets/vault_action_card.dart';
import '../widgets/vault_dashboard_header.dart';
import '../widgets/vault_security_status_card.dart';

class VaultDashboardPage extends StatefulWidget {
  final VoidCallback onOpenChat;
  final VoidCallback onOpenSettings;
  final bool isDuressMode;

  const VaultDashboardPage({
    super.key,
    required this.onOpenChat,
    required this.onOpenSettings,
    this.isDuressMode = false,
  });

  @override
  State<VaultDashboardPage> createState() => _VaultDashboardPageState();
}

class _VaultDashboardPageState extends State<VaultDashboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: VaultMotion.pageTransitionDuration,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: VaultMotion.entryCurve,
      ),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: VaultMotion.entryCurve,
      ),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _openPrivateFolder(BuildContext context) {
    Navigator.push(
      context,
      VaultPageRoute(
        builder: (_) => const PrivateFolderPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ShakePanicWrapper(
      child: Scaffold(
        backgroundColor:
            isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        VaultDashboardHeader(
                          isDuressMode: widget.isDuressMode,
                          onOpenSettings: widget.onOpenSettings,
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'MAIN VAULT UTILITIES',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppTheme.subtitleGrey,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ValueListenableBuilder<List<ChatConversation>>(
                          valueListenable:
                              LocalChatStorage.instance.conversationsNotifier,
                          builder: (context, conversations, _) {
                            final unreadTotal = widget.isDuressMode
                                ? 0
                                : conversations.fold<int>(
                                    0, (sum, c) => sum + c.unreadCount);
                            final totalChats = widget.isDuressMode
                                ? 0
                                : conversations.length;

                            return VaultActionCard(
                              icon: CupertinoIcons.chat_bubble_2_fill,
                              iconGradient: const [
                                Color(0xFF007AFF),
                                Color(0xFF00C6FF)
                              ],
                              title: 'Chat',
                              subtitle: 'End-to-End Encrypted Messaging',
                              badgeText: unreadTotal > 0
                                  ? '$unreadTotal Unread'
                                  : '$totalChats Active Chats',
                              badgeColor: unreadTotal > 0
                                  ? const Color(0xFFFF3B30)
                                  : const Color(0xFF007AFF),
                              onTap: widget.onOpenChat,
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        VaultActionCard(
                          icon: CupertinoIcons.folder_fill_badge_person_crop,
                          iconGradient: const [
                            Color(0xFFAF52DE),
                            Color(0xFF5856D6)
                          ],
                          title: 'Private Folder',
                          subtitle: 'Encrypted Media Vault & Documents',
                          badgeText: 'Encrypted',
                          badgeColor: const Color(0xFFAF52DE),
                          onTap: () => _openPrivateFolder(context),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'SECURITY STATUS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppTheme.subtitleGrey,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const VaultSecurityStatusCard(),
                        const SizedBox(height: 24),
                        // Emergency Quick Lock Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFF3B30),
                              side: const BorderSide(color: Color(0xFFFF3B30)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(CupertinoIcons.lock_fill,
                                size: 20),
                            label: const Text(
                              'Lock Vault Immediately',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(context, rootNavigator: true)
                                  .pushAndRemoveUntil(
                                PageRouteBuilder(
                                  transitionDuration: Duration.zero,
                                  reverseTransitionDuration: Duration.zero,
                                  pageBuilder: (context, anim1, anim2) =>
                                      const CalculatorPage(),
                                ),
                                (route) => false,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 32),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
