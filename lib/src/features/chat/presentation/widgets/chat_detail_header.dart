import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';
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

  const ChatDetailHeader({
    super.key,
    required this.conversation,
    required this.chatName,
    required this.chatAvatar,
    required this.isPeerOnline,
    required this.isPeerTyping,
    required this.onOpenChatInfo,
    this.onSearchMessages,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.paddingOf(context).top;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(12.0, topPadding + 4.0, 12.0, 8.0),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.68)
                : Colors.white.withValues(alpha: 0.75),
          ),
          child: ValueListenableBuilder<List<ChatConversation>>(
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

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // iOS Back Button with Unread Badge
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2C2C2E).withValues(alpha: 0.75)
                            : Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.glassBorder(isDark),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.25 : 0.05,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.chevron_left,
                            size: 18,
                            color: AppTheme.primaryColor,
                          ),
                          if (unreadTotal > 0) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$unreadTotal',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Centered Identity Pill (Avatar + Name >)
                  Expanded(
                    child: GestureDetector(
                      onTap: onOpenChatInfo,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IosAvatar(
                            name: displayChatName,
                            imagePath: displayChatAvatar,
                            isOnline: isPeerOnline.value,
                            size: 42,
                            showOnline: true,
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C2C2E).withValues(alpha: 0.75)
                                  : Colors.white.withValues(alpha: 0.82),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.glassBorder(isDark),
                                width: 0.6,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    displayChatName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryText(isDark),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  CupertinoIcons.chevron_right,
                                  size: 12,
                                  color: AppTheme.secondaryText(isDark),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Glass Action Buttons
                  if (onSearchMessages != null) ...[
                    GestureDetector(
                      onTap: onSearchMessages,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2E).withValues(alpha: 0.75)
                              : Colors.white.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.glassBorder(isDark),
                            width: 0.8,
                          ),
                        ),
                        child: const Icon(
                          CupertinoIcons.search,
                          size: 18,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  GestureDetector(
                    onTap: onOpenChatInfo,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2C2C2E).withValues(alpha: 0.75)
                            : Colors.white.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.glassBorder(isDark),
                          width: 0.8,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.info,
                        size: 18,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

