import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
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
  final Function(ChatMessage message, Offset pos, Size size, {bool reactionsOnly}) onShowMessageActions;
  final Function(ChatMessage)? onShowMessageInfo;
  final Function(ChatMessage) onBeginReply;
  final ValueChanged<ChatMessage>? onForwardMessage;
  final void Function(ChatMessage, String emoji)? onReactMessage;
  final Future<bool> Function(ChatMessage)? onToggleStarMessage;
  final ValueChanged<ChatMessage>? onDeleteMessage;
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
  final Function(ChatMessage)? onFailedTap;
  final double? topInset;
  final double? bottomInset;
  final String? scrollTargetId;
  final GlobalKey? scrollTargetKey;
  final String? hiddenMessageId;

  const ChatMessageList({
    super.key,
    required this.messages,
    this.hiddenMessageId,
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
    this.onForwardMessage,
    this.onReactMessage,
    this.onToggleStarMessage,
    this.onDeleteMessage,
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
    this.onFailedTap,
    this.topInset,
    this.bottomInset,
    this.scrollTargetId,
    this.scrollTargetKey,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  final Set<String> _animateIds = <String>{};
  final Map<String, String> _keyAlias = <String, String>{}; // serverId -> localId

  String _keyOf(ChatMessage m) => _keyAlias[m.id] ?? m.id;

  @override
  void initState() {
    super.initState();
  }

  bool _isLocalId(String id) =>
      id.startsWith('local_') || id.startsWith('fwd_') || id.startsWith('temp_');

  @override
  void didUpdateWidget(ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldMsgs = oldWidget.messages, newMsgs = widget.messages;
    if (oldMsgs.isEmpty || newMsgs.isEmpty) return;

    final oldIds = {for (final m in oldMsgs) m.id};
    final newIds = {for (final m in newMsgs) m.id};
    // local rows that disappeared in this update = candidates for an id swap
    final removedLocals = oldMsgs
        .where((o) => _isLocalId(o.id) && !newIds.contains(o.id))
        .toList();

    for (final m in newMsgs) {
      if (oldIds.contains(m.id)) continue;

      final i = removedLocals.indexWhere((o) =>
      o.senderId == m.senderId &&
          ((o.hasMedia && m.hasMedia)
              ? o.fileName == m.fileName
              : o.content.trim() == m.content.trim()));
      if (i >= 0) {
        final o = removedLocals.removeAt(i);
        _keyAlias[m.id] = _keyAlias[o.id] ?? o.id; // same key, no remount
        continue;
      }
      if (DateTime.now().difference(m.timestamp).inSeconds.abs() < 30) {
        _animateIds.add(m.id);
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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

  static const int _groupWindowMinutes = 15;

  bool _isMediaMessage(ChatMessage msg) {
    if (msg.isDeleted || msg.isCallMessage) return false;
    final type = msg.type.toLowerCase().trim();
    if (type.contains('gif') || type == 'sticker') return false;
    final url = (msg.mediaUrl ?? '').toLowerCase().trim();
    final name = (msg.fileName ?? '').toLowerCase().trim();

    final isImage = type.contains('image') ||
        type == 'photo' ||
        ['jpg', 'jpeg', 'png', 'webp', 'heic']
            .any((e) => url.contains('.$e') || name.endsWith('.$e'));
    final isVideo = type.contains('video') ||
        ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v']
            .any((e) => url.contains('.$e') || name.endsWith('.$e'));
    return (isImage || isVideo) && url.isNotEmpty;
  }

  bool _hasCaption(ChatMessage msg) {
    final c = msg.content.trim();
    if (c.isEmpty) return false;
    final lower = c.toLowerCase();
    const generic = {
      '[attachment]', 'photo', 'video', 'sent a photo', 'sent a video',
      'sent an attachment', 'voice message', 'gif',
    };
    if (generic.contains(lower)) return false;
    final name = (msg.fileName ?? '').trim().toLowerCase();
    if (lower == name) return false;
    if (name.contains('.') &&
        lower == name.substring(0, name.lastIndexOf('.'))) {
      return false;
    }
    return true;
  }

  /// A message continues the previous album when it has no caption of its own.
  /// CHANGED: forwarded and normal media never share an album, so the
  /// "Forwarded" tag always matches every item in the group.
  bool _isGroupFollower(int i) {
    if (i <= 0) return false;
    final cur = widget.messages[i];
    final prev = widget.messages[i - 1];

    if (!_isMediaMessage(cur) || !_isMediaMessage(prev)) return false;
    if (cur.senderId != prev.senderId) return false;
    if (cur.isForwarded != prev.isForwarded) return false;

    final timeDiffSec = cur.timestamp.difference(prev.timestamp).inSeconds.abs();
    if (timeDiffSec > _groupWindowMinutes * 60) return false;

    // A message with its own individual caption is ALWAYS its own separate message.
    if (_hasCaption(cur)) return false;

    // If cur has no caption:
    // It follows prev if prev has no caption OR if prev and cur were sent in the same batch (<= 3s)
    final prevHasCap = _hasCaption(prev);
    if (prevHasCap && timeDiffSec > 3) {
      return false;
    }

    return true;
  }

  /// null = normal bubble, empty = already rendered by its leader, else the album.
  List<ChatMessage>? _getGroupedMedia(int i) {
    final cur = widget.messages[i];
    if (!_isMediaMessage(cur)) return null;
    if (_isGroupFollower(i)) return const <ChatMessage>[];

    final grouped = <ChatMessage>[cur];
    var n = i + 1;
    while (n < widget.messages.length && _isGroupFollower(n)) {
      grouped.add(widget.messages[n]);
      n++;
    }
    return grouped.length > 1 ? grouped : null;
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
    int latestOutgoingIndex = -1;
    for (var i = widget.messages.length - 1; i >= 0; i--) {
      final m = widget.messages[i];
      if (m.senderId == 'user' && !m.isDeleted) {
        latestOutgoingIndex = i;
        break;
      }
    }

    final topInset = widget.topInset ?? (MediaQuery.paddingOf(context).top + 68.0);
    final bottomInset = widget.bottomInset ?? (MediaQuery.paddingOf(context).bottom + 58.0);

    return Stack(
      children: [
        GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: ListView.builder(
            controller: widget.scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            reverse: true,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
            cacheExtent: 400.0,
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
              final msgKey = _keyOf(msg);

              final bool shouldAnimate =
                  !widget.isSelectionMode && _animateIds.contains(msg.id);
              if (shouldAnimate) {
                WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _animateIds.remove(msg.id),
                );
              }

              final groupedImages = _getGroupedMedia(messageIndex);
              if (groupedImages != null && groupedImages.isEmpty) {
                return const SizedBox.shrink();
              }

              final showUnreadBanner = _isFirstUnreadPeerMessage(messageIndex);
              final showDateHeader = messageIndex == 0 ||
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

              final lastIdx = messageIndex + ((groupedImages?.length ?? 1) - 1);
              final lastMsg = widget.messages[lastIdx];
              final isLastInGroup = lastIdx == widget.messages.length - 1 ||
                  widget.messages[lastIdx + 1].senderId != msg.senderId ||
                  widget.messages[lastIdx + 1].timestamp
                      .difference(lastMsg.timestamp)
                      .inMinutes
                      .abs() >
                      5 ||
                  widget.messages[lastIdx + 1].hasMedia;

              Widget messageChild = Column(
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
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: (int.tryParse(msg.id) != null && !widget.isSelectionMode)
                            ? () {
                                HapticFeedback.lightImpact();
                                final box = bubbleContext.findRenderObject() as RenderBox?;
                                final globalPos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
                                final size = box?.size ?? const Size(240, 60);
                                widget.onShowMessageActions(msg, globalPos, size, reactionsOnly: true);
                              }
                            : null,
                        onLongPressStart: int.tryParse(msg.id) != null
                            ? (details) {
                                final box = bubbleContext.findRenderObject() as RenderBox?;
                                final globalPos = box?.localToGlobal(Offset.zero) ?? details.globalPosition;
                                final size = box?.size ?? const Size(240, 60);
                                widget.onShowMessageActions(msg, globalPos, size, reactionsOnly: false);
                              }
                            : null,
                        child: Opacity(
                          opacity: widget.hiddenMessageId == msg.id ? 0.0 : 1.0,
                          child: RepaintBoundary(
                            child: BouncyMessageEntryAnimation(
                              key: ValueKey('anim_$msgKey'),
                              isMe: msg.senderId == 'user',
                              animate: shouldAnimate,
                              child: ChatBubble(
                                key: ValueKey('bubble_$msgKey'),
                                id: msg.id,
                                sourceMessage: msg,
                                onReplyToMessage: widget.onBeginReply,
                                onForwardMessage: widget.onForwardMessage,
                                onReactMessage: widget.onReactMessage,
                                onToggleStarMessage: widget.onToggleStarMessage,
                                onDeleteMessage: widget.onDeleteMessage,
                                chatId: widget.conversation.id,
                                message: msg.content,
                                isMe: msg.senderId == 'user',
                                timestamp: msg.timestamp,
                                type: msg.type,
                                mediaUrl: msg.mediaUrl,
                                fileName: msg.fileName,
                                isRead: msg.isRead,
                                isDelivered: msg.isDelivered,
                                status: msg.status,
                                isEdited: msg.isEdited,
                                isDeleted: msg.isDeleted,
                                isSaved: msg.isSaved,
                                isDecrypting:
                                widget.decryptingMessageIds.contains(msg.id),
                                showDeliveryStatus: messageIndex ==
                                    latestOutgoingIndex ||
                                    (groupedImages != null &&
                                        latestOutgoingIndex >= 0 &&
                                        groupedImages.any((g) =>
                                        g.id ==
                                            widget.messages[latestOutgoingIndex]
                                                .id)),
                                showTail: isLastInGroup,
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
                                isHighlighted:
                                widget.highlightedMessageId == msg.id,
                                searchQuery: widget.searchQuery,
                                isForwarded: msg.isForwarded,
                                isSelectionMode: widget.isSelectionMode,
                                isSelected:
                                widget.selectedMessageIds.contains(msg.id),
                                onToggleSelect: () =>
                                    widget.onToggleSelectMessage?.call(msg),
                                onShowMessageActions: widget.onShowMessageActions,
                                reactions:
                                msg.reaction == null ? null : [msg.reaction!],
                                msgType: msg.msgType,
                                callId: msg.callId,
                                callType: msg.callType,
                                callStatus: msg.callStatus,
                                callDuration: msg.callDuration,
                                onVoiceCallTap: widget.onVoiceCallTap,
                                onVideoCallTap: widget.onVideoCallTap,
                                onFailedTap: () => widget.onFailedTap?.call(msg),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );

              if (widget.scrollTargetId != null &&
                  msg.id == widget.scrollTargetId &&
                  widget.scrollTargetKey != null) {
                messageChild = KeyedSubtree(
                  key: widget.scrollTargetKey,
                  child: messageChild,
                );
              }

              return SwipeToReply(
                key: ValueKey(msgKey),
                enabled: int.tryParse(msg.id) != null,
                isMe: msg.senderId == 'user',
                onReply: () => widget.onBeginReply(msg),
                onInfo: widget.onShowMessageInfo != null
                    ? () => widget.onShowMessageInfo!(msg)
                    : null,
                child: messageChild,
              );
            },
          ),
        ),
        if (widget.showJumpToLatest)
          Positioned(
            right: 14,
            bottom: (widget.bottomInset ?? MediaQuery.paddingOf(context).bottom + 58.0) + 6,
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