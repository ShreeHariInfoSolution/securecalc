import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/core/widgets/typing_dots.dart';
import '../../domain/entities/chat_conversation.dart';

class ConversationTile extends StatelessWidget {
  final ChatConversation conversation;
  final bool isTyping;
  final VoidCallback onTap;
  final bool showDivider;

  const ConversationTile({
    super.key,
    required this.conversation,
    this.isTyping = false,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formattedTime = conversation.lastMessageTime;
    final showTyping = isTyping || conversation.isTyping;
    final hasUnread = conversation.unreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppTheme.primaryColor.withValues(alpha: 0.08),
        highlightColor: AppTheme.primaryColor.withValues(alpha: 0.04),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              child: Row(
                children: [
                  // Dynamic Far Left Unread Indicator Blue Dot
                  if (hasUnread) ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // iOS Avatar
                  IosAvatar(
                    name: conversation.name,
                    imagePath: conversation.avatarUrl,
                    isOnline: conversation.isOnline,
                    size: 54,
                    showOnline: true,
                  ),
                  const SizedBox(width: 12),

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
                                  fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                                  color: AppTheme.primaryText(isDark),
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formattedTime,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: hasUnread
                                    ? AppTheme.primaryText(isDark)
                                    : AppTheme.secondaryText(isDark),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 14,
                              color: AppTheme.secondaryText(isDark).withValues(alpha: 0.6),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),

                        // Bottom Row: Message Preview / Typing / Icons + Badge
                        Row(
                          children: [
                            if (conversation.isPinned)
                              const Padding(
                                padding: EdgeInsets.only(right: 4.0),
                                child: Icon(CupertinoIcons.pin_fill,
                                    size: 12, color: Colors.amber),
                              ),
                            if (conversation.isMuted)
                              Padding(
                                padding: const EdgeInsets.only(right: 4.0),
                                child: Icon(CupertinoIcons.bell_slash_fill,
                                    size: 12, color: AppTheme.secondaryText(isDark)),
                              ),
                            Expanded(
                              child: showTyping
                                  ? Row(
                                      children: [
                                        const Text(
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
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: hasUnread
                                            ? AppTheme.primaryText(isDark)
                                            : AppTheme.secondaryText(isDark),
                                        fontWeight: hasUnread
                                            ? FontWeight.w500
                                            : FontWeight.w400,
                                        height: 1.25,
                                      ),
                                    ),
                            ),
                            if (hasUnread && conversation.unreadCount > 1) ...[
                              const SizedBox(width: 6),
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor,
                                  borderRadius: BorderRadius.circular(9),
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
            if (showDivider)
              Padding(
                padding: const EdgeInsets.only(left: 84.0),
                child: Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: AppTheme.listDivider(isDark),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

