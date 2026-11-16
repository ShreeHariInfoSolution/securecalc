import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/widgets/ios_avatar.dart';
import 'package:securecalc/src/core/widgets/typing_dots.dart';
import 'package:securecalc/src/features/chat/domain/services/local_chat_storage.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/bot_assistant_service.dart';
import '../../domain/services/presence_store.dart';
import 'sticker_picker_panel.dart';

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

    final draftText = LocalChatStorage.instance.getDraft(conversation.id);
    final hasDraft = draftText != null && draftText.trim().isNotEmpty;

    final lastMsg = conversation.messages.isNotEmpty
        ? conversation.messages.last
        : null;

    final isLastMsgFromMe = lastMsg != null && lastMsg.senderId == 'user';

    IconData? statusIcon;
    Color? statusColor;

    if (isLastMsgFromMe) {
      final status = lastMsg.messageStatus;
      if (status == MessageStatus.sending) {
        statusIcon = Icons.access_time_rounded;
        statusColor = AppTheme.secondaryText(isDark);
      } else if (status == MessageStatus.read) {
        statusIcon = Icons.done_all_rounded;
        statusColor = const Color(0xFF53BDEB);
      } else if (status == MessageStatus.delivered) {
        statusIcon = Icons.done_all_rounded;
        statusColor = AppTheme.secondaryText(isDark);
      } else {
        statusIcon = Icons.done_rounded;
        statusColor = AppTheme.secondaryText(isDark);
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppTheme.primaryColor.withValues(alpha: 0.08),
        highlightColor: AppTheme.primaryColor.withValues(alpha: 0.04),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 10.0,
              ),
              child: Row(
                children: [
                  // iOS Avatar
                  ValueListenableBuilder<Map<int, PresenceState>>(
                    valueListenable: PresenceStore.instance.presenceNotifier,
                    builder: (context, presenceMap, _) {
                      final presence = PresenceStore.instance.getPresenceForChat(
                        peerUserId: conversation.peerUserId,
                        chatId: conversation.id,
                        isGroup: conversation.isGroup,
                      );
                      final isOnline = presence != null ? presence.isOnline : conversation.isOnline;
                      return IosAvatar(
                        name: conversation.name,
                        imagePath: conversation.avatarUrl,
                        isOnline: isOnline,
                        size: 54,
                        showOnline: true,
                      );
                    },
                  ),
                  const SizedBox(width: 12),

                  // Tile Text Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Row: Name + Timestamp
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      conversation.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: hasUnread
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: AppTheme.primaryText(isDark),
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ),
                                  if (conversation.id == BotAssistantService.botId ||
                                      conversation.name.contains('Calnox AI')) ...[
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF007AFF)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'AI BOT',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF007AFF),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formattedTime,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: hasUnread
                                    ? AppTheme.primaryColor
                                    : AppTheme.secondaryText(isDark),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Bottom Row: Message Preview / Typing / Icons + Badge
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
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
                                  : Row(
                                      children: [
                                        if (!hasDraft && isLastMsgFromMe && statusIcon != null) ...[
                                          Icon(
                                            statusIcon,
                                            size: 16,
                                            color: statusColor,
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Expanded(
                                          child: hasDraft
                                              ? RichText(
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  text: TextSpan(
                                                    children: [
                                                      const TextSpan(
                                                        text: 'Draft: ',
                                                        style: TextStyle(
                                                          color: Color(0xFFFF3B30),
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text: draftText.trim(),
                                                        style: TextStyle(
                                                          color: AppTheme.secondaryText(isDark),
                                                          fontSize: 14,
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : EmojiText(
                                                  formatDisplayLastMessage(normalizeChatMessageText(conversation.lastMessage)),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: hasUnread
                                                        ? AppTheme.primaryText(isDark)
                                                        : AppTheme.secondaryText(
                                                          isDark,
                                                        ),
                                                    fontWeight: hasUnread
                                                        ? FontWeight.w500
                                                        : FontWeight.w400,
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                            ),
                            if (conversation.isProfileHidden ||
                                conversation.isMuted ||
                                conversation.isPinned ||
                                hasUnread) ...[
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (conversation.isProfileHidden)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4.0),
                                      child: Icon(
                                        CupertinoIcons.eye_slash_fill,
                                        size: 13,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  if (conversation.isMuted)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4.0),
                                      child: Icon(
                                        CupertinoIcons.bell_slash_fill,
                                        size: 13,
                                        color: AppTheme.secondaryText(isDark),
                                      ),
                                    ),
                                  if (conversation.isPinned)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4.0),
                                      child: Icon(
                                        CupertinoIcons.pin_fill,
                                        size: 13,
                                        color: Colors.amber.shade700,
                                      ),
                                    ),
                                  if (hasUnread)
                                    Container(
                                      constraints: const BoxConstraints(
                                        minWidth: 20,
                                        minHeight: 20,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5.5,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        conversation.unreadCount > 99
                                            ? '99+'
                                            : '${conversation.unreadCount}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          height: 1.1,
                                        ),
                                      ),
                                    ),
                                ],
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
                padding: const EdgeInsets.only(left: 80.0),
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

String formatDisplayLastMessage(String msg) {
  final s = msg.trim();
  if (s.startsWith('{') &&
      (s.contains('"latitude"') ||
          s.contains('"location_id"') ||
          s.contains('"longitude"'))) {
    final isLive = s.contains('"is_live":true') || s.contains('"isLive":true');
    return isLive ? '📍 Live location' : '📍 Location';
  }
  return msg;
}
