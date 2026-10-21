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
import '../../domain/services/e2e_crypto_service.dart';
import '../../domain/services/local_chat_storage.dart';
import '../../domain/services/server_api_service.dart';
import '../../domain/services/server_chat_manager.dart';
import '../../domain/services/socket_chat_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_detail_header.dart';
import '../widgets/chat_message_list.dart';
import '../widgets/chat_typing_indicator.dart';
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
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, String> _groupMemberNames = {};
  final Set<String> _decryptingEditedMessageIds = <String>{};
  bool _showJumpToLatest = false;
  int _newMessagesWhileAway = 0;
  final ValueNotifier<bool> _isPeerTyping = ValueNotifier(false);
  final ValueNotifier<bool> _isPeerOnline = ValueNotifier(false);
  Timer? _peerTypingTimer;
  StreamSubscription<ServerMessageModel>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;
  StreamSubscription<Map<String, dynamic>>? _presenceSubscription;
  StreamSubscription<Map<String, dynamic>>? _readSubscription;
  StreamSubscription<Map<String, dynamic>>? _editedSubscription;
  StreamSubscription<Map<String, dynamic>>? _deletedSubscription;
  StreamSubscription<Map<String, dynamic>>? _reactionSubscription;

  late int _disappearType;
  late final int _initialUnreadCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _disappearType = widget.conversation.disappearType;
    _initialUnreadCount = widget.conversation.unreadCount;
    ServerChatManager.instance.activeChatId = widget.conversation.id;
    _chatName = widget.conversation.name;
    _chatAvatar = widget.conversation.avatarUrl;
    _isPeerOnline.value = widget.conversation.isOnline;
    _groupMemberNames.addAll(widget.conversation.memberNames);
    _scrollController.addListener(_handleScrollChanged);
    _messages = List.from(widget.conversation.messages);
    unawaited(_warmAttachmentCache());
    if (widget.conversation.isGroup) unawaited(_loadGroupMemberNames());
    unawaited(_resolvePeerProfileIfNeeded());
    _loadInitialMessages();
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
    _editedSubscription = SocketChatService.instance.onMessageEdited.listen(
      _handleEditedMessage,
    );
    _deletedSubscription = SocketChatService.instance.onMessageDeleted.listen(
      _handleDeletedMessage,
    );
    _reactionSubscription = SocketChatService.instance.onMessageReaction.listen(
      _handleReactionMessage,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _markChatRead();
      }
    });
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
          _isPeerOnline.value = peer.isOnline;
          final peerLastSeen = peer.lastSeenAt != null
              ? DateTime.tryParse(peer.lastSeenAt!)?.toLocal()
              : null;
          unawaited(
            LocalChatStorage.instance.updateConversation(
              widget.conversation.id,
              (c) => c.copyWith(
                isOnline: peer.isOnline,
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

    // Minimize keyboard if open when user scrolls/drags chat list
    if (_inputFocusNode.hasFocus &&
        _scrollController.position.userScrollDirection !=
            ScrollDirection.idle) {
      _inputFocusNode.unfocus();
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

  void _handleIncomingMessage(ServerMessageModel serverMessage) {
    if (!mounted ||
        serverMessage.chatHeadId.toString() != widget.conversation.id) {
      return;
    }
    final wasNearLatest =
        !_scrollController.hasClients ||
        _scrollController.position.pixels < 180;
    final currentUserId = ServerApiService.instance.currentUserId;
    final plaintext = serverMessage.decryptedContent(
      'chat_key_${serverMessage.chatHeadId}',
    );
    DateTime timestamp;
    try {
      timestamp = DateTime.parse(serverMessage.createdAt).toLocal();
    } catch (_) {
      timestamp = DateTime.now();
    }
    final incoming = ChatMessage(
      id: serverMessage.id.toString(),
      senderId: serverMessage.senderId == currentUserId
          ? 'user'
          : serverMessage.senderId.toString(),
      content: serverMessage.isDeleted ? 'This message was deleted' : plaintext,
      timestamp: timestamp,
      type:
          inferAttachmentType(
            fileType: serverMessage.fileType,
            fileName: serverMessage.fileName,
            filePath: serverMessage.filePath,
          ) ??
          (serverMessage.filePath != null &&
                  serverMessage.filePath!.trim().isNotEmpty
              ? 'application/octet-stream'
              : 'text'),
      mediaUrl: (serverMessage.filePath != null &&
              serverMessage.filePath!.trim().isNotEmpty)
          ? serverMessage.filePath
          : null,
      fileName: (serverMessage.fileName != null &&
              serverMessage.fileName!.trim().isNotEmpty)
          ? serverMessage.fileName
          : null,
      isRead: true,
      isEdited: serverMessage.isEdited,
      isDeleted: serverMessage.isDeleted,
      reaction: serverMessage.chatReact,
      replyToId: serverMessage.replyToId,
    );
    if (_isLoadingMessages) {
      _messagesReceivedWhileLoading[incoming.id] = incoming;
    }

    // Check if message is already present by ID or matches optimistic/existing local message
    final existingIndex = _messages.indexWhere(
      (message) =>
          message.id == incoming.id ||
          (message.id.startsWith('local_') &&
              incoming.senderId == 'user' &&
              message.content == incoming.content) ||
          (incoming.senderId == 'user' &&
              message.senderId == 'user' &&
              message.content == incoming.content &&
              incoming.timestamp
                      .difference(message.timestamp)
                      .inSeconds
                      .abs() <=
                  5),
    );

    if (existingIndex >= 0) {
      setState(() {
        _messages[existingIndex] = incoming;
        _messages.sort(_compareChatMessages);
      });
      if (wasNearLatest || incoming.senderId == 'user') _scrollToBottom();
      return;
    }

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
      }
    }
  }

  void _handlePresenceEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : event;

    final directPeerId = widget.conversation.peerUserId ??
        (widget.conversation.isGroup ? null : int.tryParse(widget.conversation.id));

    final userId = int.tryParse(
      (data['user_id'] ?? data['userId'] ?? data['id'])?.toString() ?? '',
    );
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
                    : (parsedLastSeen ?? c.lastSeenAt ?? DateTime.now()),
          ),
        ),
      );
    }
  }

  void _handleReadEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final eventChatId =
        (data['chat_head_id'] ??
                data['chat_id'] ??
                data['chatHeadId'] ??
                data['chatId'])
            ?.toString();
    final readerId = int.tryParse(
      (data['user_id'] ?? data['userId'] ?? data['reader_id'] ?? '').toString(),
    );
    final currentUserId = ServerApiService.instance.currentUserId;
    if (eventChatId != widget.conversation.id ||
        currentUserId == null ||
        (readerId != null && readerId == currentUserId)) {
      return;
    }

    final lastReadAt = DateTime.tryParse(
      (data['last_read_at'] ?? data['lastReadAt'] ?? '').toString(),
    );
    var changed = false;
    final updatedMessages = _messages.map((message) {
      final isReadByPeer =
          lastReadAt == null || !message.timestamp.isAfter(lastReadAt);
      if (message.senderId == 'user' && isReadByPeer && !message.isRead) {
        changed = true;
        return message.copyWith(isRead: true, isDelivered: true);
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

      final mergedById = <String, ChatMessage>{
        for (final m in _messages) m.id: m,
      };
      for (final message in filtered) {
        mergedById[message.id] = message;
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
      _messagesReceivedWhileLoading.clear();
      _scrollToBottom();
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
    final messagesById = <String, ChatMessage>{
      for (final message in _messages) message.id: message,
      for (final message in cached) message.id: message,
    };
    final messages = messagesById.values.toList()..sort(_compareChatMessages);
    setState(() => _messages = messages);
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
    final messageId = (data['id'] ?? data['message_id'])?.toString();
    if (messageId == null || !mounted) return;
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    setState(() {
      _messages[index] = _messages[index].copyWith(
        content: 'This message was deleted',
        isDeleted: true,
      );
    });
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
    ).then((_) {
      if (mounted) _exitSelectionMode();
    });
  }

  Widget _buildSelectionHeader(bool isDark) {
    final topPadding = MediaQuery.paddingOf(context).top;
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
            '${_selectedMessageIds.length} Selected',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const Spacer(),
          if (_selectedMessageIds.isNotEmpty)
            GlassButton(
              height: 36,
              radius: 18,
              isDark: isDark,
              onTap: _openForwardDialog,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shortcut_rounded,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Forward',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
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

  Future<void> _showMessageActions(
    ChatMessage message,
    Offset globalPosition,
    Size bubbleSize,
  ) async {
    if (message.isDeleted) return;
    final messageId = int.tryParse(message.id);
    final isMine = message.senderId == 'user';
    final screen = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);

    final minutesSinceSent = DateTime.now()
        .difference(message.timestamp)
        .inMinutes;
    final isExpired = minutesSinceSent >= 15;
    final canEdit =
        isMine && messageId != null && message.type == 'text' && !isExpired;
    final canDelete =
        isMine && messageId != null && !message.isRead && !isExpired;

    const emojiHeight = 50.0;
    const menuWidth = 220.0;
    final totalRows = 4 + (canEdit ? 1 : 0) + (canDelete ? 1 : 0);
    final menuHeight = totalRows * 46.0 + 10;

    final minTop = safePadding.top + 60.0;
    final maxBottom = screen.height - safePadding.bottom - 16.0;

    final bubbleHeight = math.max(40.0, bubbleSize.height);

    double targetBubbleTop = globalPosition.dy;

    if (targetBubbleTop - emojiHeight - 10 < minTop) {
      targetBubbleTop = minTop + emojiHeight + 10;
    }
    if (targetBubbleTop + bubbleHeight + 10 + menuHeight > maxBottom) {
      targetBubbleTop = maxBottom - menuHeight - 10 - bubbleHeight;
      if (targetBubbleTop - emojiHeight - 10 < minTop) {
        targetBubbleTop = minTop + emojiHeight + 10;
      }
    }

    HapticFeedback.mediumImpact();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Message actions',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogContext, animation1, animation2) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
        final primaryText = isDark ? Colors.white : Colors.black87;
        final emojiItems = ['👍', '❤️', '😂', '😮', '😢', '🙏', '👻'];

        Widget actionRow({
          required IconData icon,
          required String label,
          required VoidCallback onTap,
          Color? color,
        }) => InkWell(
          onTap: onTap,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color ?? primaryText),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color ?? primaryText,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        Widget divider() => Divider(
          height: 1,
          thickness: 0.5,
          color: isDark ? Colors.white12 : Colors.black12,
        );

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // 1. Frosted Glass Blur Background
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.pop(dialogContext),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.45)
                          : Colors.black.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),

              // 2. Scrollable Glass Sheet with Reactions, Message & Action Menu
              SafeArea(
                child: GestureDetector(
                  onTap: () => Navigator.pop(dialogContext),
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        // Emoji Reaction Bar
                        Material(
                          color: cardColor,
                          elevation: 8,
                          borderRadius: BorderRadius.circular(28),
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: screen.width * 0.82,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ...emojiItems.map(
                                      (emoji) => InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: messageId == null
                                            ? null
                                            : () {
                                                HapticFeedback.lightImpact();
                                                Navigator.pop(dialogContext);
                                                _reactToMessage(message, emoji);
                                              },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 6,
                                          ),
                                          child: Text(
                                            emoji,
                                            style: const TextStyle(
                                              fontSize: 24,
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'More reactions',
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        Navigator.pop(dialogContext);
                                        _showMoreReactions(message);
                                      },
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                        size: 26,
                                        color: AppTheme.subtitleGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Highlighted Message Preview (Scrollable for Big Messages)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: screen.width * 0.82,
                            maxHeight: screen.height * 0.45,
                          ),
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: ChatBubble(
                                chatId: widget.conversation.id,
                                message: message.content,
                                isMe: isMine,
                                timestamp: message.timestamp,
                                type: message.type,
                                mediaUrl: message.mediaUrl,
                                fileName: message.fileName,
                                isRead: message.isRead,
                                isDelivered: message.isDelivered,
                                isEdited: message.isEdited,
                                isDeleted: message.isDeleted,
                                isSaved: message.isSaved,
                                senderName: !isMine && widget.conversation.isGroup
                                    ? _groupMemberNames[int.tryParse(message.senderId)]
                                    : null,
                                replyToId: message.replyToId,
                                repliedMessage: message.replyToId == null
                                    ? null
                                    : _messages.cast<ChatMessage?>().firstWhere(
                                        (m) => m?.id == message.replyToId.toString(),
                                        orElse: () => null,
                                      ),
                                reactions: message.reaction == null
                                    ? null
                                    : [message.reaction!],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Glass Action Menu
                        Container(
                          width: menuWidth,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xEE2C2C2E)
                                : const Color(0xF2FFFFFF),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.35 : 0.1,
                                ),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              actionRow(
                                icon: Icons.reply_rounded,
                                label: 'Reply',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(dialogContext);
                                  _beginReply(message);
                                },
                              ),
                              divider(),
                              actionRow(
                                icon: Icons.shortcut_rounded,
                                label: 'Forward',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(dialogContext);
                                  _enterSelectionMode(message);
                                },
                              ),
                              divider(),
                              actionRow(
                                icon: Icons.copy_rounded,
                                label: 'Copy',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(dialogContext);
                                  Clipboard.setData(
                                    ClipboardData(text: message.content),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Message copied'),
                                    ),
                                  );
                                },
                              ),
                              divider(),
                              actionRow(
                                icon: Icons.share_rounded,
                                label: 'Share',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(dialogContext);
                                  _shareMessage(message);
                                },
                              ),
                              divider(),
                              actionRow(
                                icon: Icons.info_outline_rounded,
                                label: 'Info',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(dialogContext);
                                  _showMessageInfo(message);
                                },
                              ),
                              divider(),
                              actionRow(
                                icon: message.reaction == 'star'
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                label: message.reaction == 'star'
                                    ? 'Unstar'
                                    : 'Star',
                                color: message.reaction == 'star'
                                    ? Colors.amber
                                    : null,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(dialogContext);
                                  if (message.reaction == 'star') {
                                    _reactToMessage(message, '');
                                  } else {
                                    _reactToMessage(message, 'star');
                                  }
                                },
                              ),
                              divider(),
                              actionRow(
                                icon: message.isSaved
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                                label: message.isSaved
                                    ? 'Unsave Message'
                                    : 'Save Message',
                                color:
                                    message.isSaved ? AppTheme.primaryColor : null,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.pop(dialogContext);
                                  _toggleSaveMessage(message);
                                },
                              ),
                              if (canEdit) ...[
                                divider(),
                                actionRow(
                                  icon: Icons.edit_outlined,
                                  label: 'Edit',
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.pop(dialogContext);
                                    _beginEditingMessage(message);
                                  },
                                ),
                              ],
                              if (canDelete) ...[
                                divider(),
                                actionRow(
                                  icon: Icons.delete_outline_rounded,
                                  label: 'Delete',
                                  color: Colors.redAccent,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.pop(dialogContext);
                                    _deleteMessage(message);
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
  },
);
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
    final messageId = int.tryParse(message.id);
    if (messageId == null) return;
    final saved = await ServerApiService.instance.reactMessageREST(
      messageId: messageId,
      chatReact: emoji,
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

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messageId = int.tryParse(message.id);
    if (messageId == null) return;
    final deleted = await ServerApiService.instance.deleteMessageREST(
      messageId,
    );
    if (!deleted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message could not be deleted.')),
        );
      }
      return;
    }
    final updated = message.copyWith(
      content: 'This message was deleted',
      isDeleted: true,
    );
    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((item) => item.id == message.id);
        if (index >= 0) _messages[index] = updated;
        if (_editingMessage?.id == message.id) _editingMessage = null;
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
    final text = _inputController.text.trim();
    if (text.isEmpty || text == message.content) {
      _cancelEditingMessage();
      return;
    }

    setState(() => _isSending = true);
    final encryptedText = E2eCryptoService.instance.encryptText(
      text,
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
      await _saveEditedMessage();
      return;
    }
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    final localMsgId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = ChatMessage(
      id: localMsgId,
      senderId: 'user',
      content: text,
      timestamp: DateTime.now(),
      type: 'text',
      isRead: false,
      replyToId: _replyingMessage == null
          ? null
          : int.tryParse(_replyingMessage!.id),
    );
    final replyToId = _replyingMessage == null
        ? null
        : int.tryParse(_replyingMessage!.id);

    _inputController.clear();
    setState(() {
      _messages = [..._messages, optimisticMsg];
      _isSending = true;
    });
    _scrollToBottom();

    // Reset typing indicator
    final numericId = int.tryParse(widget.conversation.id);
    if (numericId != null) {
      SocketChatService.instance.sendTyping(
        chatHeadId: numericId,
        isTyping: false,
      );
    }

    try {
      final sent = await ServerChatManager.instance.sendMessage(
        chatId: widget.conversation.id,
        peerName: _chatName,
        text: text,
        peerUserId: widget.conversation.peerUserId,
        replyToId: replyToId,
      );
      if (!sent) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message could not be sent. Please try again.'),
            ),
          );
          setState(() {
            _messages = _messages.where((m) => m.id != localMsgId).toList();
            _inputController.text = text;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _messages = _messages.where((m) => m.id != localMsgId).toList();
          _replyingMessage = null;
        });
      }
      await _showCachedMessages();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _uploadAndSendAttachment({
    required File file,
    required String fileName,
    required String fileType,
    String? caption,
  }) async {
    if (mounted) setState(() => _isSending = true);
    try {
      final secretKey = 'chat_key_${widget.conversation.id}';

      // 1. Encrypt file bytes
      final rawBytes = await file.readAsBytes();
      final encryptedBytes = E2eCryptoService.instance.encryptFileBytes(
        rawBytes,
        secretKey,
      );

      final tempDir = await getTemporaryDirectory();
      final tempEncFile = File(
        '${tempDir.path}${Platform.pathSeparator}enc_upload_${DateTime.now().millisecondsSinceEpoch}.tmp',
      );
      await tempEncFile.writeAsBytes(encryptedBytes, flush: true);

      final messageText = (caption != null && caption.trim().isNotEmpty)
          ? caption.trim()
          : (fileType.startsWith('image/')
                ? 'Photo'
                : fileType.startsWith('video/')
                ? 'Video'
                : fileType.startsWith('audio/')
                ? 'Voice message'
                : fileName);

      // 2. Send file directly via POST /api/chats/:chat_id/messages (multipart form-data)
      String? uploadedPath;
      try {
        final serverMessage = await ServerApiService.instance.sendMessageREST(
          chatId: int.tryParse(widget.conversation.id) ?? 0,
          message: E2eCryptoService.instance.encryptText(
            messageText,
            secretKey,
          ),
          file: tempEncFile,
          fileName: fileName,
          fileType: fileType,
          replyToId: _replyingMessage == null
              ? null
              : int.tryParse(_replyingMessage!.id),
        );
        uploadedPath = serverMessage.filePath;
      } catch (e) {
        debugPrint('[DIRECT FILE SEND FALLBACK] $e');
        // Fallback to upload then send
        uploadedPath = await ServerApiService.instance.uploadFile(
          tempEncFile,
          filename: fileName,
        );
        if (uploadedPath != null && uploadedPath.isNotEmpty) {
          final sent = await ServerChatManager.instance.sendMessage(
            chatId: widget.conversation.id,
            peerName: _chatName,
            text: messageText,
            filePath: uploadedPath,
            fileName: fileName,
            fileType: fileType,
            peerUserId: widget.conversation.peerUserId,
            replyToId: _replyingMessage == null
                ? null
                : int.tryParse(_replyingMessage!.id),
          );
          if (!sent) throw Exception('The file message could not be sent.');
        }
      } finally {
        try {
          await tempEncFile.delete();
        } catch (_) {}
      }

      if (uploadedPath == null || uploadedPath.isEmpty) {
        throw Exception('The file could not be sent. Please try again.');
      }

      // 3. Save unencrypted original file copy in local chat_attachments
      final documents = await getApplicationDocumentsDirectory();
      final attachmentDirectory = Directory(
        '${documents.path}${Platform.pathSeparator}chat_attachments',
      );
      await attachmentDirectory.create(recursive: true);
      final mediaKey = uploadedPath
          .split('/')
          .last
          .split('\\')
          .last
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final localCopyPath =
          '${attachmentDirectory.path}${Platform.pathSeparator}${mediaKey}_$safeName';
      final localCopy = File(localCopyPath);
      await file.copy(localCopy.path);

      // Update AttachmentCacheService so sender's device maps mediaUrl to local path instantly
      AttachmentCacheService.instance.updateCache(uploadedPath, localCopy.path);

      if (mounted) setState(() => _replyingMessage = null);
      await _showCachedMessages();
    } catch (error) {
      debugPrint('[ATTACHMENT SEND ERROR] $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppToast.userFriendlyMessage('Unable to send attachment: $error'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
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

  void _scrollToMessageId(String targetId) {
    final index = _messages.indexWhere((m) => m.id == targetId);
    if (index < 0) {
      AppToast.show('Original message not found in history.');
      return;
    }
    if (!_scrollController.hasClients) return;

    final reversedIndex = (_messages.length - 1) - index;
    final viewportHeight = _scrollController.position.viewportDimension;
    // Calculate offset that places the target message in the center of the screen
    final centeredOffset = (reversedIndex * 78.0) - (viewportHeight / 2) + 39.0;
    final targetOffset = centeredOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );

    _highlightTimer?.cancel();
    setState(() {
      _highlightedMessageId = targetId;
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

  Future<void> _onSearchQueryChanged(String query) async {
    final generation = ++_searchGeneration;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _currentSearchIndex = -1;
      });
      return;
    }

    // Search the cached conversation as well as the current server page. A
    // chat may have older messages stored locally that are not mounted yet.
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

      // EXCLUDE IMAGES / MEDIA ATTACHMENTS - Search ONLY text messages!
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
      await LocalChatStorage.instance.cacheMessages(
        widget.conversation.id,
        _messages,
      );
      await LocalChatStorage.instance.updateConversation(
        widget.conversation.id,
        (conv) => conv.copyWith(
          unreadCount: 0,
          messages: _messages,
          lastMessage: _messages.isNotEmpty
              ? _messages.last.previewText
              : 'No messages yet',
        ),
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A terminated app is not guaranteed to run dispose().  Treat leaving the
    // foreground as the end of this viewing session so after-read messages are
    // not restored after an app restart.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_purgeSeenMessagesOnExit());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _purgeSeenMessagesOnExit();
    _messageSearchController.dispose();
    _messageSearchFocusNode.dispose();
    _highlightTimer?.cancel();
    if (ServerChatManager.instance.activeChatId == widget.conversation.id) {
      ServerChatManager.instance.activeChatId = null;
    }
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _presenceSubscription?.cancel();
    _readSubscription?.cancel();
    _editedSubscription?.cancel();
    _deletedSubscription?.cancel();
    _reactionSubscription?.cancel();
    _peerTypingTimer?.cancel();
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _isPeerOnline.dispose();
    _isPeerTyping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _purgeSeenMessagesOnExit();
        }
      },
      child: ShakePanicWrapper(
        child: Scaffold(
          backgroundColor: AppTheme.chatCanvas(isDark),
          body: ValueListenableBuilder<String>(
            valueListenable: AppPreferences.chatWallpaperNotifier,
            builder: (context, _, __) {
              return ValueListenableBuilder<int>(
                valueListenable: AppPreferences.chatBubbleColorNotifier,
                builder: (context, _, __) {
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
                        child: ChatMessageList(
                          messages: _messages,
                          isLoadingMessages: _isLoadingMessages,
                          isLoadingMore: _isLoadingMore,
                          isPeerTyping: false,
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
                        ),
                      ),

                      // Floating Typing Indicator Bubble above Composer (Commented out)
                      /*
                      Positioned(
                        left: 12,
                        bottom:
                            (_replyingMessage != null || _editingMessage != null
                                ? 118.0
                                : 66.0) +
                            MediaQuery.viewInsetsOf(context).bottom,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _isPeerTyping,
                          builder: (context, isTyping, _) {
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: isTyping
                                  ? ChatTypingIndicator(
                                      key: const ValueKey('floating_typing'),
                                      chatName: _chatName,
                                      chatAvatar: _chatAvatar,
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('floating_empty'),
                                    ),
                            );
                          },
                        ),
                      ),
                      */

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
                                onOpenChatInfo: _openChatInfo,
                                onSearchMessages: _toggleMessageSearch,
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

                      // Bottom Input Bar Composer
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ChatComposer(
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
                          onDisappearingTap: _showDisappearingMessagesPicker,
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
    );
  }
}
