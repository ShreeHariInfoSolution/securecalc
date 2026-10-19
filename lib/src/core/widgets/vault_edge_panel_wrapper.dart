import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/features/calculator/presentation/pages/calculator_page.dart';
import 'package:securecalc/src/features/chat/domain/entities/chat_conversation.dart';
import 'package:securecalc/src/features/chat/domain/services/local_chat_storage.dart';
import 'package:securecalc/src/features/chat/presentation/pages/chat_detail_page.dart';
import 'package:securecalc/src/features/chat/presentation/pages/conversation_list_page.dart';
import 'package:securecalc/src/features/chat/presentation/pages/secret_settings_page.dart';
import 'package:securecalc/src/features/private_folder/presentation/pages/private_folder_page.dart';

/// Compact Edge Bar Overlay for 1-tap direct navigation to Settings, Chat,
/// Pinned Chat Avatars (only if pinned), Private Folder, and Calculator Lock.
/// Supports vertical dragging (Hold & Move) and long-press to disable/reset.
class VaultEdgePanelWrapper extends StatefulWidget {
  final Widget child;
  final bool isDuressMode;

  const VaultEdgePanelWrapper({
    super.key,
    required this.child,
    this.isDuressMode = false,
  });

  @override
  State<VaultEdgePanelWrapper> createState() => _VaultEdgePanelWrapperState();
}

