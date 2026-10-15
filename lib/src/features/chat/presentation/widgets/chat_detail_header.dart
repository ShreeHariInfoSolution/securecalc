import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/widgets/ios_avatar.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/services/local_chat_storage.dart';

class ChatDetailHeader extends StatelessWidget {
  final ChatConversation conversation;
  final String chatName;
  final String chatAvatar;
  final ValueNotifier<bool> isPeerOnline;
  final ValueNotifier<bool> isPeerTyping;
  final VoidCallback onOpenChatInfo;
  final VoidCallback? onSearchMessages;
  final VoidCallback? onCallTap;

  const ChatDetailHeader({
    super.key,
    required this.conversation,
    required this.chatName,
    required this.chatAvatar,
    required this.isPeerOnline,
    required this.isPeerTyping,
    required this.onOpenChatInfo,
    this.onSearchMessages,
    this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.paddingOf(context).top;

    return ValueListenableBuilder<List<ChatConversation>>(
      valueListenable: LocalChatStorage.instance.conversationsNotifier,
      builder: (context, conversations, _) {
        final liveConv = conversations.cast<ChatConversation?>().firstWhere(
              (c) => c?.id == conversation.id,
              orElse: () => null,
            );

        final displayChatName = (liveConv != null &&
                liveConv.name.isNotEmpty &&
                !liveConv.name.startsWith('User #') &&
                !liveConv.name.startsWith('Chat #'))
            ? liveConv.name
            : (chatName.isNotEmpty ? chatName : conversation.name);

        final displayChatAvatar =
            (liveConv != null && liveConv.avatarUrl.isNotEmpty)
                ? liveConv.avatarUrl
                : (chatAvatar.isNotEmpty
                    ? chatAvatar
                    : conversation.avatarUrl);

        final unreadTotal = conversations.fold<int>(
          0,
          (sum, c) => sum + c.unreadCount,
        );

        return ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: EdgeInsets.only(
                top: topPadding + 6,
                bottom: 8,
                left: 10,
                right: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.transparent,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.50, 1.0],
                  colors: isDark
                      ? [
                          const Color(0xF21C1C1E),
                          const Color(0x881C1C1E),
                          const Color(0x1A1C1C1E),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.92),
                          Colors.white.withValues(alpha: 0.52),
                          Colors.white.withValues(alpha: 0.12),
                        ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // 1. Back Button (<)
                  GlassButton(
                    height: 40,
                    radius: 20,
                    isDark: isDark,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: unreadTotal > 0 ? 8 : 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chevron_left_rounded,
                            size: 28,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          if (unreadTotal > 0) ...[
                            const SizedBox(width: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white : Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$unreadTotal',
                                style: TextStyle(
                                  color: isDark ? Colors.black : Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // 2. Avatar Profile Pic + Name + Online/Offline Status (Clickable)
                  Expanded(
                    child: GestureDetector(
                      onTap: onOpenChatInfo,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          ValueListenableBuilder<bool>(
                            valueListenable: isPeerOnline,
                            builder: (context, online, _) {
                              return IosAvatar(
                                name: displayChatName,
                                imagePath: displayChatAvatar,
                                isOnline: online,
                                size: 42,
                                showOnline: true,
                              );
                            },
                          ),

                          const SizedBox(width: 10),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayChatName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.15,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                ValueListenableBuilder<bool>(
                                  valueListenable: isPeerTyping,
                                  builder: (context, typing, _) {
                                    return ValueListenableBuilder<bool>(
                                      valueListenable: isPeerOnline,
                                      builder: (context, online, _) {
                                        final String statusText;
                                        final Color statusColor;

                                        if (typing) {
                                          statusText = 'typing...';
                                          statusColor = const Color(0xFF34C759);
                                        } else if (online) {
                                          statusText = 'Online';
                                          statusColor = const Color(0xFF34C759);
                                        } else {
                                          statusText = 'Offline';
                                          statusColor = const Color(0xFF8E8E93);
                                        }

                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: statusColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              statusText,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: statusColor,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // 3. Right Action Buttons: Search + Info
                  if (onSearchMessages != null) ...[
                    GlassButton(
                      width: 38,
                      height: 38,
                      radius: 19,
                      isDark: isDark,
                      onTap: onSearchMessages,
                      child: Center(
                        child: Icon(
                          CupertinoIcons.search,
                          size: 18,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],

                  GlassButton(
                    width: 38,
                    height: 38,
                    radius: 19,
                    isDark: isDark,
                    onTap: onOpenChatInfo,
                    child: Center(
                      child: Icon(
                        CupertinoIcons.info,
                        size: 19,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class GlassSurface extends StatelessWidget {
  final double radius;
  final Widget? child;
  final bool isDark;

  const GlassSurface({
    super.key,
    required this.radius,
    this.child,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.85),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class GlassButton extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  final Widget child;
  final bool isDark;
  final VoidCallback? onTap;

  const GlassButton({
    super.key,
    this.width,
    this.height,
    required this.radius,
    required this.child,
    this.isDark = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: height,
        child: GlassSurface(
          radius: radius,
          isDark: isDark,
          child: child,
        ),
      ),
    );
  }
}
