import 'dart:ui';
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

  const ChatDetailHeader({
    super.key,
    required this.conversation,
    required this.chatName,
    required this.chatAvatar,
    required this.isPeerOnline,
    required this.isPeerTyping,
    required this.onOpenChatInfo,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.82)
                : Colors.white.withValues(alpha: 0.85),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: ValueListenableBuilder<List<ChatConversation>>(
            valueListenable: LocalChatStorage.instance.conversationsNotifier,
            builder: (context, conversations, _) {
              final unreadTotal = conversations.fold<int>(
                0,
                (sum, c) => sum + c.unreadCount,
              );

              return Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: unreadTotal > 0 ? 12 : 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2C2C2E).withValues(alpha: 0.85)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.3 : 0.06,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          if (unreadTotal > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '$unreadTotal',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: onOpenChatInfo,
                      borderRadius: BorderRadius.circular(16),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: isPeerOnline,
                        builder: (context, online, _) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: isPeerTyping,
                            builder: (context, typing, _) {
                              return Row(
                                children: [
                                  IosAvatar(
                                    name: chatName,
                                    imagePath: chatAvatar,
                                    isOnline: online,
                                    size: 38,
                                    showOnline: true,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          chatName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        Text(
                                          typing
                                              ? 'typing…'
                                              : online
                                              ? 'online'
                                              : 'Tap for info',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: typing || online
                                                ? AppTheme.primaryColor
                                                : AppTheme.subtitleGrey,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onOpenChatInfo,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2C2C2E).withValues(alpha: 0.85)
                            : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.3 : 0.06,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        size: 20,
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
