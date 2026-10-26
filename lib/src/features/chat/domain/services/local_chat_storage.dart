import 'dart:async';
import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/chat_conversation.dart';
import '../entities/chat_message.dart';
import '../models/server_models.dart';
import 'bot_assistant_service.dart';
import 'presence_store.dart';

/// Local persistent storage manager for P2P messages and conversations.
class LocalChatStorage {
  LocalChatStorage._internal();
  static final LocalChatStorage instance = LocalChatStorage._internal();

  static const String _baseConversationsKey = 'PREF_P2P_CONVERSATIONS';

  final ValueNotifier<List<ChatConversation>> conversationsNotifier =
      ValueNotifier<List<ChatConversation>>([]);

  SharedPreferences? _prefs;
  int? _accountId;
  int _accountEpoch = 0;

  String _accountKey(String key) =>
      _accountId == null ? key : 'PREF_CHAT_ACCOUNT_${_accountId}_$key';

  String get _keyConversations => _accountKey(_baseConversationsKey);
  String _messageKey(String chatId) => _accountKey('PREF_MSG_$chatId');
  String _historyKey(String chatId) =>
      _accountKey('PREF_HISTORY_CACHED_$chatId');
  String _draftKey(String chatId) => _accountKey('PREF_DRAFT_$chatId');

  String? getDraft(String chatId) {
    if (_prefs == null || chatId.isEmpty) return null;
    return _prefs!.getString(_draftKey(chatId));
  }

