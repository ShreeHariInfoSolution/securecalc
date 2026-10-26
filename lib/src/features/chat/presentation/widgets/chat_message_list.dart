import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/server_api_service.dart';
import 'chat_bubble.dart';
import 'chat_typing_indicator.dart';
import 'swipe_to_reply.dart';

class ChatMessageList extends StatefulWidget {
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
  final Function(ChatMessage)? onShowMessageInfo;
  final Function(ChatMessage) onBeginReply;
  final Function(int)? onTapReply;
  final String? highlightedMessageId;
  final String? searchQuery;
  final Set<String> decryptingMessageIds;
  final VoidCallback onJumpToLatest;
  final VoidCallback onReloadMessages;
  final DateTime? sessionStartTime;
  final int initialUnreadCount;
  final bool isSelectionMode;
  final Set<String> selectedMessageIds;
  final Function(ChatMessage)? onToggleSelectMessage;
  final VoidCallback? onVoiceCallTap;
  final VoidCallback? onVideoCallTap;

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
    this.onShowMessageInfo,
    required this.onBeginReply,
    this.onTapReply,
    this.highlightedMessageId,
    this.searchQuery,
    this.decryptingMessageIds = const <String>{},
    required this.onJumpToLatest,
    required this.onReloadMessages,
    this.sessionStartTime,
    this.initialUnreadCount = 0,
    this.isSelectionMode = false,
    this.selectedMessageIds = const <String>{},
    this.onToggleSelectMessage,
    this.onVoiceCallTap,
    this.onVideoCallTap,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  final Set<String> _animatedMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    for (final m in widget.messages) {
      _animatedMessageIds.add(m.id);
    }
  }

  @override
  void didUpdateWidget(ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_animatedMessageIds.isEmpty && widget.messages.isNotEmpty) {
      for (final m in widget.messages) {
        _animatedMessageIds.add(m.id);
      }
    }

    // Map optimistic local IDs that transition to server IDs
    for (final newMsg in widget.messages) {
      if (!_animatedMessageIds.contains(newMsg.id)) {
        final matchedOldLocal = oldWidget.messages.any(
          (oldMsg) =>
              (oldMsg.id.startsWith('local_') || oldMsg.id.startsWith('fwd_')) &&
              _animatedMessageIds.contains(oldMsg.id) &&
              oldMsg.senderId == newMsg.senderId &&
              oldMsg.content.trim() == newMsg.content.trim(),
        );
        if (matchedOldLocal) {
          _animatedMessageIds.add(newMsg.id);
        }
      }
    }
  }

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
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday at $timeStr';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year} at $timeStr';
  }

  bool _isFirstUnreadPeerMessage(int targetIndex) {
    if (widget.initialUnreadCount <= 0 ||
        targetIndex < 0 ||
        targetIndex >= widget.messages.length) {
      return false;
    }
    if (widget.messages[targetIndex].senderId == 'user') return false;

    var peerCount = 0;
    for (int i = widget.messages.length - 1; i >= 0; i--) {
      if (widget.messages[i].senderId != 'user') {
        peerCount++;
        if (peerCount == widget.initialUnreadCount) {
          return i == targetIndex;
        }
      }
    }
    for (int i = 0; i < widget.messages.length; i++) {
      if (widget.messages[i].senderId != 'user') return i == targetIndex;
    }
    return false;
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

  bool _isImageDownloaded(ChatMessage msg) {
    final rawUrl = msg.mediaUrl;
    if (rawUrl == null || rawUrl.isEmpty) return false;
    return AttachmentCacheService.instance.isCachedInMemory(rawUrl);
  }

  List<ChatMessage>? _getGroupedImages(int messageIndex) {
    final currentMsg = widget.messages[messageIndex];
    if (!_isImageMessage(currentMsg)) return null;

    if (messageIndex > 0 && _isImageMessage(widget.messages[messageIndex - 1])) {
      final prevMsg = widget.messages[messageIndex - 1];
      if (prevMsg.senderId == currentMsg.senderId &&
          currentMsg.timestamp.difference(prevMsg.timestamp).inMinutes.abs() <=
              15) {
        int firstIndex = messageIndex - 1;
        while (firstIndex > 0 &&
            _isImageMessage(widget.messages[firstIndex - 1]) &&
            widget.messages[firstIndex - 1].senderId == currentMsg.senderId &&
            widget.messages[firstIndex].timestamp
                    .difference(widget.messages[firstIndex - 1].timestamp)
                    .inMinutes
                    .abs() <=
                15) {
          firstIndex--;
        }

        final fullGroup = <ChatMessage>[];
        int idx = firstIndex;
        while (idx < widget.messages.length &&
            _isImageMessage(widget.messages[idx]) &&
            (idx == firstIndex ||
                widget.messages[idx].senderId == widget.messages[idx - 1].senderId) &&
            (idx == firstIndex ||
                widget.messages[idx].timestamp
                        .difference(widget.messages[idx - 1].timestamp)
                        .inMinutes
                        .abs() <=
                    15)) {
          fullGroup.add(widget.messages[idx]);
          idx++;
        }

        bool allDownloaded = true;
        for (final m in fullGroup) {
          if (!_isImageDownloaded(m)) {
            allDownloaded = false;
            break;
          }
        }

        if (allDownloaded && fullGroup.length > 1) {
          return const <ChatMessage>[];
        }
      }
    }

    final grouped = <ChatMessage>[currentMsg];
    int nextIndex = messageIndex + 1;
    while (nextIndex < widget.messages.length) {
      final nextMsg = widget.messages[nextIndex];
      if (_isImageMessage(nextMsg) &&
          nextMsg.senderId == currentMsg.senderId &&
          nextMsg.timestamp
                  .difference(grouped.last.timestamp)
                  .inMinutes
                  .abs() <=
              15) {
        grouped.add(nextMsg);
        nextIndex++;
      } else {
        break;
      }
    }

    if (grouped.length > 1) {
      for (final gMsg in grouped) {
        if (!_isImageDownloaded(gMsg)) {
          return null;
        }
      }
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
              widget.historyError == null
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.cloud_off_rounded,
              size: 42,
              color: AppTheme.subtitleGrey,
            ),
            const SizedBox(height: 12),
            Text(
              widget.historyError ?? 'No messages yet. Start the conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : AppTheme.subtitleGrey,
              ),
            ),
            if (widget.historyError != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: widget.onReloadMessages,
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

    if (widget.isLoadingMessages && widget.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.messages.isEmpty) {
      return _buildEmptyHistory(isDark);
    }

    final messagesById = {for (final message in widget.messages) message.id: message};
    String? latestOutgoingMessageId;
    for (final message in widget.messages.reversed) {
      if (message.senderId == 'user' && !message.isDeleted) {
        latestOutgoingMessageId = message.id;
        break;
      }
    }

    final topInset = MediaQuery.paddingOf(context).top + 68.0;
    final bottomInset = MediaQuery.paddingOf(context).bottom + 58.0;

    return Stack(
      children: [
        GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: ListView.builder(
            controller: widget.scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            reverse: true,
            padding: EdgeInsets.fromLTRB(0, topInset, 0, bottomInset),
            itemCount: widget.messages.length +
                (widget.isPeerTyping ? 1 : 0) +
                (widget.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (widget.isPeerTyping) {
                if (index == 0) {
                  return RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6, top: 2),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ChatTypingIndicator(
                          key: const ValueKey('bottom_chat_typing_indicator'),
                          chatName: widget.chatName,
                          chatAvatar: widget.chatAvatar,
                        ),
                      ),
                    ),
                  );
                }
              }

              final adjustedIndex = widget.isPeerTyping ? index - 1 : index;

              if (adjustedIndex >= widget.messages.length) {
                return _buildTopLoadingShimmer(isDark);
              }

              final messageIndex = widget.messages.length - 1 - adjustedIndex;
              final msg = widget.messages[messageIndex];

              final bool shouldAnimate = !_animatedMessageIds.contains(msg.id);
              if (shouldAnimate) {
                _animatedMessageIds.add(msg.id);
              }

              final groupedImages = _getGroupedImages(messageIndex);
              if (groupedImages != null && groupedImages.isEmpty) {
                return const SizedBox.shrink();
              }

              final showUnreadBanner = _isFirstUnreadPeerMessage(messageIndex);
              final showDateHeader =
                  messageIndex == 0 ||
                  !_sameDay(
                    widget.messages[messageIndex - 1].timestamp,
                    msg.timestamp,
                  );
              final previousSender = messageIndex > 0
                  ? widget.messages[messageIndex - 1].senderId
                  : null;
              final showGroupSender =
                  widget.conversation.isGroup && msg.senderId != previousSender;
              final senderId = msg.senderId == 'user'
                  ? ServerApiService.instance.currentUserId
                  : int.tryParse(msg.senderId);
              final repliedMessage = msg.replyToId == null
                  ? null
                  : messagesById[msg.replyToId.toString()];

              return SwipeToReply(
                enabled: int.tryParse(msg.id) != null,
                isMe: msg.senderId == 'user',
                onReply: () => widget.onBeginReply(msg),
                onInfo: widget.onShowMessageInfo != null
                    ? () => widget.onShowMessageInfo!(msg)
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showUnreadBanner)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : const Color(0xFFE5E5EA),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '${widget.initialUnreadCount} UNREAD MESSAGES',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: AppTheme.secondaryText(isDark),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (showDateHeader) DateLabel(_dateLabel(msg.timestamp)),
                    Builder(
                      builder: (bubbleContext) {
                        return GestureDetector(
                          onLongPressStart: int.tryParse(msg.id) != null
                              ? (details) {
                                  final box =
                                      bubbleContext.findRenderObject()
                                          as RenderBox?;
                                  final globalPos =
                                      box?.localToGlobal(Offset.zero) ??
                                      details.globalPosition;
                                  final size = box?.size ?? const Size(240, 60);
                                  widget.onShowMessageActions(msg, globalPos, size);
                                }
                              : null,
                          child: RepaintBoundary(
                            child: BouncyMessageEntryAnimation(
                              key: ValueKey('anim_${msg.id}'),
                              isMe: msg.senderId == 'user',
                              animate: shouldAnimate,
                              child: ChatBubble(
                                key: ValueKey(msg.id),
                                chatId: widget.conversation.id,
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
                                isDecrypting: widget.decryptingMessageIds.contains(msg.id),
                                showDeliveryStatus:
                                    msg.id == latestOutgoingMessageId,
                                groupedImages: groupedImages,
                                senderName: showGroupSender && senderId != null
                                    ? widget.groupMemberNames[senderId] ?? 'Member'
                                    : null,
                                replyToId: msg.replyToId,
                                repliedMessage: repliedMessage,
                                replySender: repliedMessage == null
                                    ? null
                                    : repliedMessage.senderId == 'user'
                                    ? 'You'
                                    : widget.conversation.isGroup
                                    ? widget.groupMemberNames[int.tryParse(
                                            repliedMessage.senderId,
                                          )] ??
                                          'Member'
                                    : widget.chatName,
                                replyText: repliedMessage?.previewText,
                                onTapReply: widget.onTapReply,
                                isHighlighted: widget.highlightedMessageId == msg.id,
                                searchQuery: widget.searchQuery,
                                isForwarded: msg.isForwarded,
                                isSelectionMode: widget.isSelectionMode,
                                isSelected: widget.selectedMessageIds.contains(msg.id),
                                onToggleSelect: () => widget.onToggleSelectMessage?.call(msg),
                                onShowMessageActions: widget.onShowMessageActions,
                                reactions: msg.reaction == null
                                    ? null
                                    : [msg.reaction!],
                                msgType: msg.msgType,
                                callId: msg.callId,
                                callType: msg.callType,
                                callStatus: msg.callStatus,
                                callDuration: msg.callDuration,
                                onVoiceCallTap: widget.onVoiceCallTap,
                                onVideoCallTap: widget.onVideoCallTap,
                              ),
                            ),
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
        if (widget.showJumpToLatest)
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
                    onPressed: widget.onJumpToLatest,
                    tooltip: 'Jump to latest',
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    color: AppTheme.primaryColor,
                  ),
                  if (widget.newMessagesWhileAway > 0)
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
                          '${widget.newMessagesWhileAway}',
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
  final String text;

  const DateLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.secondaryText(isDark),
            ),
          ),
        ),
      ),
    );
  }
}
