import 'dart:async';
import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../entities/chat_conversation.dart';
import '../entities/chat_message.dart';
import '../models/server_models.dart';

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
        _setConversationsNotifier(conversations);
        return conversations;
      } catch (_) {}
    }

    // Return clean empty list for real API server integration
    if (epoch == _accountEpoch) _setConversationsNotifier([]);
    return [];
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
    final snapshot = List<ChatConversation>.unmodifiable(conversations);
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
          isEdited: (m['isEdited'] as bool?) ?? false,
          isDeleted: (m['isDeleted'] as bool?) ?? false,
          isSaved: (m['isSaved'] as bool?) ?? false,
          disappearType: (m['disappearType'] as int?) ?? 0,
          expiresAt: m['expiresAt'] != null
              ? DateTime.tryParse(m['expiresAt'].toString())
              : null,
          reaction: normalizeChatReaction(m['reaction']),
          replyToId: int.tryParse(m['replyToId']?.toString() ?? ''),
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
            'disappearType': message.disappearType,
            'expiresAt': message.expiresAt?.toIso8601String(),
            'reaction': message.reaction,
            'replyToId': message.replyToId,
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
    final existingIdx = messages.indexWhere(
      (m) =>
          m.id == message.id ||
          (m.senderId == message.senderId &&
              m.content == message.content &&
              m.timestamp.difference(message.timestamp).inSeconds.abs() <= 5),
    );
    final isNewMessage = existingIdx < 0;
    if (existingIdx >= 0) {
      messages[existingIdx] = message;
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
        messages[i] = messages[i].copyWith(isDelivered: true);
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