  Future<void> saveDraft(String chatId, String text) async {
    if (_prefs == null || chatId.isEmpty) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      await _prefs!.remove(_draftKey(chatId));
    } else {
      await _prefs!.setString(_draftKey(chatId), text);
    }
  }

  Future<void> clearDraft(String chatId) async {
    if (_prefs == null || chatId.isEmpty) return;
    await _prefs!.remove(_draftKey(chatId));
  }

  void setAccountId(int? accountId) {
    if (_accountId == accountId) return;
    _accountId = accountId;
    _accountEpoch++;
    conversationsNotifier.value = const [];
    if (accountId != null) {
      unawaited(loadConversations());
    }
  }

  void _setConversationsNotifier(List<ChatConversation> list) {
    final accountId = _accountId;
    final unmodifiableList = List<ChatConversation>.unmodifiable(list);
    void publish() {
      if (_accountId == accountId) {
        conversationsNotifier.value = unmodifiableList;
      }
    }

    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) => publish());
      // addPostFrameCallback alone does not request a frame. Live socket
      // events often arrive while the app is idle, so request the frame that
      // delivers the notifier update when we had to defer it during layout.
      binding.ensureVisualUpdate();
    } else {
      // Publish immediately for socket/API updates while idle. This ensures a
      // typing or message event refreshes ValueListenableBuilder without
      // waiting for an unrelated rebuild or a later API response.
      publish();
    }
  }

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    await loadConversations();
  }

  /// Clears account chat data without touching app settings or device identity.
  Future<void> clearChats() async {
    _prefs ??= await SharedPreferences.getInstance();
    final messageKeys = _prefs!
        .getKeys()
        .where(
          (key) =>
              key.startsWith('PREF_MSG_') ||
              key.startsWith('PREF_HISTORY_CACHED_') ||
              key.startsWith('PREF_CHAT_ACCOUNT_') ||
              key == _baseConversationsKey,
        )
        .toList();
    for (final key in messageKeys) {
      await _prefs!.remove(key);
    }
    await _prefs!.remove(_keyConversations);
    // Clear synchronously so a newly logged-in account cannot render the old
    // notifier value for the remainder of the current frame.
    conversationsNotifier.value = const [];
  }

  Future<List<ChatConversation>> loadConversations() async {
    final epoch = _accountEpoch;
    final conversationsKey = _keyConversations;
    _prefs ??= await SharedPreferences.getInstance();
    if (epoch != _accountEpoch) return [];
    final jsonStr = _prefs?.getString(conversationsKey);

    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        final conversations = <ChatConversation>[];

        for (final item in jsonList) {
          final map = item as Map<String, dynamic>;
          final deviceId = map['id'] as String;
          final name = map['name'] as String;
          final avatarUrl = (map['avatarUrl'] as String?) ?? '';
          final isPinned = (map['isPinned'] as bool?) ?? false;
          final isMuted = (map['isMuted'] as bool?) ?? false;
          final isArchived = (map['isArchived'] as bool?) ?? false;

          final messages = await loadMessages(deviceId);
          final lastMsg = messages.isNotEmpty
              ? messages.last.content
              : (map['lastMessage'] as String? ?? 'No messages yet');
          final lastTimeStr =
              map['lastMessageTimeStr'] as String? ??
              (messages.isNotEmpty
                  ? _formatTime(messages.last.timestamp)
                  : 'Just now');

          conversations.add(
            ChatConversation(
              id: deviceId,
              name: name,
              avatarUrl: avatarUrl,
              lastMessage: lastMsg,
              lastMessageTime: lastTimeStr,
              lastActivityAt: map['lastActivityAt'] is int
                  ? DateTime.fromMillisecondsSinceEpoch(
                      map['lastActivityAt'] as int,
                    )
                  : DateTime.tryParse(map['lastActivityAt']?.toString() ?? ''),
              unreadCount: (map['unreadCount'] as int?) ?? 0,
              // Presence and typing are socket-only transient states. Do not
              // restore stale values from a previous app session.
              isOnline: false,
              lastSeenAt: map['lastSeenAt'] is int
                  ? DateTime.fromMillisecondsSinceEpoch(
                      map['lastSeenAt'] as int,
                    )
                  : DateTime.tryParse(map['lastSeenAt']?.toString() ?? ''),
              isTyping: false,
              peerUserId: map['peerUserId'] as int?,
              isGroup: map['isGroup'] as bool? ?? false,
              memberNames: ((map['memberNames'] as Map?) ?? const {}).map(
                (key, value) => MapEntry(
                  int.tryParse(key.toString()) ?? -1,
                  value.toString(),
                ),
              )..remove(-1),
              isPinned: isPinned,
              isMuted: isMuted,
              isArchived: isArchived,
              disappearType: (map['disappearType'] as int?) ?? 0,
              backgroundUrl: map['backgroundUrl'] as String?,
              messages: messages,
            ),
          );
        }

        if (epoch != _accountEpoch) return [];
        final withBot = await _ensureBotIncluded(conversations);
        _setConversationsNotifier(withBot);
        return withBot;
      } catch (_) {}
    }

    // Return bot conversation when list is otherwise empty
    if (epoch == _accountEpoch) {
      final emptyWithBot = await _ensureBotIncluded([]);
      _setConversationsNotifier(emptyWithBot);
      return emptyWithBot;
    }
    return [];
  }

  Future<List<ChatConversation>> _ensureBotIncluded(
    List<ChatConversation> conversations,
  ) async {
    final botIndex =
        conversations.indexWhere((c) => c.id == BotAssistantService.botId);
    if (botIndex < 0) {
      final botMessages = await loadMessages(BotAssistantService.botId);
      final initialMessages = botMessages.isNotEmpty
          ? botMessages
          : [
              ChatMessage(
                id: 'bot_welcome_1',
                senderId: BotAssistantService.botId,
                content:
                    '👋 Hello! I am your Calnox AI Assistant.\n\nHow can I help you today? Tap any of the suggested questions below or type your query!',
                timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
                isRead: true,
                isDelivered: true,
              ),
            ];

      if (botMessages.isEmpty) {
        await cacheMessages(BotAssistantService.botId, initialMessages);
      }

      final botConv = ChatConversation(
        id: BotAssistantService.botId,
        name: BotAssistantService.botName,
        avatarUrl: '',
        lastMessage: initialMessages.last.content,
        lastMessageTime: 'Online',
        lastActivityAt: DateTime.now(),
        unreadCount: 0,
        isOnline: true,
        isPinned: true,
        messages: initialMessages,
      );

      conversations.insert(0, botConv);
    } else {
      final bot = conversations[botIndex];
      conversations[botIndex] = bot.copyWith(isOnline: true);
    }
    return conversations;
  }

  Future<List<ChatConversation>> _currentConversations() async {
    final current = conversationsNotifier.value;
    if (current.isNotEmpty) return List<ChatConversation>.from(current);
    return loadConversations();
  }

  /// Replaces the cached conversation list with the latest server snapshot.
  Future<void> replaceConversations(
    List<ChatConversation> conversations,
  ) async {
    final epoch = _accountEpoch;
    final conversationsKey = _keyConversations;
    _prefs ??= await SharedPreferences.getInstance();
    if (epoch != _accountEpoch) return;
    final listWithBot = await _ensureBotIncluded(
      List<ChatConversation>.from(conversations),
    );
    for (final c in listWithBot) {
      if (!c.isGroup) {
        final pId = c.peerUserId ?? int.tryParse(c.id);
        if (pId != null && pId > 0) {
          PresenceStore.instance.bindChatUser(c.id, pId);
        }
      }
    }
    final snapshot = List<ChatConversation>.unmodifiable(listWithBot);
    conversationsNotifier.value = snapshot;
    final jsonList = snapshot
        .map(
          (c) => {
            'id': c.id,
            'name': c.name,
            'avatarUrl': c.avatarUrl,
            'lastMessage': c.lastMessage,
            'lastMessageTimeStr': c.lastMessageTime,
            'lastActivityAt': c.lastActivityAt?.millisecondsSinceEpoch,
            'unreadCount': c.unreadCount,
            'isPinned': c.isPinned,
            'disappearType': c.disappearType,
            'isOnline': c.isOnline,
            'lastSeenAt': c.lastSeenAt?.millisecondsSinceEpoch,
            'isTyping': c.isTyping,
            'peerUserId': c.peerUserId,
            'isGroup': c.isGroup,
            'backgroundUrl': c.backgroundUrl,
            'memberNames': c.memberNames.map(
              (key, value) => MapEntry('$key', value),
            ),
          },
        )
        .toList();
    await _prefs!.setString(conversationsKey, jsonEncode(jsonList));
  }

  Future<void> updateConversation(
    String deviceId,
    ChatConversation Function(ChatConversation current) update,
  ) async {
    final epoch = _accountEpoch;
    _prefs ??= await SharedPreferences.getInstance();
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final index = conversations.indexWhere(
      (conversation) => conversation.id == deviceId,
    );
    if (index < 0) return;
    conversations[index] = update(conversations[index]);
    _persistConversations(conversations);
  }

  Future<List<ChatMessage>> loadMessages(
    String deviceId, {
    int chatDisappearType = 0,
    bool keepReadSessionMessages = false,
  }) async {
    final epoch = _accountEpoch;
    final key = _messageKey(deviceId);
    _prefs ??= await SharedPreferences.getInstance();
    if (epoch != _accountEpoch) return [];
    final jsonStr = _prefs?.getString(key);

    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final List<ChatMessage> list = [];
      for (final item in jsonList) {
        final m = item as Map<String, dynamic>;
        final msg = ChatMessage(
          id: m['id'] as String,
          senderId: m['senderId'] as String,
          content: m['content'] as String,
          timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
          type: (m['type'] as String?) ?? 'text',
          mediaUrl: m['mediaUrl'] as String?,
          fileName: m['fileName'] as String?,
          isRead: (m['isRead'] as bool?) ?? false,
          isDelivered:
              (m['isDelivered'] as bool?) ?? ((m['isRead'] as bool?) ?? false),
          status: (m['status'] as String?) ??
              ((m['isRead'] as bool? ?? false)
                  ? 'read'
                  : ((m['isDelivered'] as bool? ?? false)
                      ? 'delivered'
                      : 'sent')),
          isEdited: (m['isEdited'] as bool?) ?? false,
          isDeleted: (m['isDeleted'] as bool?) ?? false,
          isSaved: (m['isSaved'] as bool?) ?? false,
          isForwarded: (m['isForwarded'] as bool?) ?? false,
          disappearType: (m['disappearType'] as int?) ?? 0,
          expiresAt: m['expiresAt'] != null
              ? DateTime.tryParse(m['expiresAt'].toString())
              : null,
          reaction: normalizeChatReaction(m['reaction']),
          replyToId: int.tryParse(m['replyToId']?.toString() ?? ''),
          msgType: m['msgType'] as String?,
          callId: m['callId'] as int?,
          callType: m['callType'] as String?,
          callStatus: m['callStatus'] as String?,
          callDuration: m['callDuration'] as int?,
        );
        if (!isMessageExpired(
          msg,
          chatDisappearType: chatDisappearType,
          keepReadSessionMessages: keepReadSessionMessages,
        )) {
          list.add(msg);
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> cacheMessages(
    String deviceId,
    List<ChatMessage> messages, {
    int chatDisappearType = 0,
    bool keepReadSessionMessages = false,
  }) async {
    final epoch = _accountEpoch;
    final messageKey = _messageKey(deviceId);
    final historyKey = _historyKey(deviceId);
    _prefs ??= await SharedPreferences.getInstance();
    if (epoch != _accountEpoch) return;
    final jsonList = messages
        .where(
          (message) => !isMessageExpired(
            message,
            chatDisappearType: chatDisappearType,
            keepReadSessionMessages: keepReadSessionMessages,
          ),
        )
        .map(
          (message) => {
            'id': message.id,
            'senderId': message.senderId,
            'content': message.content,
            'timestamp': message.timestamp.millisecondsSinceEpoch,
            'type': message.type,
            'mediaUrl': message.mediaUrl,
            'fileName': message.fileName,
            'isRead': message.isRead,
            'isDelivered': message.isDelivered,
            'isEdited': message.isEdited,
            'isDeleted': message.isDeleted,
            'isSaved': message.isSaved,
            'isForwarded': message.isForwarded,
            'disappearType': message.disappearType,
            'expiresAt': message.expiresAt?.toIso8601String(),
            'reaction': message.reaction,
            'replyToId': message.replyToId,
            'msgType': message.msgType,
            'callId': message.callId,
            'callType': message.callType,
            'callStatus': message.callStatus,
            'callDuration': message.callDuration,
          },
        )
        .toList();
    await _prefs?.setString(messageKey, jsonEncode(jsonList));
    if (epoch != _accountEpoch) return;
    await _prefs?.setBool(historyKey, true);
  }

  Future<bool> hasCompleteHistory(String deviceId) async {
    final epoch = _accountEpoch;
    final key = _historyKey(deviceId);
    _prefs ??= await SharedPreferences.getInstance();
    if (epoch != _accountEpoch) return false;
    return _prefs?.getBool(key) ?? false;
  }

  Future<void> markHistoryIncomplete(String deviceId) async {
    final epoch = _accountEpoch;
    final key = _historyKey(deviceId);
    _prefs ??= await SharedPreferences.getInstance();
    if (epoch != _accountEpoch) return;
    await _prefs?.setBool(key, false);
  }

  Future<void> updatePeerProfile({
    required String deviceId,
    required String displayName,
    String? avatarUrl,
  }) async {
    final epoch = _accountEpoch;
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final index = conversations.indexWhere((c) => c.id == deviceId);

    if (index >= 0) {
      final existing = conversations[index];
      final newAvatar = (avatarUrl != null && avatarUrl.isNotEmpty)
          ? avatarUrl
          : existing.avatarUrl;

      if (existing.name != displayName || existing.avatarUrl != newAvatar) {
        conversations[index] = existing.copyWith(
          name: displayName,
          avatarUrl: newAvatar,
        );
        _persistConversations(conversations);
      }
    }
  }

  Future<void> saveMessage({
    required String deviceId,
    required String peerName,
    required ChatMessage message,
    bool markUnread = true,
    bool clearTyping = false,
    int? peerUserId,
  }) async {
    final epoch = _accountEpoch;
    _prefs ??= await SharedPreferences.getInstance();
    if (epoch != _accountEpoch) return;

    // 1. Save Message
    final messages = await loadMessages(deviceId);
    if (epoch != _accountEpoch) return;
    final existingIdx = messages.indexWhere((m) {
      if (m.id == message.id) return true;
      final isLocalId = m.id.startsWith('local_') ||
          m.id.startsWith('fwd_') ||
          message.id.startsWith('local_');
      final isMediaMsg = m.hasMedia ||
          message.hasMedia ||
          m.type == 'image/gif' ||
          message.type == 'image/gif';

      if (isMediaMsg) {
        return isLocalId &&
            m.senderId == message.senderId &&
            m.mediaUrl != null &&
            m.mediaUrl!.isNotEmpty &&
            m.mediaUrl == message.mediaUrl;
      }

      return isLocalId &&
          m.senderId == message.senderId &&
          m.content.trim() == message.content.trim() &&
          m.timestamp.difference(message.timestamp).inSeconds.abs() <= 3;
    });
    final isNewMessage = existingIdx < 0;
    if (existingIdx >= 0) {
      final existing = messages[existingIdx];
      final effectiveContent = (message.content.trim().isEmpty ||
                  message.content == '[Attachment]') &&
              existing.content.trim().isNotEmpty &&
              existing.content != '[Attachment]'
          ? existing.content
          : message.content;

      final isTextMsg = message.type == 'text' || message.type == 'text/plain';
      final effectiveMediaUrl = isTextMsg
          ? null
          : ((message.mediaUrl == null || message.mediaUrl!.isEmpty) &&
                  existing.mediaUrl != null &&
                  existing.mediaUrl!.isNotEmpty
              ? existing.mediaUrl
              : message.mediaUrl);

      messages[existingIdx] = message.copyWith(
        content: effectiveContent,
        mediaUrl: effectiveMediaUrl,
        isSaved: message.isSaved,
      );
    } else {
      messages.add(message);
    }
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final latestMessage = messages.last;

    final msgJsonList = messages.map((m) {
      return {
        'id': m.id,
        'senderId': m.senderId,
        'content': m.content,
        'timestamp': m.timestamp.millisecondsSinceEpoch,
        'type': m.type,
        'mediaUrl': m.mediaUrl,
        'fileName': m.fileName,
        'isRead': m.isRead,
        'isDelivered': m.isDelivered,
        'isEdited': m.isEdited,
        'isDeleted': m.isDeleted,
        'isSaved': m.isSaved,
        'reaction': m.reaction,
        'replyToId': m.replyToId,
      };
    }).toList();

    await _prefs?.setString(_messageKey(deviceId), jsonEncode(msgJsonList));
    if (epoch != _accountEpoch) return;

    // 2. Update Conversation List (Move to top)
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final index = conversations.indexWhere((c) => c.id == deviceId);

    final isIncoming = message.senderId != 'user';

    if (index >= 0) {
      final existing = conversations[index];
      final updated = existing.copyWith(
        name: peerName.startsWith('User #') || peerName.startsWith('Chat #')
            ? existing.name
            : peerName,
        peerUserId: peerUserId,
        lastMessage: latestMessage.previewText.isNotEmpty
            ? latestMessage.previewText
            : '[Attachment]',
        lastMessageTime: _formatTime(latestMessage.timestamp),
        lastActivityAt: latestMessage.timestamp,
        unreadCount: isIncoming
            ? (markUnread && isNewMessage
                  ? existing.unreadCount + 1
                  : existing.unreadCount)
            : 0,
        isTyping: clearTyping ? false : existing.isTyping,
        messages: messages,
      );
      conversations.removeAt(index);
      conversations.insert(0, updated);
    } else {
      conversations.insert(
        0,
        ChatConversation(
          id: deviceId,
          name: peerName,
          avatarUrl: '',
          lastMessage: latestMessage.previewText.isNotEmpty
              ? latestMessage.previewText
              : '[Attachment]',
          lastMessageTime: _formatTime(latestMessage.timestamp),
          lastActivityAt: latestMessage.timestamp,
          unreadCount: isIncoming && markUnread ? 1 : 0,
          peerUserId: peerUserId,
          isPinned: false,
          messages: messages,
        ),
      );
    }

    _persistConversations(conversations);
  }

  Future<void> markAllOutgoingMessagesAsDelivered(String deviceId) async {
    final epoch = _accountEpoch;
    final messageKey = _messageKey(deviceId);
    _prefs ??= await SharedPreferences.getInstance();
    if (epoch != _accountEpoch) return;
    final messages = await loadMessages(deviceId);
    if (epoch != _accountEpoch) return;
    var updated = false;

    for (var i = 0; i < messages.length; i++) {
      if (messages[i].senderId == 'user' && !messages[i].isDelivered) {
        messages[i] = messages[i].copyWith(isDelivered: true, status: 'delivered');
        updated = true;
      }
    }

    if (updated) {
      final msgJsonList = messages.map((m) {
        return {
          'id': m.id,
          'senderId': m.senderId,
          'content': m.content,
          'timestamp': m.timestamp.millisecondsSinceEpoch,
          'type': m.type,
          'mediaUrl': m.mediaUrl,
          'fileName': m.fileName,
          'isRead': m.isRead,
          'isDelivered': m.isDelivered,
          'status': m.status,
          'isEdited': m.isEdited,
          'isDeleted': m.isDeleted,
          'reaction': m.reaction,
          'replyToId': m.replyToId,
        };
      }).toList();

      await _prefs?.setString(messageKey, jsonEncode(msgJsonList));
      if (epoch != _accountEpoch) return;
      final conversations = await _currentConversations();
      if (epoch != _accountEpoch) return;
      final index = conversations.indexWhere((item) => item.id == deviceId);
      if (index >= 0) {
        conversations[index] = conversations[index].copyWith(
          messages: messages,
        );
        _persistConversations(conversations);
      }
    }
  }

  Future<void> markAllOutgoingMessagesAsRead(
    String deviceId, {
    DateTime? readThrough,
  }) async {
    final epoch = _accountEpoch;
    final messageKey = _messageKey(deviceId);
    _prefs ??= await SharedPreferences.getInstance();
    if (epoch != _accountEpoch) return;
    final messages = await loadMessages(deviceId);
    if (epoch != _accountEpoch) return;
    var updated = false;

    for (var i = 0; i < messages.length; i++) {
      final wasReadByPeer =
          readThrough == null || !messages[i].timestamp.isAfter(readThrough);
      if (messages[i].senderId == 'user' &&
          wasReadByPeer &&
          (!messages[i].isRead || !messages[i].isDelivered)) {
        messages[i] = messages[i].copyWith(isRead: true, isDelivered: true);
        updated = true;
      }
    }

    if (updated) {
      final msgJsonList = messages.map((m) {
        return {
          'id': m.id,
          'senderId': m.senderId,
          'content': m.content,
          'timestamp': m.timestamp.millisecondsSinceEpoch,
          'type': m.type,
          'mediaUrl': m.mediaUrl,
          'fileName': m.fileName,
          'isRead': m.isRead,
          'isDelivered': m.isDelivered,
          'isEdited': m.isEdited,
          'isDeleted': m.isDeleted,
          'reaction': m.reaction,
          'replyToId': m.replyToId,
        };
      }).toList();

      await _prefs?.setString(messageKey, jsonEncode(msgJsonList));
      if (epoch != _accountEpoch) return;
      final conversations = await _currentConversations();
      if (epoch != _accountEpoch) return;
      final index = conversations.indexWhere((item) => item.id == deviceId);
      if (index >= 0) {
        conversations[index] = conversations[index].copyWith(
          messages: messages,
        );
        _persistConversations(conversations);
      }
    }
  }

  ChatConversation? getConversationSync(String chatId) {
    for (final c in conversationsNotifier.value) {
      if (c.id == chatId) return c;
    }
    return null;
  }

  Future<void> markAsRead(String deviceId) async {
    final epoch = _accountEpoch;
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final index = conversations.indexWhere((c) => c.id == deviceId);
    if (index >= 0) {
      final existing = conversations[index];
      conversations[index] = existing.copyWith(unreadCount: 0);
      _persistConversations(conversations);
    }
  }

  Future<void> togglePinConversation(String chatId) async {
    final epoch = _accountEpoch;
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final index = conversations.indexWhere((c) => c.id == chatId);
    if (index >= 0) {
      final existing = conversations[index];
      conversations[index] = existing.copyWith(isPinned: !existing.isPinned);
      _persistConversations(conversations);
    }
  }

  Future<void> toggleMuteConversation(String chatId) async {
    final epoch = _accountEpoch;
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final index = conversations.indexWhere((c) => c.id == chatId);
    if (index >= 0) {
      final existing = conversations[index];
      conversations[index] = existing.copyWith(isMuted: !existing.isMuted);
      _persistConversations(conversations);
    }
  }

  Future<void> toggleUnreadConversation(String chatId) async {
    final epoch = _accountEpoch;
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final index = conversations.indexWhere((c) => c.id == chatId);
    if (index >= 0) {
      final existing = conversations[index];
      final newCount = existing.unreadCount > 0 ? 0 : 1;
      conversations[index] = existing.copyWith(unreadCount: newCount);
      _persistConversations(conversations);
    }
  }

  Future<void> toggleArchiveConversation(String chatId) async {
    final epoch = _accountEpoch;
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final index = conversations.indexWhere((c) => c.id == chatId);
    if (index >= 0) {
      final existing = conversations[index];
      conversations[index] = existing.copyWith(
        isArchived: !existing.isArchived,
      );
      _persistConversations(conversations);
    }
  }

  Future<void> markAllAsRead() async {
    final epoch = _accountEpoch;
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final updated = conversations
        .map((c) => c.copyWith(unreadCount: 0))
        .toList();
    _persistConversations(updated);
  }

  Future<void> deleteConversation(String chatId) async {
    final epoch = _accountEpoch;
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    conversations.removeWhere((c) => c.id == chatId);
    _persistConversations(conversations);
  }

  Future<void> deleteLocalMessage(String deviceId, String messageId) async {
    final epoch = _accountEpoch;
    _prefs ??= await SharedPreferences.getInstance();
    if (epoch != _accountEpoch) return;

    final cached = await loadMessages(deviceId);
    cached.removeWhere((m) => m.id == messageId);
    await cacheMessages(deviceId, cached);

    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final index = conversations.indexWhere((c) => c.id == deviceId);
    if (index >= 0) {
      final existing = conversations[index];
      final latestMessage = cached.isNotEmpty ? cached.last : null;
      if (latestMessage != null) {
        conversations[index] = existing.copyWith(
          lastMessage: latestMessage.previewText.isNotEmpty
              ? latestMessage.previewText
              : 'Message',
          lastActivityAt: latestMessage.timestamp,
        );
      } else {
        conversations[index] = existing.copyWith(
          lastMessage: '',
        );
      }
      _persistConversations(conversations);
    }
  }

  Future<void> createOrGetConversation({
    required String deviceId,
    required String displayName,
    String? avatarUrl,
    int? peerUserId,
  }) async {
    final epoch = _accountEpoch;
    final conversations = await _currentConversations();
    if (epoch != _accountEpoch) return;
    final index = conversations.indexWhere((c) => c.id == deviceId);

    final avatar = (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : '';

    if (index < 0) {
      conversations.insert(
        0,
        ChatConversation(
          id: deviceId,
          name: displayName,
          avatarUrl: avatar,
          lastMessage: 'Tap to start secret thread',
          lastMessageTime: 'Just now',
          lastActivityAt: DateTime.now(),
          unreadCount: 0,
          peerUserId: peerUserId,
          isPinned: false,
          messages: [],
        ),
      );
      _persistConversations(conversations);
    } else if ((avatar.isNotEmpty &&
            conversations[index].avatarUrl != avatar) ||
        conversations[index].name != displayName ||
        conversations[index].peerUserId != peerUserId) {
      final existing = conversations[index];
      conversations[index] = existing.copyWith(
        name: displayName,
        avatarUrl: avatar.isNotEmpty ? avatar : existing.avatarUrl,
        peerUserId: peerUserId,
      );
      _persistConversations(conversations);
    }
  }

  void _persistConversations(List<ChatConversation> list) {
    final epoch = _accountEpoch;
    final key = _keyConversations;
    _setConversationsNotifier(list);

    final jsonList = list.map((c) {
      return {
        'id': c.id,
        'name': c.name,
        'avatarUrl': c.avatarUrl,
        'lastMessage': c.lastMessage,
        'lastMessageTimeStr': c.lastMessageTime,
        'lastActivityAt': c.lastActivityAt?.millisecondsSinceEpoch,
        'unreadCount': c.unreadCount,
        'isPinned': c.isPinned,
        'isMuted': c.isMuted,
        'isArchived': c.isArchived,
        'disappearType': c.disappearType,
        'isOnline': c.isOnline,
        'isTyping': c.isTyping,
        'peerUserId': c.peerUserId,
        'isGroup': c.isGroup,
        'memberNames': c.memberNames.map(
          (key, value) => MapEntry('$key', value),
        ),
      };
    }).toList();

    if (epoch == _accountEpoch) {
      _prefs?.setString(key, jsonEncode(jsonList));
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (now.day == time.day &&
        now.month == time.month &&
        now.year == time.year) {
      final hour = time.hour > 12
          ? time.hour - 12
          : (time.hour == 0 ? 12 : time.hour);
      final min = time.minute.toString().padLeft(2, '0');
      final period = time.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$min $period';
    }
    return '${time.month}/${time.day}';
  }
}
