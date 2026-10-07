import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/core/widgets/typing_dots.dart';
import '../../domain/entities/chat_conversation.dart';

class ConversationTile extends StatelessWidget {
  final ChatConversation conversation;
  final bool isTyping;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    this.isTyping = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final formattedTime = conversation.lastMessageTime;
    final showTyping = isTyping || conversation.isTyping;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: AppTheme.primaryColor.withValues(alpha: 0.1),
        highlightColor: AppTheme.primaryColor.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          child: Row(
            children: [
              // iOS Avatar with Online Badge
              IosAvatar(
                name: conversation.name,
                imagePath: conversation.avatarUrl,
                isOnline: conversation.isOnline,
                size: 54,
                showOnline: true,
              ),
              const SizedBox(width: 14),

              // Tile Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Name + Timestamp
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            conversation.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: conversation.unreadCount > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        Text(
                          formattedTime,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                            color: conversation.unreadCount > 0
                                ? AppTheme.primaryColor
                                : AppTheme.subtitleGrey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),

                    // Bottom Row: Subtitle / Typing / Pins + Unread Badge
                    Row(
                      children: [
                        if (conversation.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 4.0),
                            child: Icon(Icons.push_pin_rounded,
                                size: 13, color: Colors.amber),
                          ),
                        if (conversation.isMuted)
                          const Padding(
                            padding: EdgeInsets.only(right: 4.0),
                            child: Icon(Icons.volume_off_rounded,
                                size: 13, color: Colors.grey),
                          ),
                        Expanded(
                          child: showTyping
                              ? Row(
                                  children: [
                                    Text(
                                      'typing',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const TypingDots(
                                      color: AppTheme.primaryColor,
                                      dotSize: 4.0,
                                    ),
                                  ],
                                )
                              : Text(
                                  conversation.lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: conversation.unreadCount > 0
                                        ? (isDark
                                            ? Colors.white
                                            : Colors.black)
                                        : AppTheme.subtitleGrey,
                                    fontWeight: conversation.unreadCount > 0
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                        ),
                        if (conversation.unreadCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${conversation.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
