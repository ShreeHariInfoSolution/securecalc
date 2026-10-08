import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/server_api_service.dart';
import 'chat_bubble.dart';
import 'chat_typing_indicator.dart';

class ChatMessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool isLoadingMessages;
  final bool isLoadingMore;
  final bool isPeerTyping;
  final bool showJumpToLatest;
  final int newMessagesWhileAway;
  final String? historyError;
  final ScrollController scrollController;
  final ChatConversation conversation;
  final Map<int, String> groupMemberNames;
  final String chatName;
  final String chatAvatar;
  final Function(ChatMessage, Offset) onShowMessageActions;
  final Function(ChatMessage) onBeginReply;
  final VoidCallback onJumpToLatest;
  final VoidCallback onReloadMessages;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.isLoadingMessages,
    required this.isLoadingMore,
    required this.isPeerTyping,
    required this.showJumpToLatest,
    required this.newMessagesWhileAway,
    required this.historyError,
    required this.scrollController,
    required this.conversation,
    required this.groupMemberNames,
    required this.chatName,
    required this.chatAvatar,
    required this.onShowMessageActions,
    required this.onBeginReply,
    required this.onJumpToLatest,
    required this.onReloadMessages,
  });

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _buildTopLoadingShimmer(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14.0),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDark ? Colors.white70 : AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Loading older messages...',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : AppTheme.subtitleGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHistory(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              historyError == null
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.cloud_off_rounded,
              size: 42,
              color: AppTheme.subtitleGrey,
            ),
            const SizedBox(height: 12),
            Text(
              historyError ?? 'No messages yet. Start the conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : AppTheme.subtitleGrey,
              ),
            ),
            if (historyError != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onReloadMessages,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isLoadingMessages && messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (messages.isEmpty) {
      return _buildEmptyHistory(isDark);
    }

    final messagesById = {for (final message in messages) message.id: message};

    return Stack(
      children: [
        ListView.builder(
          controller: scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: messages.length + (isPeerTyping ? 1 : 0) + (isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (isPeerTyping && index == 0) {
              return ChatTypingIndicator(
                chatName: chatName,
                chatAvatar: chatAvatar,
              );
            }

            final offsetIndex = index - (isPeerTyping ? 1 : 0);
            if (offsetIndex >= messages.length) {
              return _buildTopLoadingShimmer(isDark);
            }

            final messageIndex = messages.length - 1 - offsetIndex;
            final msg = messages[messageIndex];
            final showDateHeader =
                messageIndex == 0 ||
                !_sameDay(messages[messageIndex - 1].timestamp, msg.timestamp);
            final previousSender =
                messageIndex > 0 ? messages[messageIndex - 1].senderId : null;
            final showGroupSender =
                conversation.isGroup && msg.senderId != previousSender;
            final senderId = msg.senderId == 'user'
                ? ServerApiService.instance.currentUserId
                : int.tryParse(msg.senderId);
            final repliedMessage = msg.replyToId == null
                ? null
                : messagesById[msg.replyToId.toString()];

            double horizontalDragDistance = 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDateHeader)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.055),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _dateLabel(msg.timestamp),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.subtitleGrey,
                          ),
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  onLongPressStart: int.tryParse(msg.id) != null
                      ? (details) => onShowMessageActions(msg, details.globalPosition)
                      : null,
                  onHorizontalDragStart: (_) {
                    horizontalDragDistance = 0;
                  },
                  onHorizontalDragUpdate: (details) {
                    horizontalDragDistance += details.delta.dx;
                  },
                  onHorizontalDragEnd: (_) {
                    if (horizontalDragDistance.abs() > 42) {
                      onBeginReply(msg);
                    }
                    horizontalDragDistance = 0;
                  },
                  child: ChatBubble(
                    key: ValueKey(msg.id),
                    chatId: conversation.id,
                    message: msg.content,
                    isMe: msg.senderId == 'user',
                    timestamp: msg.timestamp,
                    type: msg.type,
                    mediaUrl: msg.mediaUrl,
                    fileName: msg.fileName,
                    isRead: msg.isRead,
                    isEdited: msg.isEdited,
                    isDeleted: msg.isDeleted,
                    senderName: showGroupSender && senderId != null
                        ? groupMemberNames[senderId] ?? 'Member'
                        : null,
                    replySender: repliedMessage == null
                        ? null
                        : repliedMessage.senderId == 'user'
                            ? 'You'
                            : conversation.isGroup
                                ? groupMemberNames[int.tryParse(repliedMessage.senderId)] ?? 'Member'
                                : chatName,
                    replyText: repliedMessage?.previewText,
                    reactions: msg.reaction == null ? null : [msg.reaction!],
                  ),
                ),
              ],
            );
          },
        ),
        if (showJumpToLatest)
          Positioned(
            right: 14,
            bottom: 18,
            child: Material(
              color: isDark ? AppTheme.darkSurface : Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: onJumpToLatest,
                    tooltip: 'Jump to latest',
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    color: AppTheme.primaryColor,
                  ),
                  if (newMessagesWhileAway > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$newMessagesWhileAway',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