class _VaultEdgePanelWrapperState extends State<VaultEdgePanelWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  bool _isOpen = false;
  double? _topY;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _slideAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _togglePanel() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _closePanel() {
    if (_isOpen) {
      setState(() {
        _isOpen = false;
        _animationController.reverse();
      });
    }
  }

  void _openPrivateFolder(BuildContext context) {
    _closePanel();
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => const PrivateFolderPage(),
      ),
    );
  }

  void _showEdgePanelLongPressMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'EdgePanelMenu',
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, animation1, animation2) {
        return Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: 280,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xEE2C2C2E)
                        : const Color(0xF2F8F8F8),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.08),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Icon & Title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.view_sidebar_rounded,
                              color: AppTheme.primaryColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Edge Panel Shortcut',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                Text(
                                  'Floating handle controls',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      const SizedBox(height: 8),

                      // Option 1: Disable Edge Panel
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          _closePanel();
                          Navigator.pop(dialogContext);
                          await AppPreferences.setEdgePanelEnabled(false);
                          AppToast.show('Edge Panel disabled. Re-enable anytime in Settings.');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  CupertinoIcons.eye_slash_fill,
                                  color: Colors.redAccent,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Disable Edge Panel',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                    Text(
                                      'Hides floating handle everywhere',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Option 2: Reset Position
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          Navigator.pop(dialogContext);
                          await AppPreferences.setEdgePanelY(0.28);
                          if (mounted) {
                            setState(() {
                              _topY = MediaQuery.of(context).size.height * 0.28;
                            });
                          }
                          AppToast.show('Handle position reset');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF)
                                      .withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  CupertinoIcons.arrow_counterclockwise,
                                  color: Color(0xFF007AFF),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Reset Position',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      'Move handle back to default top',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Close Button
                      SizedBox(
                        width: double.infinity,
                        height: 38,
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(
                            'Close',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppPreferences.edgePanelEnabledNotifier,
      builder: (context, isEnabled, _) {
        if (!isEnabled) {
          return widget.child;
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final screenHeight = MediaQuery.of(context).size.height;

        return ValueListenableBuilder<double>(
          valueListenable: AppPreferences.edgePanelYNotifier,
          builder: (context, relativeY, _) {
            _topY ??= screenHeight * relativeY;
            final clampedY = _topY!.clamp(70.0, screenHeight - 320.0);

            return Stack(
              children: [
                // Main Screen Body Content
                widget.child,

                // Transparent Backdrop when panel is open
                if (_isOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _closePanel,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.25),
                      ),
                    ),
                  ),

                // Compact Vertical Icon Edge Bar
                ValueListenableBuilder<List<ChatConversation>>(
                  valueListenable: LocalChatStorage.instance.conversationsNotifier,
                  builder: (context, rawConversations, _) {
                    final conversations = widget.isDuressMode
                        ? <ChatConversation>[]
                        : rawConversations;
                    final pinnedConversations =
                        conversations.where((c) => c.isPinned).toList();
                    final unreadTotal =
                        conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);

                    return AnimatedBuilder(
                      animation: _slideAnimation,
                      builder: (context, child) {
                        const barWidth = 62.0;
                        final maxOffset = barWidth;
                        final currentOffset =
                            (1.0 - _slideAnimation.value) * maxOffset;

                        return Positioned(
                          right: -currentOffset,
                          top: clampedY,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(20),
                            ),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: Container(
                                width: barWidth,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1C1C1E).withValues(alpha: 0.94)
                                      : Colors.white.withValues(alpha: 0.94),
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(20),
                                  ),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : Colors.black.withValues(alpha: 0.1),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 14,
                                      offset: const Offset(-3, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 1. Collapse Chevron Arrow Button (Draggable Top Handle)
                                    GestureDetector(
                                      onVerticalDragUpdate: (details) {
                                        setState(() {
                                          _topY = (_topY! + details.delta.dy)
                                              .clamp(70.0, screenHeight - 320.0);
                                        });
                                      },
                                      onVerticalDragEnd: (_) {
                                        AppPreferences.setEdgePanelY(
                                            _topY! / screenHeight);
                                      },
                                      onTap: _togglePanel,
                                      onLongPress: () =>
                                          _showEdgePanelLongPressMenu(context),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.08)
                                              : Colors.black.withValues(alpha: 0.05),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          color: isDark ? Colors.white : Colors.black,
                                          size: 20,
                                        ),
                                      ),
                                    ),

                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 10),
                                      child: Divider(
                                          height: 1, indent: 10, endIndent: 10),
                                    ),

                                    // 2. Settings Icon Button
                                    _buildEdgeIconButton(
                                      icon: CupertinoIcons.gear_alt_fill,
                                      color: const Color(0xFFFF9500),
                                      tooltip: 'Settings',
                                      onTap: () {
                                        _closePanel();
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const SecretSettingsPage(),
                                          ),
                                        );
                                      },
                                    ),

                                    const SizedBox(height: 14),

                                    // 3. Chat Icon Button (With Badge)
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        _buildEdgeIconButton(
                                          icon: CupertinoIcons.chat_bubble_2_fill,
                                          color: const Color(0xFF007AFF),
                                          tooltip: 'Secret Chat',
                                          onTap: () {
                                            _closePanel();
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => ConversationListPage(
                                                  isDuressMode: widget.isDuressMode,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        if (unreadTotal > 0)
                                          Positioned(
                                            right: 4,
                                            top: 4,
                                            child: Container(
                                              width: 10,
                                              height: 10,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFFFF3B30),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),

                                    // 4. Pinned Chat Avatars (ONLY if pinned chats exist!)
                                    if (pinnedConversations.isNotEmpty) ...[
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 10),
                                        child: Divider(
                                            height: 1, indent: 10, endIndent: 10),
                                      ),
                                      ...pinnedConversations.take(3).map((conv) {
                                        return Padding(
                                          padding:
                                              const EdgeInsets.symmetric(vertical: 6),
                                          child: GestureDetector(
                                            onTap: () {
                                              _closePanel();
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) => ChatDetailPage(
                                                    conversation: conv,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                IosAvatar(
                                                  name: conv.name,
                                                  imagePath: conv.avatarUrl,
                                                  size: 38,
                                                  isOnline: conv.isOnline,
                                                ),
                                                Positioned(
                                                  right: -2,
                                                  top: -2,
                                                  child: Container(
                                                    padding: const EdgeInsets.all(2),
                                                    decoration: const BoxDecoration(
                                                      color: Colors.black,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.push_pin_rounded,
                                                      size: 10,
                                                      color: Colors.amber,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    ],

                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 10),
                                      child: Divider(
                                          height: 1, indent: 10, endIndent: 10),
                                    ),

                                    // 5. Private Folder Icon Button
                                    _buildEdgeIconButton(
                                      icon:
                                          CupertinoIcons.folder_fill_badge_person_crop,
                                      color: const Color(0xFFAF52DE),
                                      tooltip: 'Private Folder',
                                      onTap: () => _openPrivateFolder(context),
                                    ),

                                    const SizedBox(height: 14),

                                    // 6. Lock Calculator Icon Button
                                    _buildEdgeIconButton(
                                      icon: CupertinoIcons.lock_fill,
                                      color: const Color(0xFFFF3B30),
                                      tooltip: 'Lock Calculator',
                                      onTap: () {
                                        FocusManager.instance.primaryFocus?.unfocus();
                                        _closePanel();
                                        Navigator.of(context, rootNavigator: true)
                                            .pushAndRemoveUntil(
                                          PageRouteBuilder(
                                            transitionDuration: Duration.zero,
                                            reverseTransitionDuration: Duration.zero,
                                            pageBuilder: (context, a1, a2) =>
                                                const CalculatorPage(),
                                          ),
                                          (route) => false,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                // Floating Docked Handle Button (Draggable Arrow Tab on Right Edge when Collapsed)
                if (!_isOpen)
                  ValueListenableBuilder<List<ChatConversation>>(
                    valueListenable: LocalChatStorage.instance.conversationsNotifier,
                    builder: (context, rawConversations, _) {
                      final conversations = widget.isDuressMode
                          ? <ChatConversation>[]
                          : rawConversations;
                      final unreadTotal = conversations.fold<int>(
                          0, (sum, c) => sum + c.unreadCount);

                      return Positioned(
                        right: 0,
                        top: clampedY,
                        child: GestureDetector(
                          onVerticalDragUpdate: (details) {
                            setState(() {
                              _topY = (_topY! + details.delta.dy)
                                  .clamp(70.0, screenHeight - 320.0);
                            });
                          },
                          onVerticalDragEnd: (_) {
                            AppPreferences.setEdgePanelY(_topY! / screenHeight);
                          },
                          onTap: _togglePanel,
                          onLongPress: () =>
                              _showEdgePanelLongPressMenu(context),
                          child: Container(
                            height: 50,
                            padding: const EdgeInsets.only(left: 8, right: 4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1C1C1E).withValues(alpha: 0.95)
                                  : Colors.white.withValues(alpha: 0.95),
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(16),
                              ),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : Colors.black.withValues(alpha: 0.1),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 10,
                                  offset: const Offset(-2, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.chevron_left_rounded,
                                  color: AppTheme.primaryColor,
                                  size: 22,
                                ),
                                if (unreadTotal > 0) ...[
                                  const SizedBox(width: 2),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF3B30),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEdgeIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color,
          size: 20,
        ),
      ),
    );
  }
}
