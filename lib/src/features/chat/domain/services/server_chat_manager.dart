import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/config/app_preferences.dart';
import '../entities/chat_conversation.dart';
import '../entities/chat_message.dart';
import '../models/server_models.dart';
import 'e2e_crypto_service.dart';
import 'local_chat_storage.dart';
import 'server_api_service.dart';
import 'socket_chat_service.dart';

/// Container for paginated chat message history
class PaginatedMessagesResult {
  final List<ChatMessage> messages;
  final int page;
  final int totalPages;
  final int total;
  final bool hasMore;

  PaginatedMessagesResult({
    required this.messages,
    required this.page,
    required this.totalPages,
    required this.total,
    required this.hasMore,
  });
}

/// Central Server-based Chat Manager orchestrating REST API & Socket.IO.
class ServerChatManager {
  ServerChatManager._();

  static final ServerChatManager instance = ServerChatManager._();

  String? activeChatId;
  int _socketGeneration = 0;

  final List<StreamSubscription> _socketSubscriptions = [];
  final Map<String, Timer> _typingTimers = {};
  final Set<String> _typingChatIds = {};

  /// Ends the active account session, clears local chat cache, profile preferences, and media attachments.
  Future<void> logout() async {
    _socketGeneration++;
    for (final sub in _socketSubscriptions) {
      await sub.cancel();
    }
    _socketSubscriptions.clear();
    SocketChatService.instance.disconnect();
    activeChatId = null;
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typingChatIds.clear();

    // Invalidate the in-memory identity, profile, and local chats storage
    await ServerApiService.instance.clearSession();
    await LocalChatStorage.instance.clearChats();
    await AppPreferences.clearAccountProfile();

    // Clean up cached attachments directory from disk
    try {
      final documents = await getApplicationDocumentsDirectory();
      final attachmentDir = Directory(
        '${documents.path}${Platform.pathSeparator}chat_attachments',
      );
      if (await attachmentDir.exists()) {
        await attachmentDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[LOGOUT] Attachment directory cleanup error: $e');
    }
  }

  /// Initializes Server API session, loads server chats, and connects Socket.IO.
  Future<void> init() async {
    await ServerApiService.instance.init();

    if (ServerApiService.instance.authToken != null) {
      _listenToSocketEvents();
      SocketChatService.instance.connect();
      await syncChats();
    }
  }

  /// Fetches latest chats from GET /api/chats and updates the chat list.
  /// Live message events update the list locally without calling this method.
  Future<List<ChatConversation>> syncChats() async {
    final syncUserId = ServerApiService.instance.currentUserId;
    final syncToken = ServerApiService.instance.authToken;
    final previousConversations =
        LocalChatStorage.instance.conversationsNotifier.value.isNotEmpty
        ? LocalChatStorage.instance.conversationsNotifier.value
        : await LocalChatStorage.instance.loadConversations();
    final previousById = {
      for (final conversation in previousConversations)
        conversation.id: conversation,
    };
    final serverChats = await ServerApiService.instance.getChats();
    if (syncUserId != ServerApiService.instance.currentUserId ||
        syncToken != ServerApiService.instance.authToken) {
      return [];
    }
    final conversations = <ChatConversation>[];

    for (final sc in serverChats) {
      final cachedMessages = await LocalChatStorage.instance.loadMessages(
        sc.id.toString(),
      );
      if (sc.lastMessageId != null) {
        if (!cachedMessages.any(
          (message) => message.id == sc.lastMessageId.toString(),
        )) {
          await LocalChatStorage.instance.markHistoryIncomplete(
            sc.id.toString(),
          );
        }
      }
      final currentUserId = ServerApiService.instance.currentUserId;
      final otherMembers = sc.members
          .where((member) => member.id != currentUserId)
          .toList();
      final peer = otherMembers.isNotEmpty ? otherMembers.first : null;
      final name = sc.isGroup
          ? (sc.groupName ?? 'Group chat')
          : (peer?.name ?? sc.groupName ?? 'Chat #${sc.id}');
      final avatar = sc.isGroup
          ? (sc.groupAvatar ?? '')
          : (peer?.avatar ?? sc.groupAvatar ?? '');
      final previous = previousById[sc.id.toString()];
      final newestCachedMessage = cachedMessages.isEmpty
          ? null
          : cachedMessages.last;
      final serverLastMessageTime = DateTime.tryParse(
        sc.lastMessageCreatedAt ?? sc.updatedAt ?? '',
      )?.toLocal();
      final cachedMessageIsNewer =
          newestCachedMessage != null &&
          (serverLastMessageTime == null ||
              newestCachedMessage.timestamp.isAfter(serverLastMessageTime));

      // Decrypt last message if encrypted
      var lastMsgText = sc.lastMessage ?? sc.lastMessageCiphertext ?? '';
      if (lastMsgText.isEmpty && sc.lastMessageFilePath != null) {
        lastMsgText = sc.lastMessageFileName ?? 'Attachment';
      } else if (lastMsgText.isNotEmpty) {
        lastMsgText = E2eCryptoService.instance.decryptText(
          lastMsgText,
          'chat_key_${sc.id}',
        );
      }
      if (lastMsgText.isEmpty) lastMsgText = 'No messages yet';
      if (cachedMessageIsNewer && newestCachedMessage != null) {
        lastMsgText = newestCachedMessage.previewText.isNotEmpty
            ? newestCachedMessage.previewText
            : '[Attachment]';
      }

      final conversation = ChatConversation(
        id: sc.id.toString(),
        name: name,
        avatarUrl: avatar,
        lastMessage: lastMsgText,
        lastMessageTime: cachedMessageIsNewer && newestCachedMessage != null
            ? _formatChatTime(newestCachedMessage!.timestamp.toIso8601String())
            : _formatChatTime(sc.lastMessageCreatedAt ?? sc.updatedAt),
        lastActivityAt: cachedMessageIsNewer && newestCachedMessage != null
            ? newestCachedMessage.timestamp
            : serverLastMessageTime ??
                  DateTime.tryParse(sc.updatedAt ?? '')?.toLocal() ??
                  previous?.lastActivityAt,
        unreadCount:
            cachedMessageIsNewer &&
                (previous?.unreadCount ?? 0) > sc.unreadCount
            ? previous!.unreadCount
            : sc.unreadCount,
        isOnline: peer?.isOnline == true || previous?.isOnline == true,
        isTyping:
            _typingChatIds.contains(sc.id.toString()) ||
            (previous?.isTyping ?? false),
        peerUserId: sc.isGroup ? null : peer?.id,
        isGroup: sc.isGroup,
        memberNames: {for (final member in sc.members) member.id: member.name},
        isPinned: previous?.isPinned ?? false,
        isMuted: previous?.isMuted ?? false,
        messages: [],
      );

      conversations.add(conversation);
    }

    if (syncUserId != ServerApiService.instance.currentUserId ||
        syncToken != ServerApiService.instance.authToken) {
      return [];
    }
    conversations.sort((a, b) {
      final aTime = a.lastActivityAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.lastActivityAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });
    await LocalChatStorage.instance.replaceConversations(conversations);

    return conversations;
  }

  String _formatChatTime(String? raw) {
    if (raw == null) return '';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return '';
    final now = DateTime.now();
    final day = DateTime(parsed.year, parsed.month, parsed.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) {
      final hour24 = parsed.hour;
      final hour = hour24 > 12 ? hour24 - 12 : (hour24 == 0 ? 12 : hour24);
      final min = parsed.minute.toString().padLeft(2, '0');
      final period = hour24 >= 12 ? 'PM' : 'AM';
      return '$hour:$min $period';
    }
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (parsed.year == now.year) return '${parsed.day}/${parsed.month}';
    return '${parsed.day}/${parsed.month}/${parsed.year}';
  }

  /// Loads a single page of message history from GET /api/chats/:id/messages?page={page}&limit={limit}
  Future<PaginatedMessagesResult> loadMessagesPage(
    String chatId, {
    int page = 1,
    int limit = 20,
  }) async {
    final requestUserId = ServerApiService.instance.currentUserId;
    final requestToken = ServerApiService.instance.authToken;
    final numericId = int.tryParse(chatId) ?? 0;
    if (numericId <= 0) {
      final cached = await LocalChatStorage.instance.loadMessages(chatId);
      return PaginatedMessagesResult(
        messages: cached,
        page: 1,
        totalPages: 1,
        total: cached.length,
        hasMore: false,
      );
    }

    try {
      final pageRes = await ServerApiService.instance.getMessagesPage(
        numericId,
        page: page,
        limit: limit,
      );

      if (requestUserId != ServerApiService.instance.currentUserId ||
          requestToken != ServerApiService.instance.authToken) {
        final cached = await LocalChatStorage.instance.loadMessages(chatId);
        return PaginatedMessagesResult(
          messages: cached,
          page: 1,
          totalPages: 1,
          total: cached.length,
          hasMore: false,
        );
      }

      final cachedMessages = await LocalChatStorage.instance.loadMessages(chatId);
      final cachedById = {
        for (final message in cachedMessages) message.id: message,
      };
      final currentUserId = ServerApiService.instance.currentUserId;

      final messages = <ChatMessage>[];
      for (final sm in pageRes.messages) {
        final isMe = currentUserId != null && sm.senderId == currentUserId;
        final plaintext = sm.decryptedContent('chat_key_${sm.chatHeadId}');

        DateTime ts;
        try {
          ts = DateTime.parse(sm.createdAt).toLocal();
        } catch (_) {
          ts = DateTime.now();
        }

        final cachedMessage = cachedById[sm.id.toString()];
        messages.add(
          ChatMessage(
            id: sm.id.toString(),
            senderId: isMe ? 'user' : sm.senderId.toString(),
            content: sm.isDeleted
                ? 'This message was deleted'
                : (plaintext.isEmpty ? cachedMessage?.content ?? '' : plaintext),
            timestamp: ts,
            type:
                inferAttachmentType(
                  fileType: sm.fileType,
                  fileName: sm.fileName,
                  filePath: sm.filePath,
                ) ??
                (sm.filePath != null
                    ? 'application/octet-stream'
                    : cachedMessage?.type ?? 'text'),
            mediaUrl: sm.filePath ?? cachedMessage?.mediaUrl,
            fileName: sm.fileName ?? cachedMessage?.fileName,
            isRead: true,
            isEdited: sm.isEdited,
            isDeleted: sm.isDeleted,
            reaction: sm.chatReact,
            replyToId: sm.replyToId,
          ),
        );
      }

      // Sort page messages chronologically
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Cache messages locally
      final mergedById = {for (final message in cachedMessages) message.id: message};
      for (final message in messages) {
        mergedById[message.id] = message;
      }
      final mergedAll = mergedById.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      await LocalChatStorage.instance.cacheMessages(chatId, mergedAll);

      return PaginatedMessagesResult(
        messages: messages,
        page: pageRes.page,
        totalPages: pageRes.totalPages,
        total: pageRes.total,
        hasMore: pageRes.hasMore,
      );
    } catch (e) {
      debugPrint('[ServerChatManager] Page $page load failed for $chatId: $e');
      final cached = await LocalChatStorage.instance.loadMessages(chatId);
      return PaginatedMessagesResult(
        messages: cached,
        page: page,
        totalPages: page,
        total: cached.length,
        hasMore: false,
      );
    }
  }

  /// Loads latest message page for backward compatibility
  Future<List<ChatMessage>> loadMessages(String chatId) async {
    final res = await loadMessagesPage(chatId, page: 1, limit: 20);
    return res.messages;
  }

  /// Sends a new message via REST API / Socket.IO
  Future<bool> sendMessage({
    required String chatId,
    required String peerName,
    required String text,
    String? filePath,
    String? fileName,
    String? fileType,
    int? peerUserId,
    int? replyToId,
  }) async {
    final requestUserId = ServerApiService.instance.currentUserId;
    final requestToken = ServerApiService.instance.authToken;
    final numericId = int.tryParse(chatId) ?? 0;
    ServerMessageModel? serverMessage;
    final clientId = 'local_${DateTime.now().millisecondsSinceEpoch}';

    final encryptedText = E2eCryptoService.instance.encryptText(
      text,
      'chat_key_$chatId',
    );

    // The supported send contract is POST /api/chats/{chat_id}/messages.
    // Socket.IO remains responsible for receiving real-time messages; its
    // send_message acknowledgement currently rejects this payload as missing
    // `message`, even when the field is present. Send through REST directly.
    if (serverMessage == null && numericId > 0) {
      try {
        serverMessage = await ServerApiService.instance.sendMessageREST(
          chatId: numericId,
          message: encryptedText,
          filePath: filePath,
          fileName: fileName,
          fileType: fileType,
          replyToId: replyToId,
          clientId: clientId,
        );
      } catch (e) {
        debugPrint('[SERVER CHAT] Send Message REST Error: $e');
        return false;
      }
    }

    DateTime timestamp = DateTime.now();
    if (serverMessage != null) {
      timestamp =
          DateTime.tryParse(serverMessage.createdAt)?.toLocal() ?? timestamp;
    }

    if (requestUserId != ServerApiService.instance.currentUserId ||
        requestToken != ServerApiService.instance.authToken) {
      return false;
    }

    // Cache the server-confirmed message for display and offline fallback.
    final msg = ChatMessage(
      id:
          serverMessage?.id.toString() ??
          'local_${DateTime.now().millisecondsSinceEpoch}',
      senderId: 'user',
      content: text,
      timestamp: timestamp,
      type: fileType ?? (filePath != null ? 'image' : 'text'),
      mediaUrl: filePath,
      fileName: fileName,
      isRead: false,
      isEdited: serverMessage?.isEdited ?? false,
      replyToId: serverMessage?.replyToId ?? replyToId,
    );

    await LocalChatStorage.instance.saveMessage(
      deviceId: chatId,
      peerName: peerName,
      message: msg,
      clearTyping: true,
      peerUserId: peerUserId,
    );

    return true;
  }

  /// Marks a chat as read via Socket.IO & REST API
  Future<void> markChatRead(String chatId) async {
    final numericId = int.tryParse(chatId) ?? 0;
    if (numericId > 0) {
      if (SocketChatService.instance.isConnected) {
        unawaited(SocketChatService.instance.markRead(chatHeadId: numericId));
      }
      unawaited(ServerApiService.instance.markChatRead(numericId));
    }
    await LocalChatStorage.instance.markAsRead(chatId);
  }

  Future<void> _handleEditedMessage(Map<String, dynamic> event) async {
    var data = event;
    if (event['data'] is Map) {
      data = Map<String, dynamic>.from(event['data'] as Map);
    }
    if (data['message'] is Map) {
      data = Map<String, dynamic>.from(data['message'] as Map);
    }

    final messageId = (data['id'] ?? data['message_id'])?.toString();
    final chatId = (data['chat_head_id'] ?? data['chat_id'])?.toString();
    final rawText = data['message']?.toString() ?? data['ciphertext']?.toString();
    if (messageId == null || chatId == null || rawText == null) return;

    final decryptedText = E2eCryptoService.instance.decryptText(
      rawText,
      'chat_key_$chatId',
    );

    final messages = await LocalChatStorage.instance.loadMessages(chatId);
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;

    final updated = messages[index].copyWith(content: decryptedText, isEdited: true);
    await LocalChatStorage.instance.saveMessage(
      deviceId: chatId,
      peerName: 'Chat #$chatId',
      message: updated,
      markUnread: false,
    );
  }

  Future<void> _handleDeletedMessage(Map<String, dynamic> event) async {
    var data = event;
    if (event['data'] is Map) {
      data = Map<String, dynamic>.from(event['data'] as Map);
    }
    if (data['message'] is Map) {
      data = Map<String, dynamic>.from(data['message'] as Map);
    }
    final messageId = (data['id'] ?? data['message_id'])?.toString();
    final chatId = (data['chat_head_id'] ?? data['chat_id'])?.toString();
    if (messageId == null || chatId == null) return;

    final messages = await LocalChatStorage.instance.loadMessages(chatId);
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    await LocalChatStorage.instance.saveMessage(
      deviceId: chatId,
      peerName: 'Chat #$chatId',
      message: messages[index].copyWith(
        content: 'This message was deleted',
        isDeleted: true,
      ),
      markUnread: false,
    );
  }

  Future<void> _handleReactionEvent(Map<String, dynamic> event) async {
    var data = event;
    if (event['data'] is Map) {
      data = Map<String, dynamic>.from(event['data'] as Map);
    }
    if (data['message'] is Map) {
      data = Map<String, dynamic>.from(data['message'] as Map);
    }
    final messageId = (data['id'] ?? data['message_id'])?.toString();
    final chatId = (data['chat_head_id'] ?? data['chat_id'])?.toString();
    final reaction = normalizeChatReaction(
      data['chat_react'] ?? data['reaction'],
    );
    if (messageId == null || chatId == null || reaction == null) return;

    final messages = await LocalChatStorage.instance.loadMessages(chatId);
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    await LocalChatStorage.instance.saveMessage(
      deviceId: chatId,
      peerName: 'Chat #$chatId',
      message: messages[index].copyWith(reaction: reaction),
      markUnread: false,
    );
  }

  Future<void> _handleTypingEvent(Map<String, dynamic> event) async {
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : event;
    final chatId = (data['chat_head_id'] ?? data['chat_id'])?.toString();
    if (chatId == null) return;
    final senderId = int.tryParse(
      (data['user_id'] ?? data['userId'])?.toString() ?? '',
    );
    if (senderId != null &&
        senderId == ServerApiService.instance.currentUserId) {
      return;
    }
    final typingValue = data['is_typing'] ?? data['typing'];
    final isTyping =
        typingValue == true ||
        typingValue == 1 ||
        typingValue?.toString().toLowerCase() == 'true';

    _typingTimers.remove(chatId)?.cancel();
    if (isTyping) {
      _typingChatIds.add(chatId);
    } else {
      _typingChatIds.remove(chatId);
    }
    await LocalChatStorage.instance.updateConversation(
      chatId,
      (conversation) => conversation.copyWith(isTyping: isTyping),
    );
    if (isTyping) {
      _typingTimers[chatId] = Timer(const Duration(seconds: 5), () {
        _typingTimers.remove(chatId);
        _typingChatIds.remove(chatId);
        unawaited(
          LocalChatStorage.instance.updateConversation(
            chatId,
            (conversation) => conversation.copyWith(isTyping: false),
          ),
        );
      });
    }
  }

  Future<void> _handlePresenceEvent(Map<String, dynamic> event) async {
    final data = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : event;
    final userId = int.tryParse(
      (data['user_id'] ?? data['userId'] ?? data['id'])?.toString() ?? '',
    );
    if (userId == null) return;
    final rawOnline = data['is_online'] ?? data['online'] ?? data['status'];
    final isOnline =
        rawOnline == true ||
        rawOnline == 1 ||
        rawOnline?.toString().toLowerCase() == 'online' ||
        rawOnline?.toString().toLowerCase() == 'true';

    final matchingChatIds = LocalChatStorage
        .instance
        .conversationsNotifier
        .value
        .where((conversation) => conversation.peerUserId == userId)
        .map((conversation) => conversation.id)
        .toList();
    for (final chatId in matchingChatIds) {
      await LocalChatStorage.instance.updateConversation(
        chatId,
        (conversation) => conversation.copyWith(isOnline: isOnline),
      );
    }
  }

  void _listenToSocketEvents() {
    final generation = ++_socketGeneration;
    for (final sub in _socketSubscriptions) {
      sub.cancel();
    }
    _socketSubscriptions.clear();

    // 1. New message
    _socketSubscriptions.add(
      SocketChatService.instance.onNewMessage.listen((sm) async {
        if (generation != _socketGeneration) return;
        final incomingChatId = sm.chatHeadId.toString();
        _typingTimers.remove(incomingChatId)?.cancel();
        _typingChatIds.remove(incomingChatId);
        final currentUserId = ServerApiService.instance.currentUserId;
        final isMe = currentUserId != null && sm.senderId == currentUserId;

        final plaintext = sm.decryptedContent('chat_key_${sm.chatHeadId}');

        final msg = ChatMessage(
          id: sm.id.toString(),
          senderId: isMe ? 'user' : sm.senderId.toString(),
          content: sm.isDeleted ? 'This message was deleted' : plaintext,
          timestamp:
              DateTime.tryParse(sm.createdAt)?.toLocal() ?? DateTime.now(),
          type:
              inferAttachmentType(
                fileType: sm.fileType,
                fileName: sm.fileName,
                filePath: sm.filePath,
              ) ??
              (sm.filePath != null ? 'application/octet-stream' : 'text'),
          mediaUrl: sm.filePath,
          fileName: sm.fileName,
          isRead: false,
          isEdited: sm.isEdited,
          isDeleted: sm.isDeleted,
          reaction: sm.chatReact,
          replyToId: sm.replyToId,
        );

        await LocalChatStorage.instance.saveMessage(
          deviceId: incomingChatId,
          peerName: 'User #${sm.senderId}',
          message: msg,
          markUnread: activeChatId != incomingChatId,
          clearTyping: true,
          peerUserId: isMe ? null : sm.senderId,
        );
        if (activeChatId == incomingChatId) {
          await LocalChatStorage.instance.markAsRead(incomingChatId);
        }
      }),
    );

    // 2. Message edited
    _socketSubscriptions.add(
      SocketChatService.instance.onMessageEdited.listen((event) {
        if (generation == _socketGeneration) {
          unawaited(_handleEditedMessage(event));
        }
      }),
    );

    // 3. Message deleted
    _socketSubscriptions.add(
      SocketChatService.instance.onMessageDeleted.listen((event) {
        if (generation == _socketGeneration) {
          unawaited(_handleDeletedMessage(event));
        }
      }),
    );

    _socketSubscriptions.add(
      SocketChatService.instance.onMessageReaction.listen((event) {
        if (generation == _socketGeneration) {
          unawaited(_handleReactionEvent(event));
        }
      }),
    );

    // 4. Messages read
    _socketSubscriptions.add(
      SocketChatService.instance.onRead.listen((data) async {
        if (generation != _socketGeneration) return;
        debugPrint('[SERVER CHAT] Socket messages read event: $data');
        final chatId = (data['chat_head_id'] ?? data['chat_id'])?.toString();
        if (chatId != null) {
          await LocalChatStorage.instance.markAllOutgoingMessagesAsRead(chatId);
        }
      }),
    );

    _socketSubscriptions.add(
      SocketChatService.instance.onTyping.listen((event) {
        if (generation == _socketGeneration) {
          unawaited(_handleTypingEvent(event));
        }
      }),
    );
    _socketSubscriptions.add(
      SocketChatService.instance.onPresence.listen((event) {
        if (generation == _socketGeneration) {
          unawaited(_handlePresenceEvent(event));
        }
      }),
    );
  }
}
