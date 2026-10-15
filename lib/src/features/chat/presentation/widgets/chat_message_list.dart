import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/server_api_service.dart';
import 'chat_bubble.dart';
import 'chat_typing_indicator.dart';
import 'swipe_to_reply.dart';

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
  final Function(ChatMessage, Offset, Size) onShowMessageActions;
  final Function(ChatMessage) onBeginReply;
  final Function(int)? onTapReply;
  final String? highlightedMessageId;
  final VoidCallback onJumpToLatest;
  final VoidCallback onReloadMessages;
  final DateTime? sessionStartTime;

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
    this.onTapReply,
    this.highlightedMessageId,
    required this.onJumpToLatest,
    required this.onReloadMessages,
    this.sessionStartTime,
  });

  bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
          first.month == second.month &&
          first.day == second.day;

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final hour24 = date.hour;
    final hour = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
    final min = date.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$min $period';

    if (day == today) return 'Today at $timeStr';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday at $timeStr';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]} ${date.year} at $timeStr';
  }

  bool _isImageMessage(ChatMessage msg) {
    if (msg.isDeleted) return false;
    final type = msg.type.toLowerCase();
    if (type.startsWith('image/') || type == 'image') return true;
    if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
      final ext = msg.mediaUrl!.split('.').last.split('?').first.toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext) ||
          msg.previewText == 'Photo') {
        return true;
      }
    }
    return false;
  }

  /// Groups consecutive image messages sent by the same sender into a single list.
  List<ChatMessage>? _getGroupedImages(int messageIndex) {
    final currentMsg = messages[messageIndex];
    if (!_isImageMessage(currentMsg)) return null;

    if (messageIndex > 0 && _isImageMessage(messages[messageIndex - 1])) {
      final prevMsg = messages[messageIndex - 1];
      if (prevMsg.senderId == currentMsg.senderId &&
          currentMsg.timestamp.difference(prevMsg.timestamp).inMinutes.abs() <= 15) {

        int firstIndex = messageIndex - 1;
        while (firstIndex > 0 &&
            _isImageMessage(messages[firstIndex - 1]) &&
            messages[firstIndex - 1].senderId == currentMsg.senderId &&
            messages[firstIndex].timestamp.difference(messages[firstIndex - 1].timestamp).inMinutes.abs() <= 15) {
          firstIndex--;
        }

        final fullGroup = <ChatMessage>[];
        int idx = firstIndex;
        while (idx < messages.length &&
            _isImageMessage(messages[idx]) &&
            (idx == firstIndex || messages[idx].senderId == messages[idx - 1].senderId) &&
            (idx == firstIndex || messages[idx].timestamp.difference(messages[idx - 1].timestamp).inMinutes.abs() <= 15)) {
          fullGroup.add(messages[idx]);
          idx++;
        }

        if (fullGroup.length > 1) {
          return const <ChatMessage>[];
        }
      }
    }

    final grouped = <ChatMessage>[currentMsg];
    int nextIndex = messageIndex + 1;
    while (nextIndex < messages.length) {
      final nextMsg = messages[nextIndex];
      if (_isImageMessage(nextMsg) &&
          nextMsg.senderId == currentMsg.senderId &&
          nextMsg.timestamp.difference(grouped.last.timestamp).inMinutes.abs() <= 15) {
        grouped.add(nextMsg);
        nextIndex++;
      } else {
        break;
      }
    }

    if (grouped.length > 1) {
      return grouped;
    }

    return null;
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

    final topInset = MediaQuery.paddingOf(context).top + 68.0;
    final bottomInset = MediaQuery.paddingOf(context).bottom + 58.0;

    return Stack(
      children: [
        GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: ListView.builder(
            controller: scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            reverse: true,
            padding: EdgeInsets.fromLTRB(0, topInset, 0, bottomInset),
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

              final groupedImages = _getGroupedImages(messageIndex);
              if (groupedImages != null && groupedImages.isEmpty) {
                return const SizedBox.shrink();
              }

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

              return SwipeToReply(
                enabled: int.tryParse(msg.id) != null,
                onReply: () => onBeginReply(msg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDateHeader)
                      DateLabel(_dateLabel(msg.timestamp)),
                    Builder(
                      builder: (bubbleContext) {
                        return GestureDetector(
                          onLongPressStart: int.tryParse(msg.id) != null
                              ? (details) {
                            final box =
                            bubbleContext.findRenderObject() as RenderBox?;
                            final globalPos =
                                box?.localToGlobal(Offset.zero) ??
                                    details.globalPosition;
                            final size =
                                box?.size ?? const Size(240, 60);
                            onShowMessageActions(msg, globalPos, size);
                          }
                              : null,
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
                            isDelivered: msg.isDelivered,
                            isEdited: msg.isEdited,
                            isDeleted: msg.isDeleted,
                            isSaved: msg.isSaved,
                            groupedImages: groupedImages,
                            senderName: showGroupSender && senderId != null
                                ? groupMemberNames[senderId] ?? 'Member'
                                : null,
                            replyToId: msg.replyToId,
                            repliedMessage: repliedMessage,
                            replySender: repliedMessage == null
                                ? null
                                : repliedMessage.senderId == 'user'
                                ? 'You'
                                : conversation.isGroup
                                ? groupMemberNames[int.tryParse(repliedMessage.senderId)] ?? 'Member'
                                : chatName,
                            replyText: repliedMessage?.previewText,
                            onTapReply: onTapReply,
                            isHighlighted: highlightedMessageId == msg.id,
                            reactions: msg.reaction == null ? null : [msg.reaction!],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (showJumpToLatest)
          Positioned(
            right: 14,
            bottom: MediaQuery.paddingOf(context).bottom + 66.0,
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

class DateLabel extends StatelessWidget {
  const DateLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 13),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF8E8E93),
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: .1,
        ),
      ),
    );
  }
}
