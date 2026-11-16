import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/theme/app_theme.dart';
import 'package:securecalc/src/core/utils/app_toast.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';

import '../../domain/entities/chat_conversation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/models/server_models.dart';
import '../../domain/services/attachment_cache_service.dart';
import '../../domain/services/outgoing_attachment_manager.dart';
import '../../domain/utils/forward_marker.dart';
import '../../domain/services/call_service.dart';
import '../../domain/services/chat_audio_playback.dart';
import '../../domain/services/e2e_crypto_service.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/presence_store.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import '../../domain/services/socket_chat_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_media_viewer.dart';
import '../widgets/chat_detail_header.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/message_actions_overlay.dart';
import '../widgets/gif_picker_panel.dart';
import '../widgets/sticker_picker_panel.dart';
import '../widgets/forward_chat_selection_dialog.dart';
import 'message_info_page.dart';
import '../widgets/chat_wallpaper_widget.dart';
import 'chat_info_page.dart';

class ChatDetailPage extends StatefulWidget {
  final ChatConversation conversation;
  final String? peerIp;

  const ChatDetailPage({super.key, required this.conversation, this.peerIp});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage>
    with WidgetsBindingObserver {
  final ChatMediaController _mediaCtl = ChatMediaController();
  final DateTime _sessionStartTime = DateTime.now();
  late List<ChatMessage> _messages;
  late String _chatName;
  late String _chatAvatar;
  bool _isLoadingMessages = true;
  bool _didPurgeSeenMessagesOnExit = false;
  int _historyLoadGeneration = 0;
  final Map<String, ChatMessage> _messagesReceivedWhileLoading = {};
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMorePages = true;
  bool _isLoadingMore = false;
  bool _isSending = false;
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};
  ChatMessage? _editingMessage;
  ChatMessage? _replyingMessage;
  String? _historyError;
  final TextEditingController _inputController = EmojiTextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _composerHeight = ValueNotifier<double>(58.0);
  String? _scrollTargetId;
  final GlobalKey _scrollTargetKey = GlobalKey();
  String? _pendingScrollTargetId;
  Timer? _searchDebounceTimer;
  Timer? _metricsDebounceTimer;
  final Map<int, String> _groupMemberNames = {};
  final Set<String> _decryptingEditedMessageIds = <String>{};
  DateTime? _lastAttachmentTimestamp;
  StreamSubscription<OutgoingEvent>? _outSub;
  final ChatComposerController _composerCtl = ChatComposerController();
  Future<void> _textQueueTail = Future.value();
  Future<void> _gifQueueTail = Future.value();
  int _textSeq = 0;
  bool _showJumpToLatest = false;
  int _newMessagesWhileAway = 0;
  final ValueNotifier<bool> _isPeerTyping = ValueNotifier(false);
  final ValueNotifier<bool> _isPeerOnline = ValueNotifier(false);
  Timer? _peerTypingTimer;
  StreamSubscription<ServerMessageModel>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;
  StreamSubscription<Map<String, dynamic>>? _presenceSubscription;
  StreamSubscription<Map<String, dynamic>>? _readSubscription;
  StreamSubscription<Map<String, dynamic>>? _deliveredSubscription;
  StreamSubscription<Map<String, dynamic>>? _editedSubscription;
  StreamSubscription<Map<String, dynamic>>? _deletedSubscription;
  StreamSubscription<Map<String, dynamic>>? _reactionSubscription;

  String? _hiddenMsgId;
  late int _disappearType;
  late final int _initialUnreadCount;
  late bool _isBlocked;

  final Map<String, String> _pendingLocalToRealIdMap = <String, String>{};
  final Set<String> _matchedLocalIds = <String>{};

  void _adjustRemainingLocalMessageTimestamps(DateTime baseTimestamp) {
    var bumpMs = 10;
    for (int i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      if ((msg.id.startsWith('local_') || msg.id.startsWith('temp_')) &&
          msg.senderId == 'user') {
        if (!msg.timestamp.isAfter(baseTimestamp)) {
          final newTs = baseTimestamp.add(Duration(milliseconds: bumpMs));
          bumpMs += 10;
          _messages[i] = ChatMessage(
            id: msg.id,
            senderId: msg.senderId,
            content: msg.content,
            timestamp: newTs,
            type: msg.type,
            mediaUrl: msg.mediaUrl,
            fileName: msg.fileName,
            isRead: msg.isRead,
            isDelivered: msg.isDelivered,
            status: msg.status,
            deliveredAt: msg.deliveredAt,
            isEdited: msg.isEdited,
            isDeleted: msg.isDeleted,
            isSaved: msg.isSaved,
            isForwarded: msg.isForwarded,
            disappearType: msg.disappearType,
            expiresAt: msg.expiresAt,
            updatedAt: msg.updatedAt,
            reaction: msg.reaction,
            replyToId: msg.replyToId,
            msgType: msg.msgType,
            callId: msg.callId,
            callType: msg.callType,
            callStatus: msg.callStatus,
            callDuration: msg.callDuration,
          );
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composerCtl.isPanelOpen.addListener(() {
      if (mounted) setState(() {});
    });
    _disappearType = widget.conversation.disappearType;
    _initialUnreadCount = widget.conversation.unreadCount;
    _isBlocked = widget.conversation.isBlocked;
    ServerChatManager.instance.activeChatId = widget.conversation.id;
    _chatName = widget.conversation.name;
    _chatAvatar = widget.conversation.avatarUrl;
    _isPeerOnline.value = widget.conversation.isOnline;
    _groupMemberNames.addAll(widget.conversation.memberNames);
    _scrollController.addListener(_handleScrollChanged);
    _messages = List.from(widget.conversation.messages);
    _mediaCtl
      ..chatId = widget.conversation.id
      ..chatName = _chatName
      ..onReply = _beginReply
      ..onForward = _forwardSingleMessage
      ..onReact = _reactSingleMessage
      ..onToggleStar = _toggleStarSingleMessage
      ..onDelete = _deleteSingleMessage
      ..hasMore = (() => _hasMorePages)
      ..onLoadOlder = _loadOlderMessages;
    unawaited(_warmAttachmentCache());
    if (widget.conversation.isGroup) unawaited(_loadGroupMemberNames());
    unawaited(_resolvePeerProfileIfNeeded());
    _loadInitialMessages();
    _outSub = OutgoingAttachmentManager.instance.events.listen(_onOutgoing);
    _messageSubscription = SocketChatService.instance.onNewMessage.listen(
      _handleIncomingMessage,
    );
    _typingSubscription = SocketChatService.instance.onTyping.listen(
      _handleTypingEvent,
    );
    _presenceSubscription = SocketChatService.instance.onPresence.listen(
      _handlePresenceEvent,
    );
    _readSubscription = SocketChatService.instance.onRead.listen(
      _handleReadEvent,
    );
    _deliveredSubscription = SocketChatService.instance.onDelivered.listen(
      _handleDeliveredEvent,
    );
    _editedSubscription = SocketChatService.instance.onMessageEdited.listen(
      _handleEditedMessage,
    );
    _deletedSubscription = SocketChatService.instance.onMessageDeleted.listen(
      _handleDeletedMessage,
    );
    _reactionSubscription = SocketChatService.instance.onMessageReaction.listen(
      _handleReactionMessage,
    );

    final savedDraft = LocalChatStorage.instance.getDraft(widget.conversation.id);
    if (savedDraft != null && savedDraft.isNotEmpty) {
      _inputController.text = savedDraft;
    }
    _inputController.addListener(_onInputTextChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _markChatRead();
      }
    });
  }

  void _onInputTextChanged() {
    LocalChatStorage.instance.saveDraft(
      widget.conversation.id,
      _inputController.text,
    );
  }


  Future<void> _warmAttachmentCache() async {
    await AttachmentCacheService.instance.warmUp();
    // Rebuild once the persisted index is available so downloaded photo groups
    // are rendered immediately instead of being assembled again.
    if (mounted) setState(() {});
  }

  Future<List<ChatMessage>> _loadPlainCachedMessages() async {
    final cached = await LocalChatStorage.instance.loadMessages(
      widget.conversation.id,
      chatDisappearType: _disappearType,
      keepReadSessionMessages: true,
    );
    var changed = false;
    final plainCached = cached.map((message) {
      final encryptedText = message.content;
      if (!encryptedText.startsWith('ENC:v1:')) return message;
      final decryptedText = E2eCryptoService.instance.decryptText(
        encryptedText,
        'chat_key_${widget.conversation.id}',
      );
      changed = true;
      // The crypto service returns the original encrypted text on a failure.
      // An empty placeholder is safer than ever showing ciphertext.
      return message.copyWith(
        content: decryptedText == encryptedText ? '' : decryptedText,
      );
    }).toList();
    if (changed) {
      unawaited(
        LocalChatStorage.instance.cacheMessages(
          widget.conversation.id,
          plainCached,
          chatDisappearType: _disappearType,
          keepReadSessionMessages: true,
        ),
      );
    }
    return plainCached;
  }

  Future<void> _loadGroupMemberNames() async {
    final id = int.tryParse(widget.conversation.id);
    if (id == null) return;
    final details = await ServerApiService.instance.getChatDetails(id);
    if (!mounted || details == null) return;
    setState(() {
      for (final member in details.members) {
        _groupMemberNames[member.id] = member.name;
      }
    });
  }

  Future<void> _resolvePeerProfileIfNeeded() async {
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null) return;

    final peerId = widget.conversation.peerUserId;

    if (peerId != null && peerId > 0) {
      try {
        final user = await ServerApiService.instance.getUser(peerId);
        if (user != null && mounted) {
          _isPeerOnline.value = user.isOnline;
          String name = user.name;
          if (name.isEmpty || name == 'User' || name.startsWith('User #')) {
            if (user.phone?.isNotEmpty == true) {
              name = user.phone!;
            } else if (user.email?.isNotEmpty == true) {
              name = user.email!;
            }
          }
          final newName = (name.isNotEmpty && !name.startsWith('User #'))
              ? name
              : _chatName;
          final newAvatar = (user.avatar != null && user.avatar!.isNotEmpty)
              ? user.avatar!
              : _chatAvatar;
          setState(() {
            _chatName = newName;
            _chatAvatar = newAvatar;
          });
          await LocalChatStorage.instance.updatePeerProfile(
            deviceId: widget.conversation.id,
            displayName: newName,
            avatarUrl: user.avatar,
          );
        }
      } catch (_) {}
    }

    try {
      final details = await ServerApiService.instance.getChatDetails(chatId);
      if (details != null && mounted) {
        final currentUserId = ServerApiService.instance.currentUserId;
        final otherMembers = details.members
            .where((m) => m.id != currentUserId)
            .toList();
        final peer = otherMembers.isNotEmpty ? otherMembers.first : null;

        if (peer != null) {
          PresenceStore.instance.bindChatUser(widget.conversation.id, peer.id);

          final livePresence = PresenceStore.instance.getPresence(peer.id);
          final effectiveOnline = livePresence != null ? livePresence.isOnline : peer.isOnline;
          _isPeerOnline.value = effectiveOnline;

          final peerLastSeen = peer.lastSeenAt != null
              ? DateTime.tryParse(peer.lastSeenAt!)?.toLocal()
              : null;

          PresenceStore.instance.updatePresence({
            'user_id': peer.id,
            'is_online': peer.isOnline,
            'last_seen_at': peer.lastSeenAt,
            'last_seen_text': peer.lastSeenText ?? (peer.isOnline ? 'online' : null),
            'chat_head_id': widget.conversation.id,
          });

          unawaited(
            LocalChatStorage.instance.updateConversation(
              widget.conversation.id,
                  (c) => c.copyWith(
                peerUserId: peer.id,
                isOnline: effectiveOnline,
                lastSeenAt: peerLastSeen,
              ),
            ),
          );
        }

        final resolvedName = details.isGroup
            ? (details.groupName ?? 'Group chat')
            : (peer?.name.isNotEmpty == true && !peer!.name.startsWith('User #')
            ? peer.name
            : (peer?.phone ?? peer?.email ?? _chatName));

        final resolvedAvatar = details.isGroup
            ? (details.groupAvatar ?? '')
            : (peer?.avatar ?? details.groupAvatar ?? '');

        final finalName =
        (resolvedName.isNotEmpty && !resolvedName.startsWith('User #'))
            ? resolvedName
            : _chatName;
        final finalAvatar = resolvedAvatar.isNotEmpty
            ? resolvedAvatar
            : _chatAvatar;

        setState(() {
          _chatName = finalName;
          _chatAvatar = finalAvatar;
        });

        await LocalChatStorage.instance.updatePeerProfile(
          deviceId: widget.conversation.id,
          displayName: finalName,
          avatarUrl: finalAvatar,
        );
      }
    } catch (_) {}
  }

  void _handleScrollChanged() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.position.pixels > 180;
    if (show != _showJumpToLatest) setState(() => _showJumpToLatest = show);
    if (!show) _newMessagesWhileAway = 0;

    if (_scrollController.position.userScrollDirection != ScrollDirection.idle) {
      if (_inputFocusNode.hasFocus) _inputFocusNode.unfocus();
      _composerCtl.closePanels(); // animates the GIF panel down
    }

    // Trigger pagination when scrolling UP near top of chat history
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 250) {
      if (!_isLoadingMore && _hasMorePages && !_isLoadingMessages) {
        _loadOlderMessages();
      }
    }
  }

  void _beginReply(ChatMessage message) {
    if (int.tryParse(message.id) == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _editingMessage = null;
      _replyingMessage = message;
    });
    _inputFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingMessage = null);
  }

  int _compareChatMessages(ChatMessage a, ChatMessage b) {
    final timeCmp = a.timestamp.compareTo(b.timestamp);
    if (timeCmp != 0) return timeCmp;

    final intA = int.tryParse(a.id);
    final intB = int.tryParse(b.id);
    if (intA != null && intB != null) {
      return intA.compareTo(intB);
    }

    if (a.id.startsWith('temp_') || a.id.startsWith('local_')) {
      if (!b.id.startsWith('temp_') && !b.id.startsWith('local_')) {
        return 1;
      }
    } else if (b.id.startsWith('temp_') || b.id.startsWith('local_')) {
      return -1;
    }

    return a.id.compareTo(b.id);
  }

  void _onOutgoing(OutgoingEvent e) {
    if (!mounted || e.chatId != widget.conversation.id) return;
    switch (e.type) {
      case OutgoingEventType.sent:
        final real = e.message!;
        setState(() {
          _pendingLocalToRealIdMap[e.localId] = real.id;
          _matchedLocalIds.add(e.localId);
          _messages.removeWhere((m) => m.id == real.id && m.id != e.localId); // socket echo
          final i = _messages.indexWhere((m) => m.id == e.localId);
          if (i >= 0) {
            _messages[i] = real;
          } else {
            _messages.add(real);
          }
          _adjustRemainingLocalMessageTimestamps(real.timestamp);
          _messages.sort(_compareChatMessages);
        });
        break;
      case OutgoingEventType.failed:
        _setMessageStatus(e.localId, 'failed');
        break;
      case OutgoingEventType.retrying:
        _setMessageStatus(e.localId, 'sending');
        break;
      case OutgoingEventType.discarded:
        setState(() => _messages.removeWhere((m) => m.id == e.localId));
        break;
    }
  }

  void _handleIncomingMessage(ServerMessageModel serverMessage) {
    if (!mounted ||
        serverMessage.chatHeadId.toString() != widget.conversation.id) {
      return;
    }
    final wasNearLatest =
        !_scrollController.hasClients ||
            _scrollController.position.pixels < 180;
    final currentUserId = ServerApiService.instance.currentUserId;

    if (serverMessage.senderId != currentUserId && serverMessage.chatHeadId > 0) {
      unawaited(ServerApiService.instance.markDeliveredREST(chatId: serverMessage.chatHeadId));
    }
    final plaintext = serverMessage.decryptedContent(
      'chat_key_${serverMessage.chatHeadId}',
    );
    DateTime timestamp;
    try {
      timestamp = DateTime.parse(serverMessage.createdAt).toLocal();
    } catch (_) {
      timestamp = DateTime.now();
    }
    final isSmCall = serverMessage.msgType == 'call' ||
        serverMessage.callStatus != null ||
        serverMessage.callId != null;
    final smFileType = serverMessage.fileType?.toLowerCase().trim();
    final rawFilePath = serverMessage.filePath?.trim();
    final rawFileName = serverMessage.fileName?.trim();

    final rawMsgContent = serverMessage.isDeleted
        ? 'This message was deleted'
        : (plaintext.isEmpty ? (serverMessage.message ?? '') : plaintext);
    final msgContent = cleanMessageContentString(rawMsgContent);

    final msgText = msgContent.trim();
    final isGifContent = smFileType == 'image/gif' ||
        smFileType == 'gif' ||
        (msgText.startsWith('http://') || msgText.startsWith('https://')) &&
            (msgText.toLowerCase().contains('.gif') ||
                msgText.toLowerCase().contains('giphy.com') ||
                msgText.toLowerCase().contains('tenor.com'));

    final isStickerContent = smFileType == 'sticker' || msgText.startsWith('stk_');

    final isMediaContent = isGifContent ||
        isStickerContent ||
        (rawFilePath != null && rawFilePath.isNotEmpty) ||
        (rawFileName != null && rawFileName.isNotEmpty);

    final isSmText = !isSmCall &&
        !isMediaContent &&
        (smFileType == 'text' || smFileType == 'text/plain' || smFileType == null || smFileType.isEmpty);

    final effectiveType = isSmCall
        ? 'call'
        : (isStickerContent
        ? 'sticker'
        : (isGifContent
        ? 'image/gif'
        : (isSmText
        ? 'text'
        : (inferAttachmentType(
      fileType: serverMessage.fileType,
      fileName: serverMessage.fileName,
      filePath: serverMessage.filePath,
    ) ??
        'application/octet-stream'))));

    final effectiveMediaUrl = isSmText || isSmCall
        ? null
        : ((rawFilePath != null && rawFilePath.isNotEmpty)
        ? rawFilePath
        : (isGifContent ? msgText : null));

    final myUserIdStr = currentUserId?.toString() ?? '';
    final isMine = (serverMessage.senderId.toString() == myUserIdStr) ||
        (serverMessage.senderId.toString() == 'user');

    final incoming = ChatMessage(
      id: serverMessage.id.toString(),
      senderId: isMine ? 'user' : serverMessage.senderId.toString(),
      content: msgContent,
      timestamp: timestamp,
      type: effectiveType,
      mediaUrl: effectiveMediaUrl,
      fileName: isSmText || isSmCall
          ? null
          : ((serverMessage.fileName != null &&
          serverMessage.fileName!.trim().isNotEmpty)
          ? serverMessage.fileName
          : null),
      isRead: isMine ? serverMessage.isRead : true,
      isDelivered: isMine ? (serverMessage.isDelivered || serverMessage.isRead) : true,
      status: isMine ? serverMessage.status : 'read',
      isEdited: serverMessage.isEdited,
      isDeleted: serverMessage.isDeleted,
      reaction: serverMessage.chatReact,
      replyToId: serverMessage.replyToId,
      msgType: serverMessage.msgType ?? (isSmCall ? 'call' : null),
      callId: serverMessage.callId,
      callType: serverMessage.callType,
      callStatus: serverMessage.callStatus,
      callDuration: serverMessage.callDuration,
      isForwarded:
          serverMessage.forwardedFlag('chat_key_${serverMessage.chatHeadId}'),
    );
    if (_isLoadingMessages) {
      _messagesReceivedWhileLoading[incoming.id] = incoming;
    }

    // Check if message is already present by ID or matches optimistic/existing local message
    final existingIndex = _messages.indexWhere(
          (message) {
        // 1. Exact ID match (both server IDs, or same local ID)
        if (message.id == incoming.id) return true;

        // 2. Check if this server message matches a mapped localMsgId
        if ((_pendingLocalToRealIdMap.containsKey(message.id) &&
            _pendingLocalToRealIdMap[message.id] == incoming.id) ||
            OutgoingAttachmentManager.instance.realIdFor(message.id) == incoming.id) {
          return true;
        }

        // 3. Do NOT match confirmed server messages with different server IDs!
        final isMessageLocal = message.id.startsWith('local_') ||
            message.id.startsWith('fwd_') ||
            message.id.startsWith('temp_');
        if (!isMessageLocal) return false;

        if (_matchedLocalIds.contains(message.id)) return false;

        // 4. Match pending local message sent by current user
        final isIncomingFromMe = incoming.senderId == 'user' ||
            incoming.senderId == myUserIdStr ||
            serverMessage.senderId.toString() == myUserIdStr;
        if (!isIncomingFromMe) return false;

        // Check if both are media attachments or document files
        final messageHasMedia = message.mediaUrl != null && message.mediaUrl!.isNotEmpty;
        final incomingHasMedia = incoming.mediaUrl != null && incoming.mediaUrl!.isNotEmpty;

        if (messageHasMedia || incomingHasMedia || message.type != 'text') {
          String nameOf(ChatMessage m) => (m.fileName?.trim().isNotEmpty == true
              ? m.fileName!
              : (m.mediaUrl ?? '').split('/').last.split('\\').last)
              .toLowerCase()
              .trim();
          final a = nameOf(message), b = nameOf(incoming);
          return a.isNotEmpty && a == b;   // never match media by time
        }

        final contentMatches = message.content.trim() == incoming.content.trim();
        final timeDiff = incoming.timestamp.difference(message.timestamp).inSeconds.abs();
        return contentMatches && timeDiff <= 120;
      },
    );

    if (existingIndex >= 0) {
      final oldLocal = _messages[existingIndex].mediaUrl;
      if (incoming.mediaUrl != null &&
          oldLocal != null &&
          !oldLocal.startsWith('http') &&
          File(oldLocal).existsSync()) {
        AttachmentCacheService.instance.updateCache(incoming.mediaUrl!, oldLocal);
      }
      final oldLocalId = _messages[existingIndex].id;
      if (oldLocalId.startsWith('local_') || oldLocalId.startsWith('temp_')) {
        _matchedLocalIds.add(oldLocalId);
        _pendingLocalToRealIdMap[oldLocalId] = incoming.id;
      }
      final old = _messages[existingIndex];
      final mergedIncoming = incoming.copyWith(
        isForwarded: incoming.isForwarded || old.isForwarded,
      );
      setState(() {
        _messages[existingIndex] = mergedIncoming;
        _adjustRemainingLocalMessageTimestamps(mergedIncoming.timestamp);
        _messages.sort(_compareChatMessages);
      });
      if (wasNearLatest || incoming.senderId == 'user') _scrollToBottom();
      return;
    }

    // Secondary check: remove any pending local message if incoming is duplicate
    final dupIndex = _messages.indexWhere(
          (m) => m.id == incoming.id || _pendingLocalToRealIdMap[m.id] == incoming.id,
    );
    if (dupIndex >= 0) {
      final old = _messages[dupIndex];
      final mergedIncoming = incoming.copyWith(
        isForwarded: incoming.isForwarded || old.isForwarded,
      );
      setState(() {
        _messages[dupIndex] = mergedIncoming;
        _adjustRemainingLocalMessageTimestamps(mergedIncoming.timestamp);
        _messages.sort(_compareChatMessages);
      });
      if (wasNearLatest || incoming.senderId == 'user') _scrollToBottom();
      return;
    }

    _messages.removeWhere((m) => m.id == incoming.id || _pendingLocalToRealIdMap[m.id] == incoming.id);

    setState(() {
      _messages = [..._messages, incoming]..sort(_compareChatMessages);
      if (!wasNearLatest && incoming.senderId != 'user') {
        _newMessagesWhileAway++;
      }
    });
    if (incoming.senderId != 'user') {
      unawaited(
        ServerChatManager.instance.markChatRead(widget.conversation.id),
      );
    }
    if (wasNearLatest || incoming.senderId == 'user') _scrollToBottom();
  }

  void _handleTypingEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final event = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;
    final eventChatId =
    (event['chat_head_id'] ??
        event['chat_id'] ??
        event['chatHeadId'] ??
        event['chatId'])
        ?.toString();
    if (eventChatId == widget.conversation.id) {
      final eventUserId = int.tryParse(
        (event['user_id'] ??
            event['userId'] ??
            event['sender_id'] ??
            event['senderId'])
            ?.toString() ??
            '',
      );
      if (eventUserId != null &&
          eventUserId == ServerApiService.instance.currentUserId) {
        return;
      }
      final rawTyping =
          event['is_typing'] ?? event['typing'] ?? event['isTyping'];
      final isTyping =
          rawTyping == true ||
              rawTyping == 1 ||
              rawTyping?.toString().toLowerCase() == 'true';
      _peerTypingTimer?.cancel();
      _isPeerTyping.value = isTyping;
      if (isTyping) {
        _peerTypingTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) _isPeerTyping.value = false;
        });
        if (!_scrollController.hasClients ||
            _scrollController.position.pixels < 220) {
          _scrollToBottom();
        }
      }
    }
  }

  void _handlePresenceEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : event;

    final userId = int.tryParse(
      (data['user_id'] ?? data['userId'] ?? data['id'])?.toString() ?? '',
    );

    final myUserId = ServerApiService.instance.currentUserId;
    if (myUserId != null && myUserId > 0 && userId != null && userId == myUserId) {
      // Ignore presence events for myself
      return;
    }

    final directPeerId = widget.conversation.peerUserId ??
        PresenceStore.instance.getUserIdForChat(widget.conversation.id) ??
        (widget.conversation.isGroup ? null : int.tryParse(widget.conversation.id));

    final chatHeadId =
    (data['chat_head_id'] ?? data['chat_id'] ?? data['chatHeadId'])
        ?.toString();

    final matchesChat =
        chatHeadId != null &&
            chatHeadId.isNotEmpty &&
            chatHeadId == widget.conversation.id;

    final matchesUser = userId != null &&
        ((directPeerId != null && userId == directPeerId) ||
            (!widget.conversation.isGroup && widget.conversation.id == userId.toString()));

    if (!matchesChat && !matchesUser) {
      return;
    }

    final online = data['is_online'] ?? data['online'] ?? data['status'];
    if (online != null) {
      final isOnline =
          online == true ||
              online == 1 ||
              online.toString().toLowerCase() == 'online' ||
              online.toString().toLowerCase() == 'true';

      _isPeerOnline.value = isOnline;

      final rawLastSeen =
          data['last_seen_at'] ?? data['lastSeenAt'] ?? data['updated_at'];
      final parsedLastSeen = rawLastSeen != null
          ? DateTime.tryParse(rawLastSeen.toString())?.toLocal()
          : null;

      unawaited(
        LocalChatStorage.instance.updateConversation(
          widget.conversation.id,
              (c) => c.copyWith(
            isOnline: isOnline,
            lastSeenAt:
            isOnline
                ? null
                : (parsedLastSeen ?? (c.isOnline ? DateTime.now() : (c.lastSeenAt ?? DateTime.now()))),
          ),
        ),
      );
    }
  }

  void _handleReadEvent(Map<String, dynamic> raw) {
    if (!mounted) return;
    debugPrint('[CHAT DETAIL] Socket messages read event: $raw');

    var data = raw;
    if (data['data'] is Map) {
      data = Map<String, dynamic>.from(data['data'] as Map);
    }

    final eventChatId = (data['chat_head_id'] ??
        data['chat_id'] ??
        data['chatHeadId'] ??
        data['chatId'])
        ?.toString();

    final rawReader = data['reader_id'] ??
        data['readerId'] ??
        data['read_by'] ??
        data['readBy'] ??
        data['by_user_id'] ??
        data['by_user'] ??
        data['byUser'] ??
        data['user_id'] ??
        data['userId'];

    final readerId = int.tryParse(rawReader?.toString() ?? '');
    final currentUserId = ServerApiService.instance.currentUserId ?? LocalChatStorage.instance.accountId;
    final peerUserId = widget.conversation.peerUserId ??
        PresenceStore.instance.getUserIdForChat(widget.conversation.id) ??
        (widget.conversation.isGroup ? null : int.tryParse(widget.conversation.id));

    if (eventChatId != widget.conversation.id) return;

    // Ignore read events triggered by ourselves
    if (currentUserId != null && readerId == currentUserId) {
      debugPrint('[CHAT DETAIL] Ignoring self-triggered read event (readerId=$readerId, currentUserId=$currentUserId)');
      return;
    }

    // Must be triggered by the peer
    if (peerUserId != null && readerId != null && readerId != peerUserId) {
      debugPrint('[CHAT DETAIL] Ignoring read event not from peer (readerId=$readerId, peerUserId=$peerUserId)');
      return;
    }

    final rawReadAt = data['last_read_at'] ??
        data['lastReadAt'] ??
        data['read_at'] ??
        data['readAt'] ??
        data['seen_at'] ??
        data['seenAt'] ??
        data['updated_at'] ??
        data['updatedAt'];

    final targetMsgId =
    (data['message_id'] ?? data['messageId'] ?? data['id'])?.toString();

    DateTime? cutoff;
    if (rawReadAt != null) {
      final parsed = DateTime.tryParse(rawReadAt.toString());
      if (parsed != null) {
        cutoff = parsed.toLocal();
      }
    }
    cutoff ??= DateTime.now();

    var changed = false;
    final updatedMessages = _messages.map((message) {
      if (message.senderId == 'user') {
        final matchesSpecificId = targetMsgId != null &&
            targetMsgId.isNotEmpty &&
            (message.id == targetMsgId ||
                _pendingLocalToRealIdMap[message.id] == targetMsgId);
        final isBeforeCutoff = !message.timestamp.isAfter(cutoff!);

        final shouldMarkRead = matchesSpecificId ||
            (targetMsgId == null && isBeforeCutoff);

        if (shouldMarkRead &&
            (!message.isRead ||
                !message.isDelivered ||
                message.status.toLowerCase() != 'read')) {
          changed = true;
          return message.copyWith(
            isRead: true,
            isDelivered: true,
            status: 'read',
          );
        }
      }
      return message;
    }).toList();

    if (!changed) return;

    setState(() => _messages = updatedMessages);
    unawaited(
      LocalChatStorage.instance.cacheMessages(
        widget.conversation.id,
        updatedMessages,
        chatDisappearType: _disappearType,
        keepReadSessionMessages: true,
      ),
    );
  }

  void _handleDeliveredEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final eventChatId =
    (data['chat_head_id'] ??
        data['chat_id'] ??
        data['chatHeadId'] ??
        data['chatId'])
        ?.toString();
    if (eventChatId != widget.conversation.id) return;

    var changed = false;
    final updatedMessages = _messages.map((message) {
      if (message.senderId == 'user' && !message.isDelivered) {
        changed = true;
        return message.copyWith(isDelivered: true, status: 'delivered');
      }
      return message;
    }).toList();

    if (!changed) return;

    setState(() => _messages = updatedMessages);
    unawaited(
      LocalChatStorage.instance.cacheMessages(
        widget.conversation.id,
        updatedMessages,
        chatDisappearType: _disappearType,
        keepReadSessionMessages: true,
      ),
    );
  }

  void _onTypingChanged(bool isTyping) {
    final numericId = int.tryParse(widget.conversation.id);
    if (numericId == null) return;

    SocketChatService.instance.sendTyping(
      chatHeadId: numericId,
      isTyping: isTyping,
    );
  }

  Future<void> _markChatRead() async {
    await ServerChatManager.instance.markChatRead(widget.conversation.id);

    // Mark unread messages as read in memory without purging immediately during active viewing session
    if (mounted) {
      bool changed = false;
      final updatedMessages = <ChatMessage>[];
      for (final m in _messages) {
        if (m.senderId != 'user' && !m.isRead) {
          updatedMessages.add(m.copyWith(isRead: true));
          changed = true;
        } else {
          updatedMessages.add(m);
        }
      }
      if (changed) {
        setState(() {
          _messages = updatedMessages;
        });
      }
    }
  }

  Future<void> _reloadMessages() async {
    final generation = ++_historyLoadGeneration;
    if (mounted) {
      setState(() {
        _isLoadingMessages = true;
        _historyError = null;
      });
    }

    try {
      final res = await ServerChatManager.instance.loadMessagesPage(
        widget.conversation.id,
        page: 1,
        limit: 20,
        chatDisappearType: _disappearType,
        keepReadSessionMessages: true,
      );

      if (!mounted || generation != _historyLoadGeneration) return;

      final filtered = res.messages
          .where(
            (m) => !isMessageExpired(
          m,
          chatDisappearType: _disappearType,
          keepReadSessionMessages: true,
        ),
      )
          .toList();

      final confirmedServerIds = filtered.map((m) => m.id).toSet();
      final filteredLocalMessages = _messages.where((m) {
        if (!m.id.startsWith('local_') && !m.id.startsWith('temp_')) return false;
        if (_matchedLocalIds.contains(m.id)) return false;
        if (_pendingLocalToRealIdMap.containsKey(m.id)) {
          final realId = _pendingLocalToRealIdMap[m.id];
          if (confirmedServerIds.contains(realId)) return false;
        }
        if (OutgoingAttachmentManager.instance.realIdFor(m.id) != null) return false;
        return true;
      }).toList();

      final mergedById = <String, ChatMessage>{
        for (final m in filteredLocalMessages) m.id: m,
      };
      for (final message in filtered) {
        final prev = mergedById[message.id];
        mergedById[message.id] = (prev?.isForwarded == true)
            ? message.copyWith(isForwarded: true)
            : message;
      }
      mergedById.addAll(_messagesReceivedWhileLoading);
      final merged =
      mergedById.values
          .where(
            (m) => !isMessageExpired(
          m,
          chatDisappearType: _disappearType,
          keepReadSessionMessages: true,
        ),
      )
          .toList()
        ..sort(_compareChatMessages);

      setState(() {
        _messages = merged;
        _currentPage = res.page;
        _totalPages = res.totalPages;
        _hasMorePages = res.hasMore;
        _historyError = null;
        _isLoadingMessages = false;
      });
      _recoverOrphanedUploads();
      _messagesReceivedWhileLoading.clear();
      _scrollToBottom();
      unawaited(_markChatRead());
    } catch (error) {
      debugPrint('[CHAT] Failed to load server history: $error');
      final cached = await _loadPlainCachedMessages();
      if (mounted && generation == _historyLoadGeneration) {
        setState(() {
          _messages = cached;
          _isLoadingMessages = false;
        });
      }
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingMore || !_hasMorePages) return;

    setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final res = await ServerChatManager.instance.loadMessagesPage(
        widget.conversation.id,
        page: nextPage,
        limit: 20,
        chatDisappearType: _disappearType,
        keepReadSessionMessages: true,
      );

      if (mounted) {
        final existingById = {for (final m in _messages) m.id: m};
        for (final m in res.messages) {
          existingById[m.id] = m;
        }
        final merged = existingById.values.toList()..sort(_compareChatMessages);

        setState(() {
          _messages = merged;
          _currentPage = res.page;
          _totalPages = res.totalPages;
          _hasMorePages = res.hasMore;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint(
        '[CHAT] Error loading older messages page ${_currentPage + 1}: $e',
      );
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _loadInitialMessages() async {
    final cached = await _loadPlainCachedMessages();
    if (!mounted) return;
    final validCached = cached
        .where(
          (m) => !isMessageExpired(
        m,
        chatDisappearType: _disappearType,
        keepReadSessionMessages: true,
      ),
    )
        .toList();
    if (validCached.isNotEmpty) {
      final byId = {for (final message in validCached) message.id: message};
      byId.addAll(_messagesReceivedWhileLoading);
      final messages =
      byId.values
          .where(
            (m) => !isMessageExpired(
          m,
          chatDisappearType: _disappearType,
          keepReadSessionMessages: true,
        ),
      )
          .toList()
        ..sort(_compareChatMessages);
      setState(() {
        _messages = messages;
        _isLoadingMessages = false;
        _historyError = null;
      });
      _recoverOrphanedUploads();
      _messagesReceivedWhileLoading.clear();
      _scrollToInitialPosition();
    } else {
      setState(() {
        _isLoadingMessages = true;
      });
    }

    // Always call server API to fetch latest updated message list when entering chat screen
    await _reloadMessages();
    unawaited(_syncChatDetails());
  }

  int get _firstUnreadMessageIndex {
    if (_initialUnreadCount <= 0) return -1;
    var peerCount = 0;
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].senderId != 'user') {
        peerCount++;
        if (peerCount == _initialUnreadCount) {
          return i;
        }
      }
    }
    for (int i = 0; i < _messages.length; i++) {
      if (_messages[i].senderId != 'user') return i;
    }
    return -1;
  }

  void _scrollToInitialPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final targetIndex = _firstUnreadMessageIndex;
      if (targetIndex >= 0) {
        final reversedIndex = (_messages.length - 1) - targetIndex;
        final viewportHeight = _scrollController.position.viewportDimension;
        final targetOffset =
            (reversedIndex * 78.0) - (viewportHeight / 2) + 50.0;
        final clamped = targetOffset.clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(clamped);
      } else {
        _scrollController.jumpTo(0);
      }
    });
  }

  Future<void> _syncChatDetails() async {
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null) return;
    try {
      final details = await ServerApiService.instance.getChatDetails(chatId);
      if (details != null && mounted) {
        if (details.disappearType != _disappearType) {
          setState(() {
            _disappearType = details.disappearType;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _showCachedMessages() async {
    final cached = await _loadPlainCachedMessages();
    if (!mounted) return;

    final byId = {for (final m in _messages) m.id: m};
    for (final c in cached) {
      // skip stale optimistic rows that were already resolved
      if (_matchedLocalIds.contains(c.id) ||
          _pendingLocalToRealIdMap.containsKey(c.id)) {
        continue;
      }
      // in-memory copy always wins (it has the newest status)
      byId.putIfAbsent(c.id, () => c);
    }
    final merged = byId.values.toList()..sort(_compareChatMessages);
    setState(() => _messages = merged);
    _scrollToBottom();
  }

  Future<void> _handleEditedMessage(Map<String, dynamic> event) async {
    var data = event;
    if (event['data'] is Map) {
      data = Map<String, dynamic>.from(event['data'] as Map);
    }
    if (data['message'] is Map) {
      data = Map<String, dynamic>.from(data['message'] as Map);
    }
    final messageId = (data['id'] ?? data['message_id'] ?? data['messageId'])
        ?.toString();
    final eventChatId =
    (data['chat_head_id'] ??
        data['chat_id'] ??
        data['chatHeadId'] ??
        data['chatId'] ??
        event['chat_head_id'] ??
        event['chat_id'])
        ?.toString();
    final rawValue = data['ciphertext'] ?? data['content'] ?? data['message'];
    final encryptedText = rawValue is String ? rawValue : null;
    if (messageId == null || encryptedText == null || !mounted) return;
    if (eventChatId != null && eventChatId != widget.conversation.id) return;

    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;

    final current = _messages[index];
    final needsDecryption = encryptedText.startsWith('ENC:v1:');
    final showLoading =
        needsDecryption &&
            (current.content.trim().isEmpty ||
                current.content.startsWith('ENC:v1:'));
    if (showLoading) {
      setState(() => _decryptingEditedMessageIds.add(messageId));
      // Yield one frame so an empty bubble has a clear loading state while the
      // crypto work is resolved. Existing text stays visible during an edit.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
    }

    final decryptedText = E2eCryptoService.instance.decryptText(
      encryptedText,
      'chat_key_${widget.conversation.id}',
    );
    // decryptText intentionally returns its input if decryption fails. Never
    // put that encrypted fallback into a visible or cached chat message.
    final hasValidPlaintext =
        !needsDecryption || decryptedText != encryptedText;
    final resolvedText = hasValidPlaintext ? decryptedText : current.content;

    final refreshedIndex = _messages.indexWhere(
          (message) => message.id == messageId,
    );
    if (refreshedIndex < 0) {
      if (showLoading && mounted) {
        setState(() => _decryptingEditedMessageIds.remove(messageId));
      }
      return;
    }
    final updated = _messages[refreshedIndex].copyWith(
      content: resolvedText,
      isEdited: true,
    );
    setState(() {
      _messages[refreshedIndex] = updated;
      _decryptingEditedMessageIds.remove(messageId);
    });
    await LocalChatStorage.instance.saveMessage(
      deviceId: widget.conversation.id,
      peerName: _chatName,
      message: updated,
      markUnread: false,
      peerUserId: widget.conversation.peerUserId,
    );
  }

  void _handleDeletedMessage(Map<String, dynamic> event) {
    var data = event;
    if (event['data'] is Map) {
      data = Map<String, dynamic>.from(event['data'] as Map);
    }
    if (data['message'] is Map) {
      data = Map<String, dynamic>.from(data['message'] as Map);
    }
    final messageId = (data['id'] ?? data['message_id'] ?? data['messageId'])?.toString();
    if (messageId == null || !mounted) return;

    final rawDeleteType = data['type'] ?? data['delete_type'];
    final deleteType = rawDeleteType is int
        ? rawDeleteType
        : int.tryParse(rawDeleteType?.toString() ?? '2') ?? 2;

    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;

    if (deleteType == 2) {
      // Delete for me
      setState(() {
        _messages.removeAt(index);
        if (_editingMessage?.id == messageId) _editingMessage = null;
      });
      unawaited(
        LocalChatStorage.instance.deleteLocalMessage(
          widget.conversation.id,
          messageId,
        ),
      );
      return;
    }

    // Delete for everyone (deleteType == 1)
    final updated = _messages[index].copyWith(
      content: 'This message was deleted',
      isDeleted: true,
    );
    setState(() {
      _messages[index] = updated;
    });
    unawaited(
      LocalChatStorage.instance.saveMessage(
        deviceId: widget.conversation.id,
        peerName: _chatName,
        message: updated,
        markUnread: false,
        peerUserId: widget.conversation.peerUserId,
      ),
    );
  }

  void _handleReactionMessage(Map<String, dynamic> event) {
    var data = event;
    if (event['data'] is Map) {
      data = Map<String, dynamic>.from(event['data'] as Map);
    }
    if (data['message'] is Map) {
      data = Map<String, dynamic>.from(data['message'] as Map);
    }
    final messageId = (data['id'] ?? data['message_id'])?.toString();
    final reaction = normalizeChatReaction(
      data['chat_react'] ?? data['reaction'],
    );
    if (messageId == null || reaction == null || !mounted) return;
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    setState(() {
      _messages[index] = _messages[index].copyWith(reaction: reaction);
    });
  }

  bool _isImageMsg(ChatMessage msg) {
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

  Future<void> _shareMessage(ChatMessage message) async {
    try {
      final mediaUrl = message.mediaUrl;
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        AppToast.show('Preparing files for sharing...');

        final grouped = <ChatMessage>[];
        final msgIndex = _messages.indexWhere((m) => m.id == message.id);
        if (msgIndex != -1 && _isImageMsg(message)) {
          int start = msgIndex;
          while (start > 0 &&
              _isImageMsg(_messages[start - 1]) &&
              _messages[start - 1].senderId == message.senderId &&
              message.timestamp
                  .difference(_messages[start - 1].timestamp)
                  .inMinutes
                  .abs() <=
                  15) {
            start--;
          }
          int end = msgIndex;
          while (end < _messages.length - 1 &&
              _isImageMsg(_messages[end + 1]) &&
              _messages[end + 1].senderId == message.senderId &&
              _messages[end]
                  .timestamp
                  .difference(_messages[end + 1].timestamp)
                  .inMinutes
                  .abs() <=
                  15) {
            end++;
          }

          for (int i = start; i <= end; i++) {
            grouped.add(_messages[i]);
          }
        }

        final shareFiles = <XFile>[];
        final targets = grouped.isNotEmpty ? grouped : [message];

        for (final targetMsg in targets) {
          final localPath = await _downloadOrResolveFile(targetMsg);
          if (localPath != null && await File(localPath).exists()) {
            shareFiles.add(XFile(localPath));
          }
        }

        if (shareFiles.isNotEmpty) {
          final caption =
          message.content.isNotEmpty &&
              message.content != 'Sent a photo' &&
              message.content != 'Sent an attachment'
              ? message.content
              : null;
          await SharePlus.instance.share(
            ShareParams(files: shareFiles, text: caption),
          );
          return;
        }
      }

      if (message.content.isNotEmpty) {
        AppToast.show('Sharing message...');
        await SharePlus.instance.share(ShareParams(text: message.content));
      }
    } catch (e) {
      AppToast.show(AppToast.userFriendlyMessage('Could not share message: $e'), isError: true);
    }
  }

  Future<String?> _downloadOrResolveFile(ChatMessage message) async {
    final mediaUrl = message.mediaUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) return null;

    final file = File(mediaUrl);
    if (!mediaUrl.startsWith('http://') &&
        !mediaUrl.startsWith('https://') &&
        file.existsSync()) {
      return file.path;
    }

    final documents = await getApplicationDocumentsDirectory();
    final filename = message.fileName?.isNotEmpty == true
        ? message.fileName!
        : (Uri.tryParse(mediaUrl)?.pathSegments.last ?? 'attachment');
    final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final cachedFile = File(
      '${documents.path}${Platform.pathSeparator}chat_attachments${Platform.pathSeparator}${message.timestamp.millisecondsSinceEpoch}_$safeName',
    );

    if (cachedFile.existsSync()) {
      if (cachedFile.lengthSync() > 16) {
        return cachedFile.path;
      } else {
        try {
          cachedFile.deleteSync();
        } catch (_) {}
      }
    }

    try {
      String downloadUrl = mediaUrl;
      if (!downloadUrl.startsWith('http://') &&
          !downloadUrl.startsWith('https://')) {
        String cleanPath = mediaUrl;
        if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(mediaUrl) ||
            RegExp(r'^/(?:data|storage|private|var|tmp|Users)/')
                .hasMatch(mediaUrl)) {
          if (mediaUrl.contains('uploads/')) {
            cleanPath = 'uploads/${mediaUrl.split('uploads/').last}';
          } else if (mediaUrl.contains('files/')) {
            cleanPath = 'files/${mediaUrl.split('files/').last}';
          } else {
            cleanPath = message.fileName?.trim().isNotEmpty == true
                ? message.fileName!
                : mediaUrl.split(RegExp(r'[/\\]')).last;
          }
        }
        final normalized = cleanPath.replaceFirst(RegExp(r'^/+'), '');
        final apiBase = ServerApiService.baseUrl.replaceFirst(
          RegExp(r'/+$'),
          '',
        );
        final filePath = normalized.startsWith('api/files/')
            ? normalized.substring('api/files/'.length)
            : normalized.startsWith('files/')
            ? normalized.substring('files/'.length)
            : normalized;
        final encodedPath = filePath
            .split('/')
            .map(Uri.encodeComponent)
            .join('/');
        downloadUrl = '$apiBase/files/$encodedPath';
      }

      final headers = ServerApiService.instance.authToken == null
          ? <String, String>{}
          : {'Authorization': 'Bearer ${ServerApiService.instance.authToken}'};

      final response = await http.get(Uri.parse(downloadUrl), headers: headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        var bytes = response.bodyBytes;
        final secretKey = 'chat_key_${widget.conversation.id}';
        final decrypted = E2eCryptoService.instance.decryptFileBytes(
          bytes,
          secretKey,
        );
        if (decrypted.length > 16) {
          bytes = decrypted;
        }
        await cachedFile.parent.create(recursive: true);
        await cachedFile.writeAsBytes(bytes, flush: true);
        return cachedFile.path;
      }
    } catch (_) {}

    return null;
  }

  void _enterSelectionMode(ChatMessage msg) {
    setState(() {
      _isSelectionMode = true;
      _selectedMessageIds.clear();
      _selectedMessageIds.add(msg.id);
    });
  }

  void _toggleSelectMessage(ChatMessage msg) {
    setState(() {
      if (_selectedMessageIds.contains(msg.id)) {
        _selectedMessageIds.remove(msg.id);
        if (_selectedMessageIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(msg.id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _openForwardDialog() {
    final selectedMsgs =
        _messages.where((m) => _selectedMessageIds.contains(m.id)).toList();
    if (selectedMsgs.isEmpty) return;

    ForwardChatSelectionDialog.show(
      context,
      selectedMessages: selectedMsgs,
      sourceChatId: widget.conversation.id,
    ).then((_) {
      if (mounted) _exitSelectionMode();
    });
  }

  void _forwardSingleMessage(ChatMessage msg) {
    ForwardChatSelectionDialog.show(
      context,
      selectedMessages: [msg],
      sourceChatId: widget.conversation.id,
    );
  }

  void _reactSingleMessage(ChatMessage msg, String emoji) {
    _reactToMessage(msg, emoji);
  }

  Future<bool> _toggleStarSingleMessage(ChatMessage msg) async {
    final nextSaved = !msg.isSaved;
    await _toggleSaveMessage(msg);
    return nextSaved;
  }

  void _deleteSingleMessage(ChatMessage msg) {
    _deleteMessage(msg);
  }

  Widget _buildSelectionHeader(bool isDark) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final count = _selectedMessageIds.length;
    final allSelected = count > 0 && count == _messages.length;

    return Container(
      padding: EdgeInsets.fromLTRB(16, topPadding + 10, 16, 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xF21C1C1E)
            : Colors.white.withValues(alpha: 0.92),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          GlassButton(
            width: 36,
            height: 36,
            radius: 18,
            isDark: isDark,
            onTap: _exitSelectionMode,
            child: Center(
              child: Icon(
                CupertinoIcons.xmark,
                size: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '$count Selected',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() {
                if (allSelected) {
                  _selectedMessageIds.clear();
                } else {
                  _selectedMessageIds.addAll(_messages.map((m) => m.id));
                }
              });
            },
            child: Text(
              allSelected ? 'Deselect All' : 'Select All',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBottomBar(bool isDark) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final count = _selectedMessageIds.length;
    final hasSelection = count > 0;
    final redColor = isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        math.max(12.0, bottomPadding + 6.0),
      ),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xF21C1C1E)
            : Colors.white.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Delete Button (Left - WhatsApp iOS Style)
          InkWell(
            onTap: hasSelection ? _deleteSelectedMessages : null,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.trash,
                    size: 20,
                    color: hasSelection
                        ? redColor
                        : (isDark ? Colors.white30 : Colors.black26),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    count > 0 ? 'Delete ($count)' : 'Delete',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: hasSelection
                          ? redColor
                          : (isDark ? Colors.white30 : Colors.black26),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Forward Button (Right - WhatsApp iOS Style)
          InkWell(
            onTap: hasSelection ? _openForwardDialog : null,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shortcut_rounded,
                    size: 20,
                    color: hasSelection
                        ? AppTheme.primaryColor
                        : (isDark ? Colors.white30 : Colors.black26),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Forward',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: hasSelection
                          ? AppTheme.primaryColor
                          : (isDark ? Colors.white30 : Colors.black26),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overlayBubble(ChatMessage message, bool isMine) {
    final replied = message.replyToId == null
        ? null
        : _messages.cast<ChatMessage?>().firstWhere(
              (m) => m?.id == message.replyToId.toString(),
              orElse: () => null,
            );
    return ChatBubble(
      id: message.id,
      sourceMessage: message,
      chatId: widget.conversation.id,
      message: message.content,
      isMe: isMine,
      timestamp: message.timestamp,
      type: message.type,
      mediaUrl: message.mediaUrl,
      fileName: message.fileName,
      isRead: message.isRead,
      isDelivered: message.isDelivered,
      status: message.status,
      isEdited: message.isEdited,
      isDeleted: message.isDeleted,
      isSaved: message.isSaved,
      callId: message.callId,
      callType: message.callType,
      callStatus: message.callStatus,
      callDuration: message.callDuration,
      msgType: message.msgType,
      onVoiceCallTap: _startVoiceCall,
      onVideoCallTap: _startVideoCall,
      senderName: !isMine && widget.conversation.isGroup
          ? _groupMemberNames[int.tryParse(message.senderId)]
          : null,
      replyToId: message.replyToId,
      repliedMessage: replied,
      replySender: replied == null
          ? null
          : replied.senderId == 'user'
              ? 'You'
              : widget.conversation.isGroup
                  ? (_groupMemberNames[int.tryParse(replied.senderId)] ?? 'Member')
                  : _chatName,
      replyText: replied?.previewText,
      isForwarded: message.isForwarded,
      reactions: message.reaction == null ? null : [message.reaction!],
    );
  }

  Future<void> _showMessageActions(
    ChatMessage message,
    Offset pos,
    Size size, {
    bool reactionsOnly = false,
  }) async {
    if (message.isDeleted) {
      _enterSelectionMode(message);
      _deleteSelectedMessages();
      return;
    }

    final screenW = MediaQuery.sizeOf(context).width;
    final isMine = message.senderId == 'user';
    final messageId = int.tryParse(message.id);

    // grid tiles report a small rect -> use a full-width row instead
    var rect = pos & size;
    if (rect.width < screenW * 0.9) {
      rect = Rect.fromLTWH(0, rect.top, screenW, rect.height);
    }

    final isCall = message.type == 'call' ||
        message.callStatus != null ||
        message.callId != null ||
        message.msgType == 'call';
    final callVideo = (message.callType ?? '').toLowerCase() == 'video';
    final canEdit = isMine &&
        messageId != null &&
        message.type == 'text' &&
        DateTime.now().difference(message.timestamp).inMinutes < 15;
    final canDelete = messageId != null;

    final items = reactionsOnly
        ? const <MessageMenuItem>[]
        : <MessageMenuItem>[
            if (isCall)
              MessageMenuItem(
                icon: callVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                label: callVideo ? 'Video Call Back' : 'Call Back',
                color: const Color(0xFF34C759),
                onTap: callVideo ? _startVideoCall : _startVoiceCall,
              ),
            MessageMenuItem(
                icon: Icons.reply_rounded,
                label: 'Reply',
                onTap: () => _beginReply(message)),
            MessageMenuItem(
                icon: Icons.shortcut_rounded,
                label: 'Forward',
                onTap: () => _enterSelectionMode(message)),
            MessageMenuItem(
              icon: Icons.copy_rounded,
              label: 'Copy',
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.content));
                AppToast.show('Message copied');
              },
            ),
            MessageMenuItem(
                icon: Icons.share_rounded,
                label: 'Share',
                onTap: () => _shareMessage(message)),
            MessageMenuItem(
                icon: Icons.info_outline_rounded,
                label: 'Info',
                onTap: () => _showMessageInfo(message)),
            MessageMenuItem(
              icon: message.reaction == 'star'
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              label: message.reaction == 'star' ? 'Unstar' : 'Star',
              color: message.reaction == 'star' ? Colors.amber : null,
              onTap: () =>
                  _reactToMessage(message, message.reaction == 'star' ? '' : 'star'),
            ),
            MessageMenuItem(
              icon: message.isSaved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              label: message.isSaved ? 'Unsave Message' : 'Save Message',
              color: message.isSaved ? AppTheme.primaryColor : null,
              onTap: () => _toggleSaveMessage(message),
            ),
            if (canEdit)
              MessageMenuItem(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: () => _beginEditingMessage(message)),
            if (canDelete)
              MessageMenuItem(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                color: Colors.redAccent,
                onTap: () {
                  _enterSelectionMode(message);
                  _deleteSelectedMessages();
                },
              ),
          ];

    setState(() => _hiddenMsgId = message.id); // hide the original bubble
    await MessageActionsOverlay.show(
      context,
      bubbleRect: rect,
      bubble: _overlayBubble(message, isMine),
      isMine: isMine,
      canReact: messageId != null,
      emojis: const ['👍', '❤️', '😂', '😮', '😢', '🙏', '👻'],
      currentReaction: message.reaction == 'star' ? null : message.reaction,
      items: items,
      onReact: (e) => _reactToMessage(message, e),
      onMoreReactions: () => _showMoreReactions(message),
    );
    if (mounted) setState(() => _hiddenMsgId = null);
  }

  Future<void> _showMoreReactions(ChatMessage message) async {
    const emojis = [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🙂',
      '😊',
      '😍',
      '🥰',
      '😘',
      '😎',
      '🤔',
      '😮',
      '😢',
      '😭',
      '😡',
      '👍',
      '👎',
      '👏',
      '🙌',
      '🙏',
      '❤️',
      '🔥',
      '🎉',
      '💯',
      '👻',
      '🤝',
      '💪',
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 310,
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: emojis.length,
            itemBuilder: (context, index) => InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.pop(sheetContext);
                _reactToMessage(message, emojis[index]);
              },
              child: Center(
                child: Text(
                  emojis[index],
                  style: const TextStyle(fontSize: 27),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMessageInfo(ChatMessage message) {
    MessageInfoPage.open(
      context,
      message: message,
      conversation: widget.conversation,
    );
  }

  Future<void> _reactToMessage(ChatMessage message, String emoji) async {
    final cleanEmoji = normalizeEmojiText(emoji);
    final messageId = int.tryParse(message.id);
    if (messageId == null) return;
    final saved = await ServerApiService.instance.reactMessageREST(
      messageId: messageId,
      chatReact: cleanEmoji,
    );
    if (!saved) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reaction could not be saved.')),
        );
      }
      return;
    }
    final newReaction = emoji.isEmpty ? null : emoji;
    final updated = ChatMessage(
      id: message.id,
      senderId: message.senderId,
      content: message.content,
      timestamp: message.timestamp,
      type: message.type,
      mediaUrl: message.mediaUrl,
      fileName: message.fileName,
      isRead: message.isRead,
      isEdited: message.isEdited,
      isDeleted: message.isDeleted,
      reaction: newReaction,
      replyToId: message.replyToId,
    );
    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((item) => item.id == message.id);
        if (index >= 0) _messages[index] = updated;
      });
    }
    await LocalChatStorage.instance.saveMessage(
      deviceId: widget.conversation.id,
      peerName: _chatName,
      message: updated,
      markUnread: false,
      peerUserId: widget.conversation.peerUserId,
    );
  }

  static const Map<int, String> _disappearingLabels = {
    0: 'off',
    1: '24 hours',
    2: '1 week',
    3: 'after read',
  };

  Future<void> _toggleSaveMessage(ChatMessage message) async {
    final messageId = int.tryParse(message.id);
    final chatId = int.tryParse(widget.conversation.id);
    if (messageId == null || chatId == null) return;

    final newIsSaved = !message.isSaved;
    final updatedMessage = message.copyWith(isSaved: newIsSaved);

    // Optimistic update in UI state
    setState(() {
      final index = _messages.indexWhere((m) => m.id == message.id);
      if (index >= 0) {
        _messages[index] = updatedMessage;
      }
    });

    // Save directly to local storage
    await LocalChatStorage.instance.saveMessage(
      deviceId: widget.conversation.id,
      peerName: widget.conversation.name,
      message: updatedMessage,
      markUnread: false,
    );

    final success = await ServerApiService.instance.saveMessageREST(
      chatId: chatId,
      messageId: messageId,
      isSaved: newIsSaved,
    );

    if (!success && mounted) {
      // Revert if API failed
      final reverted = message.copyWith(isSaved: !newIsSaved);
      setState(() {
        final index = _messages.indexWhere((m) => m.id == message.id);
        if (index >= 0) {
          _messages[index] = reverted;
        }
      });
      await LocalChatStorage.instance.saveMessage(
        deviceId: widget.conversation.id,
        peerName: widget.conversation.name,
        message: reverted,
        markUnread: false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update save status.')),
      );
    } else {
      await LocalChatStorage.instance.cacheMessages(
        widget.conversation.id,
        _messages,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newIsSaved ? 'Message saved' : 'Message unsaved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _changeDisappearingType(int newType) async {
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null) return;

    final result = await ServerApiService.instance.setDisappearingMessagesREST(
      chatId: chatId,
      disappearType: newType,
    );

    if (result != null && mounted) {
      final label = _disappearingLabels[newType] ?? 'off';
      setState(() {
        _disappearType = newType;
        _messages.removeWhere(
              (m) => isMessageExpired(
            m,
            chatDisappearType: newType,
            keepReadSessionMessages: true,
          ),
        );
      });
      await LocalChatStorage.instance.updateConversation(
        widget.conversation.id,
            (current) => current.copyWith(disappearType: newType),
      );
      await LocalChatStorage.instance.cacheMessages(
        widget.conversation.id,
        _messages,
        chatDisappearType: newType,
        keepReadSessionMessages: true,
      );
      if (mounted) {
        AppToast.show('Disappearing messages set to $label');
      }
    }
  }

  Future<void> _unblockCurrentPeer() async {
    final peerUserId = widget.conversation.peerUserId ?? int.tryParse(widget.conversation.id);
    if (peerUserId == null || peerUserId <= 0) return;

    final success = await ServerChatManager.instance.unblockUser(peerUserId);
    if (mounted) {
      if (success) {
        setState(() {
          _isBlocked = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User unblocked.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to unblock user.')),
        );
      }
    }
  }

  Future<void> _blockCurrentPeer() async {
    final peerUserId = widget.conversation.peerUserId ?? int.tryParse(widget.conversation.id);
    if (peerUserId == null || peerUserId <= 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block User'),
        content: Text('Are you sure you want to block $_chatName? They will not be able to send you messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Block', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await ServerChatManager.instance.blockUser(peerUserId);
    if (mounted) {
      if (success) {
        setState(() {
          _isBlocked = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to block user.')),
        );
      }
    }
  }

  Future<void> _confirmClearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'Are you sure you want to delete all messages in this chat? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear chat', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final chatId = int.tryParse(widget.conversation.id);
    if (chatId != null && chatId > 0) {
      await ServerApiService.instance.clearChatREST(chatId);
    }
    await LocalChatStorage.instance.clearChatMessages(widget.conversation.id);
    if (mounted) {
      setState(() {
        _messages = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat cleared.')),
      );
    }
  }

  Widget _buildBlockedBanner(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.paddingOf(context).bottom + 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.1),
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You have blocked this user.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _confirmClearChat,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.delete_sweep_outlined,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Clear Chat',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _unblockCurrentPeer,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_open_rounded,
                            size: 18,
                            color: AppTheme.primaryColor,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Unblock',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDisappearingMessagesPicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  'Disappearing Messages',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'When enabled, new messages sent in this chat will disappear after the selected duration.',
                  style: TextStyle(fontSize: 13, color: AppTheme.subtitleGrey),
                ),
              ),
              const SizedBox(height: 12),
              ..._disappearingLabels.entries.map((entry) {
                final typeKey = entry.key;
                final labelText = entry.value;
                final isSelected = _disappearType == typeKey;

                return ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(
                    typeKey == 0
                        ? Icons.timer_off_outlined
                        : Icons.timer_outlined,
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.subtitleGrey,
                  ),
                  title: Text(
                    labelText,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected ? AppTheme.primaryColor : null,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.primaryColor,
                  )
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _changeDisappearingType(typeKey);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<int?> _showDeleteMessagesBottomSheet({
    required int count,
    required bool canDeleteForEveryone,
  }) async {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        final sheetBg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
        final cardBg = isDark ? const Color(0xFF2C2C2E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black;
        final redColor = isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
        final closeBg = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);
        final closeIconColor = isDark ? Colors.white : Colors.black87;
        final dividerColor = isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA);

        final titleText = 'Delete $count ${count == 1 ? 'message' : 'messages'}?';

        return Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            math.max(20.0, MediaQuery.paddingOf(ctx).bottom + 16.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Text(
                      titleText,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, null),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: closeBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: closeIconColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canDeleteForEveryone) ...[
                      InkWell(
                        onTap: () => Navigator.pop(ctx, 1),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 20,
                          ),
                          child: Text(
                            'Delete for Everyone',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: redColor,
                            ),
                          ),
                        ),
                      ),
                      Divider(height: 1, thickness: 0.5, color: dividerColor),
                    ],
                    InkWell(
                      onTap: () => Navigator.pop(ctx, 2),
                      borderRadius: BorderRadius.circular(
                        canDeleteForEveryone ? 0 : 16,
                      ).copyWith(
                        bottomLeft: const Radius.circular(16),
                        bottomRight: const Radius.circular(16),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                        child: Text(
                          'Delete for Me',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: redColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteSelectedMessages() async {
    final selectedMsgs = _messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    if (selectedMsgs.isEmpty) return;

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(minutes: 15));
    final canDeleteForEveryone = selectedMsgs.every((m) {
      final messageId = int.tryParse(m.id);
      final isMine = m.senderId == 'user';
      final msgTime = m.timestamp.toLocal();
      final isRecent =
          msgTime.isAfter(cutoff) || now.difference(msgTime).inMinutes.abs() <= 15;
      final isSeen = m.isRead ||
          m.status.toLowerCase().trim() == 'read' ||
          m.messageStatus == MessageStatus.read;
      return messageId != null && isMine && isRecent && !isSeen && !m.isDeleted;
    });

    final deleteType = await _showDeleteMessagesBottomSheet(
      count: selectedMsgs.length,
      canDeleteForEveryone: canDeleteForEveryone,
    );

    if (deleteType == null || !mounted) {
      if (mounted) _exitSelectionMode();
      return;
    }

    final deviceId = widget.conversation.id;

    if (deleteType == 1) {
      // Delete for Everyone (type = 1)
      for (final msg in selectedMsgs) {
        final messageId = int.tryParse(msg.id);
        if (messageId == null) continue;

        final deleted = await ServerApiService.instance.deleteMessageREST(
          messageId,
          type: 1,
        );
        if (deleted) {
          SocketChatService.instance.deleteMessage(messageId: messageId, type: 1);
          final updated = msg.copyWith(
            content: 'This message was deleted',
            isDeleted: true,
          );
          if (mounted) {
            setState(() {
              final index = _messages.indexWhere((item) => item.id == msg.id);
              if (index >= 0) _messages[index] = updated;
              if (_editingMessage?.id == msg.id) _editingMessage = null;
            });
          }
          await LocalChatStorage.instance.saveMessage(
            deviceId: deviceId,
            peerName: _chatName,
            message: updated,
            markUnread: false,
            peerUserId: widget.conversation.peerUserId,
          );
        }
      }
    } else if (deleteType == 2) {
      // Delete for Me (type = 2)
      for (final msg in selectedMsgs) {
        final messageId = int.tryParse(msg.id);
        if (messageId != null) {
          unawaited(
            ServerApiService.instance.deleteMessageREST(messageId, type: 2),
          );
          SocketChatService.instance.deleteMessage(messageId: messageId, type: 2);
          await LocalChatStorage.instance.deleteLocalMessage(
            deviceId,
            msg.id,
          );
        }
      }
      if (mounted) {
        setState(() {
          _messages.removeWhere((item) => _selectedMessageIds.contains(item.id));
          if (_editingMessage != null &&
              _selectedMessageIds.contains(_editingMessage!.id)) {
            _editingMessage = null;
          }
        });
      }
    }

    if (mounted) _exitSelectionMode();
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    _enterSelectionMode(message);
    await _deleteSelectedMessages();
  }

  void _beginEditingMessage(ChatMessage message) {
    setState(() {
      _editingMessage = message;
      _replyingMessage = null;
      _inputController.text = message.content;
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
    });
    _inputFocusNode.requestFocus();
  }

  void _cancelEditingMessage() {
    setState(() {
      _editingMessage = null;
      _inputController.clear();
    });
  }

  Future<void> _saveEditedMessage() async {
    final message = _editingMessage;
    if (message == null || _isSending) return;
    final messageId = int.tryParse(message.id);
    if (messageId == null) return;
    final rawText = _inputController.text.trim();
    if (rawText.isEmpty) {
      _cancelEditingMessage();
      return;
    }
    final text = normalizeChatMessageText(rawText);
    if (text == message.content) {
      _cancelEditingMessage();
      return;
    }

    setState(() => _isSending = true);
    final encryptedText = E2eCryptoService.instance.encryptText(
      message.isForwarded ? addFwdMarker(text) : text,
      'chat_key_${widget.conversation.id}',
    );
    final saved = await ServerApiService.instance.editMessageREST(
      messageId: messageId,
      message: encryptedText,
    );
    if (!mounted) return;
    setState(() => _isSending = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message could not be edited.')),
      );
      return;
    }

    final updated = message.copyWith(content: text, isEdited: true);
    setState(() {
      final index = _messages.indexWhere((item) => item.id == message.id);
      if (index >= 0) _messages[index] = updated;
      _editingMessage = null;
      _inputController.clear();
    });
    await LocalChatStorage.instance.saveMessage(
      deviceId: widget.conversation.id,
      peerName: _chatName,
      message: updated,
      markUnread: false,
    );
  }

  Future<void> _sendMessage() async {
    if (_editingMessage != null) {
      if (!_isSending) await _saveEditedMessage();
      return;
    }
    final rawText = _inputController.text.trim();
    if (rawText.isEmpty) {
      _inputController.clear();
      return;
    }
    final text = normalizeChatMessageText(rawText);

    // Capture everything NOW; the input is cleared synchronously so rapid
    // taps can never double-send.
    final replyToId =
        _replyingMessage == null ? null : int.tryParse(_replyingMessage!.id);

    var ts = DateTime.now();
    if (_messages.isNotEmpty) {
      final latest = _messages
          .map((m) => m.timestamp)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (!ts.isAfter(latest)) ts = latest.add(const Duration(milliseconds: 10));
    }

    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}_${_textSeq++}';
    final optimistic = ChatMessage(
      id: localId,
      senderId: 'user',
      content: text,
      timestamp: ts,
      type: 'text',
      status: 'sending', // bubble shows the clock icon, like WhatsApp
      isRead: false,
      replyToId: replyToId,
    );

    _inputController.clear();
    unawaited(LocalChatStorage.instance.clearDraft(widget.conversation.id));
    setState(() {
      _messages = [..._messages, optimistic];
      _replyingMessage = null; // clear the reply bar immediately
    });
    _scrollToBottom();

    final numericId = int.tryParse(widget.conversation.id);
    if (numericId != null) {
      SocketChatService.instance.sendTyping(chatHeadId: numericId, isTyping: false);
    }

    // Strictly one-by-one, in the order the user pressed send.
    _textQueueTail = _textQueueTail
        .then((_) => _deliverText(localId: localId, text: text, replyToId: replyToId))
        .catchError((e) => debugPrint('[TEXT QUEUE] $e'));
  }

  Future<void> _deliverText({
    required String localId,
    required String text,
    int? replyToId,
  }) async {
    ChatMessage? sent;
    for (var attempt = 0; attempt < 3 && sent == null; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(milliseconds: 1500 * attempt));
      sent = await ServerChatManager.instance.sendMessage(
        chatId: widget.conversation.id,
        peerName: _chatName,
        text: text,
        peerUserId: widget.conversation.peerUserId,
        replyToId: replyToId,
      );
    }

    if (!mounted) return;

    if (sent == null) {
      _setMessageStatus(localId, 'failed');
      AppToast.show('Message not sent. Check your connection.', isError: true);
      return;
    }

    final real = sent;
    setState(() {
      _pendingLocalToRealIdMap[localId] = real.id;
      _matchedLocalIds.add(localId);
      // Only remove THIS message's local row (never other pending ones with
      // the same text, or "hi", "hi" would eat each other).
      _messages.removeWhere((m) =>
          m.id == localId ||
          m.id == real.id ||
          _pendingLocalToRealIdMap[m.id] == real.id);
      _messages.add(real);
      _adjustRemainingLocalMessageTimestamps(real.timestamp);
      _messages.sort(_compareChatMessages);
    });
  }

  void _showFailedActions(ChatMessage m) {
    if (m.mediaUrl != null && m.mediaUrl!.isNotEmpty) return;
    HapticFeedback.selectionClick();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Message not sent'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _retryText(m.id);
            },
            child: const Text('Retry'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _discardFailedText(m.id);
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _retryText(String id) {
    final i = _messages.indexWhere((m) => m.id == id);
    if (i < 0 || _messages[i].status.toLowerCase() != 'failed') return;
    final m = _messages[i];
    _setMessageStatus(id, 'sending'); // clock icon again
    _textQueueTail = _textQueueTail
        .then((_) => _deliverText(
              localId: id,
              text: m.content,
              replyToId: m.replyToId,
            ))
        .catchError((e) => debugPrint('[TEXT QUEUE] $e'));
  }

  void _discardFailedText(String id) {
    setState(() => _messages.removeWhere((m) => m.id == id));
  }

  Future<File> _stageForUpload(File src) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}chat_attachments');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safe = src.path.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return src.copy('${dir.path}${Platform.pathSeparator}out_${DateTime.now().microsecondsSinceEpoch}_$safe');
  }

  Future<void> _uploadAndSendAttachment({
    required File file,
    required String fileName,
    required String fileType,
    String? caption,
    bool isHd = false,
  }) async {
    try {
      var sendFile = file;
      var sendFileName = fileName;

      final staged = await _stageForUpload(sendFile);
      sendFile = staged;

      final isMedia = fileType.startsWith('image/') || fileType.startsWith('video/');
      if (isHd && isMedia && !sendFileName.startsWith('hd_')) {
        sendFileName = 'hd_$sendFileName';
      }

      final secretKey = 'chat_key_${widget.conversation.id}';
      final localMsgId =
          'local_upload_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';

      final messageText = (caption != null && caption.trim().isNotEmpty)
          ? caption.trim()
          : (fileType.startsWith('image/')
          ? 'Photo'
          : fileType.startsWith('video/')
          ? 'Video'
          : fileType.startsWith('audio/')
          ? 'Voice message'
          : sendFileName);

      final replyId = _replyingMessage == null
          ? null
          : int.tryParse(_replyingMessage!.id);

      final now = DateTime.now();
      var localTimestamp = (_lastAttachmentTimestamp != null &&
          !_lastAttachmentTimestamp!.isBefore(now))
          ? _lastAttachmentTimestamp!.add(const Duration(milliseconds: 10))
          : now;
      if (_messages.isNotEmpty) {
        final latestTs = _messages
            .map((m) => m.timestamp)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        if (!localTimestamp.isAfter(latestTs)) {
          localTimestamp = latestTs.add(const Duration(milliseconds: 10));
        }
      }
      _lastAttachmentTimestamp = localTimestamp;

      // Create optimistic pending message immediately
      final localMsg = ChatMessage(
        id: localMsgId,
        senderId: 'user',
        content: messageText,
        timestamp: localTimestamp,
        type: fileType,
        mediaUrl: sendFile.path,
        fileName: sendFileName,
        status: 'sending',
        isRead: false,
        isDelivered: false,
        replyToId: replyId,
      );

      // Save local pending message immediately
      await LocalChatStorage.instance.saveMessage(
        deviceId: widget.conversation.id,
        peerName: _chatName,
        message: localMsg,
        peerUserId: widget.conversation.peerUserId,
      );

      if (mounted) {
        setState(() {
          _messages.add(localMsg);
          _messages.sort(_compareChatMessages);
          _replyingMessage = null;
          _isSending = false;
        });
        _scrollToBottom();
      }

      // Ensure system picker active state is reset
      AppPreferences.isPickerActive = false;

      OutgoingAttachmentManager.instance.enqueue(OutgoingJob(
        localId: localMsgId,
        chatId: widget.conversation.id,
        peerName: _chatName,
        peerUserId: widget.conversation.peerUserId,
        file: sendFile,
        fileName: sendFileName,
        fileType: fileType,
        messageText: messageText,
        secretKey: secretKey,
        localTimestamp: localTimestamp,
        replyToId: replyId,
        isHd: isHd,
      ));
    } catch (error) {
      debugPrint('[ATTACHMENT DISPATCH ERROR] $error');
      if (mounted) {
        AppToast.show(
          AppToast.userFriendlyMessage('Unable to queue attachment: $error'),
          isError: true,
        );
      }
    }
  }

  void _setMessageStatus(String id, String status) {
    if (!mounted) return;
    final i = _messages.indexWhere((m) => m.id == id);
    if (i < 0) return;
    setState(() => _messages[i] = _messages[i].copyWith(status: status));
  }

  void _recoverOrphanedUploads() {
    final mgr = OutgoingAttachmentManager.instance;
    // finished in the background while this page was closed -> drop the stale local row
    _messages.removeWhere((m) =>
        m.id.startsWith('local_upload_') && mgr.realIdFor(m.id) != null);

    for (final m in List<ChatMessage>.of(_messages)) {
      if (!m.id.startsWith('local_upload_')) continue;
      if (mgr.isActive(m.id)) continue;          // still uploading: leave it alone
      final path = m.mediaUrl;
      mgr.adopt(OutgoingJob(
        localId: m.id,
        chatId: widget.conversation.id,
        peerName: _chatName,
        peerUserId: widget.conversation.peerUserId,
        file: File(path ?? ''),
        fileName: m.fileName ?? (path ?? '').split(RegExp(r'[/\\]')).last,
        fileType: m.type,
        messageText: m.content,
        secretKey: 'chat_key_${widget.conversation.id}',
        localTimestamp: m.timestamp,
        replyToId: m.replyToId,
      ));
      _setMessageStatus(m.id, 'failed');
    }
  }

  Future<void> _sendSticker(StickerItem sticker) async {
    final sentMsg = await ServerChatManager.instance.sendMessage(
      chatId: widget.conversation.id,
      peerName: _chatName,
      text: sticker.id,
      fileType: 'sticker',
      filePath: sticker.id,
      peerUserId: widget.conversation.peerUserId,
    );
    if (sentMsg != null) {
      if (mounted) {
        setState(() {
          _messages.add(sentMsg);
          _messages.sort(_compareChatMessages);
        });
        _scrollToBottom();
      }
    }
  }

  void _sendGif(GifItem gif) {
    _gifQueueTail = _gifQueueTail
        .then((_) => _sendGifNow(gif))
        .catchError((e) => debugPrint('[GIF QUEUE] $e'));
  }

  Future<void> _sendGifNow(GifItem gif) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${docsDir.path}${Platform.pathSeparator}chat_attachments');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeId = gif.id.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final name = 'gif_${safeId}_${DateTime.now().microsecondsSinceEpoch}.gif';
      final file = File('${dir.path}${Platform.pathSeparator}$name');

      final res = await http.get(Uri.parse(gif.gifUrl)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        await file.writeAsBytes(res.bodyBytes);
        await _uploadAndSendAttachment(
          file: file,
          fileName: name,
          fileType: 'image/gif',
          caption: 'GIF',
        );
        return;
      }
    } catch (e) {
      debugPrint('[SEND GIF FILE ERROR] $e');
    }

    // fallback: send the link
    final sent = await ServerChatManager.instance.sendMessage(
      chatId: widget.conversation.id,
      peerName: _chatName,
      text: gif.gifUrl,
      fileType: 'image/gif',
      filePath: gif.gifUrl,
      peerUserId: widget.conversation.peerUserId,
    );
    if (sent != null && mounted) {
      setState(() {
        _messages.add(sent);
        _messages.sort(_compareChatMessages);
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startVoiceCall() {
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null) return;
    try {
      CallService.instance.startCall(
        chatHeadId: chatId,
        type: CallType.voice,
        name: _chatName,
        avatar: _chatAvatar,
        peerUserId: widget.conversation.peerUserId,
      ).catchError((e) {
        if (mounted) {
          AppToast.show(AppToast.userFriendlyMessage('$e'), isError: true);
        }
      });
    } catch (e) {
      AppToast.show(AppToast.userFriendlyMessage('$e'), isError: true);
    }
  }

  void _startVideoCall() {
    final chatId = int.tryParse(widget.conversation.id);
    if (chatId == null) return;
    try {
      CallService.instance.startCall(
        chatHeadId: chatId,
        type: CallType.video,
        name: _chatName,
        avatar: _chatAvatar,
        peerUserId: widget.conversation.peerUserId,
      ).catchError((e) {
        if (mounted) {
          AppToast.show(AppToast.userFriendlyMessage('$e'), isError: true);
        }
      });
    } catch (e) {
      AppToast.show(AppToast.userFriendlyMessage('$e'), isError: true);
    }
  }

  Future<void> _openChatInfo() async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => ChatInfoPage(conversation: widget.conversation),
      ),
    );
    if (!mounted) return;
    await _syncChatDetails();
    await _showCachedMessages();
    if (result == true) {
      setState(() {
        _historyLoadGeneration++;
        _isLoadingMessages = false;
        _historyError = null;
        _messages.clear();
        _messagesReceivedWhileLoading.clear();
      });
      AppToast.show('Chat cleared.');
    } else if (result is String) {
      final msgId = int.tryParse(result);
      if (msgId != null) {
        _scrollToMessage(msgId);
      }
    }
  }

  void _jumpToLatest() {
    _newMessagesWhileAway = 0;
    _scrollToBottom();
  }

  double get _topInset {
    final safeTop = MediaQuery.paddingOf(context).top;
    const headerHeight = 56.0;
    final searchHeight = _isSearchingMessages ? 56.0 : 0.0;
    return safeTop + headerHeight + searchHeight + 12.0;
  }

  double get _bottomInset {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final composerSpace =
        _composerCtl.bottomSpace.value ?? _composerHeight.value;
    final baseBottom = math.max(composerSpace, kb > 0 ? kb + 54.0 : 0.0);
    return baseBottom + 8.0;
  }

  String? _highlightedMessageId;
  Timer? _highlightTimer;

  String? get _effectiveHighlightedMessageId {
    if (_isSearchingMessages &&
        _searchResults.isNotEmpty &&
        _currentSearchIndex >= 0 &&
        _currentSearchIndex < _searchResults.length) {
      return _searchResults[_currentSearchIndex].id;
    }
    return _highlightedMessageId;
  }

  void _scrollToMessage(int replyToId) =>
      _scrollToMessageId(replyToId.toString());

  Future<void> _scrollToMessageId(String targetId) async {
    // 1. Ensure message is loaded in memory
    if (!_messages.any((m) => m.id == targetId)) {
      AppToast.show('Finding message…');
      int pagesLoaded = 0;
      while (!_messages.any((m) => m.id == targetId) &&
          _hasMorePages &&
          pagesLoaded < 10) {
        pagesLoaded++;
        await _loadOlderMessages();
      }
    }

    final index = _messages.indexWhere((m) => m.id == targetId);
    if (index < 0) {
      AppToast.show('Original message not found in history.');
      return;
    }
    if (!_scrollController.hasClients) return;

    // 2. Attach target key
    setState(() {
      _scrollTargetId = targetId;
    });

    // 3. Coarse Jump
    final reversedIndex = (_messages.length - 1) - index;
    final viewportHeight = _scrollController.position.viewportDimension;
    final T = _topInset;
    final B = _bottomInset;
    final visibleCenter = (viewportHeight + B - T) / 2;
    final centeredOffset = (reversedIndex * 78.0) - visibleCenter + 39.0;
    final targetOffset = centeredOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(targetOffset);

    // 4. Retry until built & context exists
    int retry = 0;
    while (_scrollTargetKey.currentContext == null && retry < 20) {
      retry++;
      await WidgetsBinding.instance.endOfFrame;
      if (_scrollTargetKey.currentContext != null) break;
      final currentOffset = _scrollController.offset;
      final nudge = (currentOffset + (targetOffset - currentOffset) * 0.5)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(nudge);
      await Future.delayed(const Duration(milliseconds: 16));
    }

    // 5. Animate to exact position using Scrollable.ensureVisible
    if (_scrollTargetKey.currentContext != null) {
      final box =
      _scrollTargetKey.currentContext!.findRenderObject() as RenderBox?;
      final H = box?.size.height ?? 60.0;
      final V = _scrollController.position.viewportDimension;
      final T = _topInset;
      final B = _bottomInset;
      final visibleArea = V - T - B;

      double alignment;
      if (H >= visibleArea) {
        alignment = (V - T - H) / (V - H);
      } else {
        alignment = (V + B - T - H) / (2 * (V - H));
      }
      alignment = alignment.clamp(0.0, 1.0);

      await Scrollable.ensureVisible(
        _scrollTargetKey.currentContext!,
        alignment: alignment,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );

      // 6. Correct post-animation for images or layout shifts
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted && _scrollTargetKey.currentContext != null) {
        await Scrollable.ensureVisible(
          _scrollTargetKey.currentContext!,
          alignment: alignment,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
        );
      }
    }

    // 7. Highlight & store pending ID for keyboard metrics change
    _highlightTimer?.cancel();
    setState(() {
      _highlightedMessageId = targetId;
      _pendingScrollTargetId = targetId;
    });
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  bool _isSearchingMessages = false;
  final TextEditingController _messageSearchController =
  TextEditingController();
  final FocusNode _messageSearchFocusNode = FocusNode();
  List<ChatMessage> _searchResults = [];
  int _currentSearchIndex = -1;
  int _searchGeneration = 0;

  void _toggleMessageSearch() {
    setState(() {
      _isSearchingMessages = !_isSearchingMessages;
      if (!_isSearchingMessages) {
        _searchGeneration++;
        _messageSearchController.clear();
        _searchResults = [];
        _currentSearchIndex = -1;
        _messageSearchFocusNode.unfocus();
      } else {
        _messageSearchFocusNode.requestFocus();
      }
    });
  }

  void _onSearchQueryChanged(String query) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final generation = ++_searchGeneration;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _currentSearchIndex = -1;
      });
      return;
    }

    final cached = await _loadPlainCachedMessages();
    if (!mounted || generation != _searchGeneration) return;

    final allMessagesById = <String, ChatMessage>{
      for (final message in cached) message.id: message,
      for (final message in _messages) message.id: message,
    };
    final allMessages = allMessagesById.values.toList()
      ..sort(_compareChatMessages);
    final results = allMessages.where((m) {
      if (m.isDeleted) return false;

      final type = m.type.toLowerCase();
      if (type.startsWith('image') ||
          type.startsWith('video') ||
          type.startsWith('audio') ||
          (m.mediaUrl != null && m.mediaUrl!.isNotEmpty)) {
        return false;
      }

      final text = m.content.trim();
      if (text.isEmpty ||
          text == '[Attachment]' ||
          text == 'Photo' ||
          text == 'Video') {
        return false;
      }

      return text.toLowerCase().contains(q);
    }).toList();

    // Reverse results so index 0 is the newest match (WhatsApp style)
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    setState(() {
      _searchResults = results;
      if (results.isNotEmpty) {
        _currentSearchIndex = 0;
        _messages = allMessages;
      } else {
        _currentSearchIndex = -1;
      }
    });
    if (results.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _searchGeneration) {
          _scrollToMessageId(results.first.id);
        }
      });
    }
  }

  void _navigateSearchResult(int direction) {
    if (_searchResults.isEmpty) return;
    int nextIndex = _currentSearchIndex + direction;
    if (nextIndex < 0) nextIndex = _searchResults.length - 1;
    if (nextIndex >= _searchResults.length) nextIndex = 0;

    setState(() {
      _currentSearchIndex = nextIndex;
    });
    _scrollToMessageId(_searchResults[nextIndex].id);
  }

  Widget _buildInChatSearchBanner(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF2C2C2E).withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.glassBorder(isDark),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.search,
                  size: 18,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageSearchController,
                    focusNode: _messageSearchFocusNode,
                    onChanged: _onSearchQueryChanged,
                    onTapOutside: (_) => _messageSearchFocusNode.unfocus(),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.search,
                    keyboardType: TextInputType.text,
                    onSubmitted: (_) => _messageSearchFocusNode.unfocus(),
                    autocorrect: true,
                    enableSuggestions: true,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppTheme.primaryText(isDark),
                      letterSpacing: -0.2,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search in chat…',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintStyle: TextStyle(
                        color: AppTheme.secondaryText(isDark),
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
                if (_messageSearchController.text.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _searchResults.isEmpty
                          ? (isDark ? Colors.white12 : Colors.black12)
                          : AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _searchResults.isEmpty
                          ? '0 matches'
                          : '${_currentSearchIndex + 1} of ${_searchResults.length}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _searchResults.isEmpty
                            ? AppTheme.secondaryText(isDark)
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _searchResults.isEmpty
                        ? null
                        : () => _navigateSearchResult(1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        CupertinoIcons.chevron_up,
                        size: 18,
                        color: _searchResults.isEmpty
                            ? AppTheme.secondaryText(isDark)
                            .withValues(alpha: 0.4)
                            : AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _searchResults.isEmpty
                        ? null
                        : () => _navigateSearchResult(-1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        CupertinoIcons.chevron_down,
                        size: 18,
                        color: _searchResults.isEmpty
                            ? AppTheme.secondaryText(isDark)
                            .withValues(alpha: 0.4)
                            : AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _toggleMessageSearch,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      CupertinoIcons.xmark_circle_fill,
                      size: 18,
                      color: AppTheme.secondaryText(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _purgeSeenMessagesOnExit() async {
    if (_didPurgeSeenMessagesOnExit) return;
    _didPurgeSeenMessagesOnExit = true;
    // 1. Send markChatRead API call to server when exiting chat screen
    try {
      await ServerChatManager.instance.markChatRead(widget.conversation.id);
    } catch (e) {
      debugPrint('[CHAT] Error marking chat read on exit: $e');
    }

    // 2. Mark unread messages as read in memory and filter out expired messages
    final type = _disappearType;
    final updatedMessages = <ChatMessage>[];
    for (final m in _messages) {
      final updated = m.senderId != 'user' && !m.isRead
          ? m.copyWith(isRead: true)
          : m;
      if (!isMessageExpired(
        updated,
        chatDisappearType: type,
        keepReadSessionMessages: false,
      )) {
        updatedMessages.add(updated);
      }
    }

    _messages = updatedMessages;

    // 3. Cache updated active messages to local storage and update conversation unread count
    try {
      final mgr = OutgoingAttachmentManager.instance;
      final stored = await LocalChatStorage.instance
          .loadMessages(widget.conversation.id, keepReadSessionMessages: true);
      final byId = {for (final m in stored) m.id: m};
      for (final m in _messages) {
        if (m.id.startsWith('local_upload_') && mgr.realIdFor(m.id) != null) continue;
        byId[m.id] = m;
      }
      final merged = byId.values.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      await LocalChatStorage.instance.cacheMessages(
        widget.conversation.id,
        merged,
      );
      await LocalChatStorage.instance.updateConversation(
        widget.conversation.id,
            (conv) => conv.copyWith(
          unreadCount: 0,
          messages: merged,
          lastMessage: merged.isNotEmpty
              ? merged.last.previewText
              : 'No messages yet',
        ),
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_markChatRead());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_purgeSeenMessagesOnExit());
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (_pendingScrollTargetId != null) {
      _metricsDebounceTimer?.cancel();
      _metricsDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted && _pendingScrollTargetId != null) {
          _recenterPendingScrollTarget();
        }
      });
    }
  }

  Future<void> _recenterPendingScrollTarget() async {
    final targetId = _pendingScrollTargetId ??
        (_isSearchingMessages &&
                _searchResults.isNotEmpty &&
                _currentSearchIndex >= 0 &&
                _currentSearchIndex < _searchResults.length
            ? _searchResults[_currentSearchIndex].id
            : null);
    if (targetId == null) return;
    if (_scrollTargetKey.currentContext != null) {
      final box = _scrollTargetKey.currentContext!.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final H = box.size.height;
        final V = _scrollController.position.viewportDimension;
        final T = _topInset;
        final B = _bottomInset;
        final visibleArea = V - T - B;

        double alignment;
        if (H >= visibleArea) {
          alignment = (V - T - H) / (V - H);
        } else {
          alignment = (V + B - T - H) / (2 * (V - H));
        }
        alignment = alignment.clamp(0.0, 1.0);

        await Scrollable.ensureVisible(
          _scrollTargetKey.currentContext!,
          alignment: alignment,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    }
    _pendingScrollTargetId = null;
  }

  @override
  void dispose() {
    ChatAudioPlayback.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounceTimer?.cancel();
    _metricsDebounceTimer?.cancel();
    _composerHeight.dispose();
    _inputController.removeListener(_onInputTextChanged);
    LocalChatStorage.instance.saveDraft(
      widget.conversation.id,
      _inputController.text,
    );
    _purgeSeenMessagesOnExit();
    _messageSearchController.dispose();
    _messageSearchFocusNode.dispose();
    _highlightTimer?.cancel();
    if (ServerChatManager.instance.activeChatId == widget.conversation.id) {
      ServerChatManager.instance.activeChatId = null;
    }
    _outSub?.cancel();
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _presenceSubscription?.cancel();
    _readSubscription?.cancel();
    _deliveredSubscription?.cancel();
    _editedSubscription?.cancel();
    _deletedSubscription?.cancel();
    _reactionSubscription?.cancel();
    _peerTypingTimer?.cancel();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _isPeerOnline.dispose();
    _isPeerTyping.dispose();
    _mediaCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    _mediaCtl.chatName = _chatName;
    _mediaCtl.attach(_messages);

    return PopScope(
      canPop: !_composerCtl.isPanelOpen.value,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _composerCtl.closePanels();
          return;
        }
        FocusManager.instance.primaryFocus?.unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        _purgeSeenMessagesOnExit();
      },

      child: ChatMediaScope(
        controller: _mediaCtl,
        child: ShakePanicWrapper(
          child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: AppTheme.chatCanvas(isDark),
          body: ValueListenableBuilder<String>(
            valueListenable: AppPreferences.chatWallpaperNotifier,
            builder: (context, _, __) {
              return ValueListenableBuilder<int>(
                valueListenable: AppPreferences.chatBubbleColorNotifier,
                builder: (context, _, __) {
                  return ValueListenableBuilder<List<ChatConversation>>(
                    valueListenable: LocalChatStorage.instance.conversationsNotifier,
                    builder: (context, conversations, _) {
                      final liveConv = conversations.cast<ChatConversation?>().firstWhere(
                            (c) => c?.id == widget.conversation.id,
                        orElse: () => null,
                      );
                      return Stack(
                        children: [
                          // Background Wallpaper Layer
                          Positioned.fill(
                            child: ChatWallpaperWidget(
                              chatId: widget.conversation.id,
                              isDark: isDark,
                              backgroundUrl: widget.conversation.backgroundUrl,
                            ),
                          ),
                          // Messages List (paints full screen behind header and composer)
                          Positioned.fill(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _isPeerTyping,
                              builder: (context, isTyping, _) {
                                return ListenableBuilder(
                                  listenable: Listenable.merge([_composerHeight, _composerCtl.bottomSpace]),
                                  builder: (context, _) {
                                    final kb = MediaQuery.viewInsetsOf(context).bottom;
                                    final composerSpace = _composerCtl.bottomSpace.value ?? _composerHeight.value;
                                    final composerH = math.max(composerSpace, kb > 0 ? kb + 54.0 : 0.0);
                                    return ChatMessageList(
                                      messages: _messages,
                                      hiddenMessageId: _hiddenMsgId,
                                      isLoadingMessages: _isLoadingMessages,
                                      isLoadingMore: _isLoadingMore,
                                      isPeerTyping: isTyping,
                                      showJumpToLatest: _showJumpToLatest,
                                      newMessagesWhileAway: _newMessagesWhileAway,
                                      historyError: _historyError,
                                      scrollController: _scrollController,
                                      conversation: widget.conversation,
                                      groupMemberNames: _groupMemberNames,
                                      chatName: _chatName,
                                      chatAvatar: _chatAvatar,
                                      onShowMessageActions: _showMessageActions,
                                      onShowMessageInfo: _showMessageInfo,
                                      onBeginReply: _beginReply,
                                      onForwardMessage: _forwardSingleMessage,
                                      onReactMessage: _reactSingleMessage,
                                      onToggleStarMessage: _toggleStarSingleMessage,
                                      onDeleteMessage: _deleteSingleMessage,
                                      onTapReply: _scrollToMessage,
                                      highlightedMessageId: _effectiveHighlightedMessageId,
                                      searchQuery: _isSearchingMessages
                                          ? _messageSearchController.text.trim()
                                          : null,
                                      decryptingMessageIds: _decryptingEditedMessageIds,
                                      onJumpToLatest: _jumpToLatest,
                                      onReloadMessages: _reloadMessages,
                                      sessionStartTime: _sessionStartTime,
                                      initialUnreadCount: _initialUnreadCount,
                                      isSelectionMode: _isSelectionMode,
                                      selectedMessageIds: _selectedMessageIds,
                                      onToggleSelectMessage: _toggleSelectMessage,
                                      onVoiceCallTap: _startVoiceCall,
                                      onVideoCallTap: _startVideoCall,
                                      onFailedTap: _showFailedActions,
                                      topInset: _topInset,
                                      bottomInset: composerH + 8.0,
                                      scrollTargetId: _scrollTargetId,
                                      scrollTargetKey: _scrollTargetKey,
                                    );
                                  },
                                );
                              },
                            ),
                          ),

                          // Floating Frosted Header / Selection Header
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _isSelectionMode
                                ? _buildSelectionHeader(isDark)
                                : ChatDetailHeader(
                              conversation: widget.conversation,
                              chatName: _chatName,
                              chatAvatar: _chatAvatar,
                              isPeerOnline: _isPeerOnline,
                              isPeerTyping: _isPeerTyping,
                              isBlocked: _isBlocked || (liveConv?.isBlocked == true),
                              onBlockTap: _blockCurrentPeer,
                              onUnblockTap: _unblockCurrentPeer,
                              onOpenChatInfo: _openChatInfo,
                              onSearchMessages: _toggleMessageSearch,
                              onVoiceCallTap: _startVoiceCall,
                              onVideoCallTap: _startVideoCall,
                            ),
                          ),

                          if (_disappearType != 0 && !_isSearchingMessages)
                            Positioned(
                              top: MediaQuery.paddingOf(context).top + 64.0,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: GestureDetector(
                                  onTap: _showDisappearingMessagesPicker,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (isDark
                                          ? const Color(0xFF2C2C2E)
                                          : Colors.white)
                                          .withValues(alpha: 0.90),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppTheme.glassBorder(isDark),
                                        width: 0.8,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.1,
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
                                          CupertinoIcons.timer,
                                          size: 13,
                                          color: AppTheme.primaryColor,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Disappearing messages: ${_disappearingLabels[_disappearType] ?? ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.primaryText(isDark),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          if (_isSearchingMessages)
                            Positioned(
                              top: MediaQuery.paddingOf(context).top + 62.0,
                              left: 12,
                              right: 12,
                              child: _buildInChatSearchBanner(isDark),
                            ),

                          // Bottom Input Bar Composer / Selection Action Bar
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _MeasureSize(
                              onChange: (size) {
                                if (_composerHeight.value != size.height) {
                                  _composerHeight.value = size.height;
                                }
                              },
                              child: _isSelectionMode
                                  ? _buildSelectionBottomBar(isDark)
                                  : ((_isBlocked || (liveConv?.isBlocked == true))
                                  ? _buildBlockedBanner(isDark)
                                  : ChatComposer(
                                inputController: _inputController,
                                inputFocusNode: _inputFocusNode,
                                editingMessage: _editingMessage,
                                replyingMessage: _replyingMessage,
                                conversation: widget.conversation.copyWith(
                                  disappearType: _disappearType,
                                ),
                                chatName: _chatName,
                                groupMemberNames: _groupMemberNames,
                                isSending: _isSending,
                                onCancelEditing: _cancelEditingMessage,
                                onCancelReply: _cancelReply,
                                onTypingChanged: _onTypingChanged,
                                onSendText: _sendMessage,
                                onSendAttachment: _uploadAndSendAttachment,
                                onSendSticker: _sendSticker,
                                onSendGif: _sendGif,
                                onDisappearingTap: _showDisappearingMessagesPicker,
                                controller: _composerCtl,
                              )),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

typedef _OnWidgetSizeChange = void Function(Size size);

class _MeasureSize extends SingleChildRenderObjectWidget {
  final _OnWidgetSizeChange onChange;

  const _MeasureSize({
    required this.onChange,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasureSize(onChange);
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderMeasureSize renderObject) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _OnWidgetSizeChange onChange;
  Size? _oldSize;

  _RenderMeasureSize(this.onChange);

  @override
  void performLayout() {
    super.performLayout();
    final newSize = size;
    if (_oldSize != newSize) {
      _oldSize = newSize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChange(newSize);
      });
    }
  }
}
