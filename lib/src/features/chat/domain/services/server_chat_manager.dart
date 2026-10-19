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

  final Set<int> _resolvingPeerIds = {};

  Future<void> _resolvePeerProfile(int userId, int chatId) async {
    if (_resolvingPeerIds.contains(userId)) return;
    _resolvingPeerIds.add(userId);
    try {
      final user = await ServerApiService.instance.getUser(userId);
      if (user != null) {
        String displayName = user.name;
        if (displayName.trim().isEmpty ||
            displayName == 'User' ||
            displayName.startsWith('User #')) {
          if (user.phone?.isNotEmpty == true) {
            displayName = user.phone!;
          } else if (user.email?.isNotEmpty == true) {
            displayName = user.email!;
          } else if (user.id > 0) {
            displayName = 'User #${user.id}';
          }
        }
        await LocalChatStorage.instance.updatePeerProfile(
          deviceId: chatId.toString(),
          displayName: displayName,
          avatarUrl: user.avatar,
        );
      }
    } catch (e) {
      debugPrint(
        '[SERVER CHAT] Resolve peer profile failed for user $userId: $e',
      );
    } finally {
      _resolvingPeerIds.remove(userId);
    }
  }

  int _syncSequence = 0;

  /// Fetches paginated chats from GET /api/chats?page={page}&limit={limit} and updates the chat list.
  Future<List<ChatConversation>> syncChats({
    int page = 1,
    int limit = 20,
    bool append = false,
  }) async {
    final currentSyncSeq = ++_syncSequence;
    final syncUserId = ServerApiService.instance.currentUserId;
    final syncToken = ServerApiService.instance.authToken;

    final ServerChatListPageModel pageRes;
    try {
      pageRes = await ServerApiService.instance.getChatsPage(
        page: page,
        limit: limit,
      );
    } catch (e) {
      debugPrint('[SERVER CHAT MANAGER] syncChats REST error: $e');
      return LocalChatStorage.instance.conversationsNotifier.value;
    }

    final serverChats = pageRes.chats;

    if (currentSyncSeq != _syncSequence ||
        syncUserId != ServerApiService.instance.currentUserId ||
        syncToken != ServerApiService.instance.authToken) {
      return LocalChatStorage.instance.conversationsNotifier.value;
    }

    // Capture the absolute latest live conversations AFTER the API request completes.
    // This includes any real-time WebSocket messages that arrived during the REST API call!
    final liveConversations =
        LocalChatStorage.instance.conversationsNotifier.value.isNotEmpty
        ? LocalChatStorage.instance.conversationsNotifier.value
        : await LocalChatStorage.instance.loadConversations();

    final liveById = {for (final conv in liveConversations) conv.id: conv};

    final newConversations = <ChatConversation>[];

    for (final sc in serverChats) {
      final chatIdStr = sc.id.toString();
      final liveLocal = liveById[chatIdStr];

      // Load cached messages for this conversation (includes live WebSocket messages)
      final cachedMessages = await LocalChatStorage.instance.loadMessages(
        chatIdStr,
      );

      if (sc.lastMessageId != null) {
        if (!cachedMessages.any((m) => m.id == sc.lastMessageId.toString())) {
          await LocalChatStorage.instance.markHistoryIncomplete(chatIdStr);
        }
      }

      final currentUserId = pageRes.viewerId > 0
          ? pageRes.viewerId
          : ServerApiService.instance.currentUserId;
      final otherMembers = sc.members
          .where((member) => member.id != currentUserId)
          .toList();
      final peer = otherMembers.isNotEmpty
          ? otherMembers.first
          : (sc.members.isNotEmpty ? sc.members.first : null);

      // Determine peer display name: PRESERVE valid non-generic name from local if API gives generic
      String peerDisplayName = peer?.name ?? '';
      final isApiPeerGeneric =
          peerDisplayName.trim().isEmpty ||
          peerDisplayName == 'User' ||
          peerDisplayName.startsWith('User #');

      if (isApiPeerGeneric && liveLocal != null) {
        final localName = liveLocal.name;
        if (localName.isNotEmpty &&
            !localName.startsWith('User #') &&
            !localName.startsWith('Chat #') &&
            localName != 'User') {
          peerDisplayName = localName;
        }
      }

      if (peerDisplayName.trim().isEmpty || peerDisplayName == 'User') {
        if (peer != null && peer.phone?.isNotEmpty == true) {
          peerDisplayName = peer.phone!;
        } else if (peer != null && peer.email?.isNotEmpty == true) {
          peerDisplayName = peer.email!;
        } else if (peer != null && peer.id > 0) {
          peerDisplayName = 'User #${peer.id}';
        } else {
          peerDisplayName = 'User';
        }
      }

      // Trigger background profile resolution if peer display name is generic or avatar is missing
      if (peer != null &&
          peer.id > 0 &&
          (peerDisplayName.startsWith('User #') ||
              peerDisplayName == 'User' ||
              peer.avatar == null ||
              peer.avatar!.isEmpty)) {
        unawaited(_resolvePeerProfile(peer.id, sc.id));
      }

      final name = sc.isGroup
          ? ((sc.groupName != null && sc.groupName!.isNotEmpty)
                ? sc.groupName!
                : (liveLocal?.name.isNotEmpty == true &&
                          !liveLocal!.name.startsWith('Chat #')
                      ? liveLocal.name
                      : 'Group chat'))
          : (peer != null
                ? peerDisplayName
                : (liveLocal?.name.isNotEmpty == true
                      ? liveLocal!.name
                      : (sc.groupName ?? 'Chat #${sc.id}')));

      final avatar = sc.isGroup
          ? (sc.groupAvatar?.isNotEmpty == true
                ? sc.groupAvatar!
                : (liveLocal?.avatarUrl ?? ''))
          : (peer?.avatar?.isNotEmpty == true
                ? peer!.avatar!
                : (liveLocal?.avatarUrl.isNotEmpty == true
                      ? liveLocal!.avatarUrl
                      : (sc.groupAvatar ?? '')));

      // Compare message timestamps to determine whether WebSocket / Local state is newer than API snapshot
      final newestCachedMessage = cachedMessages.isEmpty
          ? null
          : cachedMessages.last;
      final serverLastMessageTime = DateTime.tryParse(
        sc.lastMessageCreatedAt ?? sc.updatedAt ?? '',
      )?.toLocal();

      final localActivityTime =
          newestCachedMessage?.timestamp ?? liveLocal?.lastActivityAt;

      final bool isLocalStateNewer =
          localActivityTime != null &&
          (serverLastMessageTime == null ||
              localActivityTime.isAfter(serverLastMessageTime) ||
              localActivityTime.isAtSameMomentAs(serverLastMessageTime));

      // Determine last message text (Prioritize real-time WebSocket message text)
      String lastMsgText;
      if (isLocalStateNewer &&
          liveLocal != null &&
          liveLocal.lastMessage.isNotEmpty) {
        lastMsgText = liveLocal.lastMessage;
      } else {
        var apiText = sc.lastMessage ?? sc.lastMessageCiphertext ?? '';
        if (apiText.isEmpty && sc.lastMessageFilePath != null) {
          apiText = sc.lastMessageFileName ?? 'Attachment';
        } else if (apiText.isNotEmpty) {
          apiText = E2eCryptoService.instance.decryptText(
            apiText,
            'chat_key_${sc.id}',
          );
        }
        if (apiText.isEmpty) {
          apiText = newestCachedMessage?.previewText.isNotEmpty == true
              ? newestCachedMessage!.previewText
              : 'No messages yet';
        }
        lastMsgText = apiText;
      }

      // Determine timestamp
      final DateTime? finalLastActivityAt = isLocalStateNewer
          ? localActivityTime
          : (serverLastMessageTime ?? liveLocal?.lastActivityAt);

      final String finalLastMessageTimeStr = isLocalStateNewer
          ? (newestCachedMessage != null
                ? _formatChatTime(
                    newestCachedMessage.timestamp.toIso8601String(),
                  )
                : (liveLocal?.lastMessageTime ??
                      _formatChatTime(sc.lastMessageCreatedAt ?? sc.updatedAt)))
          : _formatChatTime(sc.lastMessageCreatedAt ?? sc.updatedAt);

      // Determine unread count (prioritize WebSocket updates)
      int finalUnreadCount;
      if (activeChatId == chatIdStr) {
        finalUnreadCount = 0;
      } else if (isLocalStateNewer && liveLocal != null) {
        finalUnreadCount = liveLocal.unreadCount > sc.unreadCount
            ? liveLocal.unreadCount
            : sc.unreadCount;
      } else {
        finalUnreadCount = sc.unreadCount;
      }

      // Transient WebSocket states (typing / presence / pin / mute / archive)
      final isOnline = peer?.isOnline == true || (liveLocal?.isOnline ?? false);
      final peerLastSeen = peer?.lastSeenAt != null
          ? DateTime.tryParse(peer!.lastSeenAt!)?.toLocal()
          : null;
      final lastSeenAt = peerLastSeen ?? liveLocal?.lastSeenAt;

      final isTyping =
          _typingChatIds.contains(chatIdStr) || (liveLocal?.isTyping ?? false);
      final isPinned = liveLocal?.isPinned ?? false;
      final isMuted = liveLocal?.isMuted ?? false;
      final isArchived = liveLocal?.isArchived ?? false;

      final conversation = ChatConversation(
        id: chatIdStr,
        name: name,
        avatarUrl: avatar,
        lastMessage: lastMsgText,
        lastMessageTime: finalLastMessageTimeStr,
        lastActivityAt: finalLastActivityAt,
        unreadCount: finalUnreadCount,
        isOnline: isOnline,
        lastSeenAt: lastSeenAt,
        isTyping: isTyping,
        peerUserId: sc.isGroup ? null : peer?.id,
        isGroup: sc.isGroup,
        disappearType: sc.disappearType,
        memberNames: {for (final member in sc.members) member.id: member.name},
        isPinned: isPinned,
        isMuted: isMuted,
        isArchived: isArchived,
        backgroundUrl: sc.backgroundUrl,
        messages: cachedMessages,
      );

      newConversations.add(conversation);
    }

    if (currentSyncSeq != _syncSequence ||
        syncUserId != ServerApiService.instance.currentUserId ||
        syncToken != ServerApiService.instance.authToken) {
      return LocalChatStorage.instance.conversationsNotifier.value;
    }

    // Combine all live local/WebSocket conversations with the updated API conversations
    // so no conversation is ever lost!
    final mergedMap = <String, ChatConversation>{
      for (final c in liveConversations) c.id: c,
    };

    for (final c in newConversations) {
      mergedMap[c.id] = c;
    }

    final finalConversations = mergedMap.values.toList();

    // Sort by lastActivityAt descending
    finalConversations.sort((a, b) {
      final aTime = a.lastActivityAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.lastActivityAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    await LocalChatStorage.instance.replaceConversations(finalConversations);

    return finalConversations;
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

  /// Loads a single page of message history
  Future<PaginatedMessagesResult> loadMessagesPage(
    String chatId, {
    int page = 1,
    int limit = 20,
    int chatDisappearType = 0,
    bool keepReadSessionMessages = false,
  }) async {
    final requestUserId = ServerApiService.instance.currentUserId;
    final requestToken = ServerApiService.instance.authToken;
    final numericId = int.tryParse(chatId) ?? 0;
    if (numericId <= 0) {
      final cached = await LocalChatStorage.instance.loadMessages(
        chatId,
        chatDisappearType: chatDisappearType,
        keepReadSessionMessages: keepReadSessionMessages,
      );
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
        final cached = await LocalChatStorage.instance.loadMessages(
          chatId,
          chatDisappearType: chatDisappearType,
          keepReadSessionMessages: keepReadSessionMessages,
        );
        return PaginatedMessagesResult(
          messages: cached,
          page: 1,
          totalPages: 1,
          total: cached.length,
          hasMore: false,
        );
      }

      final cachedMessages = await LocalChatStorage.instance.loadMessages(
        chatId,
        chatDisappearType: chatDisappearType,
        keepReadSessionMessages: keepReadSessionMessages,
      );
      final cachedById = {
        for (final message in cachedMessages) message.id: message,
      };
      final currentUserId = ServerApiService.instance.currentUserId;

      final messages = <ChatMessage>[];
      for (final sm in pageRes.messages) {
        final isMe = currentUserId != null && sm.senderId == currentUserId;
        final targetChatId = sm.chatHeadId > 0 ? sm.chatHeadId : numericId;
        final plaintext = sm.decryptedContent('chat_key_$targetChatId');

        DateTime ts;
        try {
          ts = DateTime.parse(sm.createdAt).toLocal();
        } catch (_) {
          ts = DateTime.now();
        }

        final cachedMessage = cachedById[sm.id.toString()];
        final msg = ChatMessage(
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
              (sm.filePath != null && sm.filePath!.trim().isNotEmpty
                  ? 'application/octet-stream'
                  : cachedMessage?.type ?? 'text'),
          mediaUrl: (sm.filePath != null && sm.filePath!.trim().isNotEmpty)
              ? sm.filePath
              : cachedMessage?.mediaUrl,
          fileName: (sm.fileName != null && sm.fileName!.trim().isNotEmpty)
              ? sm.fileName
              : cachedMessage?.fileName,
          isRead: isMe ? (sm.isRead || cachedMessage?.isRead == true) : true,
          isDelivered: isMe
              ? (sm.isDelivered ||
                    sm.isRead ||
                    cachedMessage?.isDelivered == true ||
                    cachedMessage?.isRead == true)
              : true,
          isEdited: sm.isEdited,
          isDeleted: sm.isDeleted,
          isSaved: sm.isSaved,
          disappearType: sm.disappearType,
          expiresAt: DateTime.tryParse(sm.expiresAt ?? ''),
          updatedAt: DateTime.tryParse(sm.updatedAt ?? ''),
          reaction: sm.chatReact,
          replyToId: sm.replyToId,
        );

        if (!isMessageExpired(
          msg,
          chatDisappearType: chatDisappearType,
          keepReadSessionMessages: keepReadSessionMessages,
        )) {
          messages.add(msg);
        }
      }

      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final mergedById = {
        for (final message in cachedMessages)
          if (!isMessageExpired(
            message,
            chatDisappearType: chatDisappearType,
            keepReadSessionMessages: keepReadSessionMessages,
          ))
            message.id: message,
      };
      for (final message in messages) {
        mergedById[message.id] = message;
      }
      final mergedAll =
          mergedById.values
              .where(
                (m) => !isMessageExpired(
                  m,
                  chatDisappearType: chatDisappearType,
                  keepReadSessionMessages: keepReadSessionMessages,
                ),
              )
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      await LocalChatStorage.instance.cacheMessages(
        chatId,
        mergedAll,
        chatDisappearType: chatDisappearType,
        keepReadSessionMessages: keepReadSessionMessages,
      );

      return PaginatedMessagesResult(
        messages: messages,
        page: pageRes.page,
        totalPages: pageRes.totalPages,
        total: pageRes.total,
        hasMore: pageRes.hasMore,
      );
    } catch (e) {
      debugPrint('[ServerChatManager] Page $page load failed for $chatId: $e');
      final cached = await LocalChatStorage.instance.loadMessages(
        chatId,
        chatDisappearType: chatDisappearType,
        keepReadSessionMessages: keepReadSessionMessages,
      );
      return PaginatedMessagesResult(
        messages: cached,
        page: page,
        totalPages: page,
        total: cached.length,
        hasMore: false,
      );
    }
  }

  /// Loads latest message page
  Future<List<ChatMessage>> loadMessages(String chatId) async {
    final res = await loadMessagesPage(chatId, page: 1, limit: 20);
    return res.messages;
  }

  /// Sends a new message via REST API and Socket.IO
  Future<bool> sendMessage({
    required String chatId,
    required String peerName,
    required String text,
    File? file,
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

    // Persist via REST API (single authoritative source of truth for message creation)
    if (numericId > 0) {
      try {
        serverMessage = await ServerApiService.instance.sendMessageREST(
          chatId: numericId,
          message: encryptedText,
          file: file,
          filePath: filePath,
          fileName: fileName,
          fileType: fileType,
          replyToId: replyToId,
          clientId: clientId,
        );
      } catch (e) {
        debugPrint('[SERVER CHAT] Send Message REST Error: $e');
        // Fallback to Socket.IO ONLY if REST fails and socket is connected
        if (SocketChatService.instance.isConnected) {
          try {
            await SocketChatService.instance.sendMessage(
              chatId: numericId,
              message: encryptedText,
              filePath: filePath,
              fileName: fileName,
              fileType: fileType,
              replyToId: replyToId,
              clientId: clientId,
            );
          } catch (_) {
            return false;
          }
        } else {
          return false;
        }
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
      isDelivered: serverMessage != null,
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

    unawaited(syncChats());

    return true;
  }

  /// Marks a chat as read via Socket.IO & REST API
  Future<void> markChatRead(String chatId) async {
    final numericId = int.tryParse(chatId) ?? 0;
    if (numericId > 0) {
      if (SocketChatService.instance.isConnected) {
        SocketChatService.instance.markRead(chatHeadId: numericId);
      }
      unawaited(ServerApiService.instance.markChatRead(numericId));
    }
    await LocalChatStorage.instance.markAsRead(chatId);
  }

  /// Resolves server chat metadata (peer name, avatar, members) when a new chat event arrives.
  Future<void> _resolveChatDetailsAndSync(int chatId) async {
    final chatIdStr = chatId.toString();
    try {
      final details = await ServerApiService.instance.getChatDetails(chatId);
      if (details != null) {
        final currentUserId = ServerApiService.instance.currentUserId;
        final otherMembers = details.members
            .where((member) => member.id != currentUserId)
            .toList();
        final peer = otherMembers.isNotEmpty
            ? otherMembers.first
            : (details.members.isNotEmpty ? details.members.first : null);

        final name = details.isGroup
            ? (details.groupName ?? 'Group chat')
            : (peer?.name ?? 'User #$chatId');
        final avatar = details.isGroup
            ? (details.groupAvatar ?? '')
            : (peer?.avatar ?? details.groupAvatar ?? '');

        await LocalChatStorage.instance.updatePeerProfile(
          deviceId: chatIdStr,
          displayName: name,
          avatarUrl: avatar,
        );
      }
    } catch (e) {
      debugPrint('[SERVER CHAT] Resolve details failed for $chatId: $e');
    }
    unawaited(syncChats());
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
    final chatId =
        (data['chat_head_id'] ??
                data['chat_id'] ??
                data['chatHeadId'] ??
                data['chatId'] ??
                event['chat_head_id'] ??
                event['chat_id'])
            ?.toString();
    final rawValue = data['ciphertext'] ?? data['content'] ?? data['message'];
    final rawText = rawValue is String ? rawValue : null;
    if (messageId == null || chatId == null || rawText == null) return;

    final decryptedText = E2eCryptoService.instance.decryptText(
      rawText,
      'chat_key_$chatId',
    );
    // A failed encrypted decode returns the original ciphertext. Keeping the
    // previous local plaintext is safer than persisting ciphertext to disk.
    if (rawText.startsWith('ENC:v1:') && decryptedText == rawText) return;

    final messages = await LocalChatStorage.instance.loadMessages(chatId);
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return;

    final updated = messages[index].copyWith(
      content: decryptedText,
      isEdited: true,
    );
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
    final messageId = (data['id'] ?? data['message_id'] ?? data['messageId'])
        ?.toString();
    final chatId =
        (data['chat_head_id'] ??
                data['chat_id'] ??
                data['chatHeadId'] ??
                data['chatId'])
            ?.toString();
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
    final messageId = (data['id'] ?? data['message_id'] ?? data['messageId'])
        ?.toString();
    final chatId =
        (data['chat_head_id'] ??
                data['chat_id'] ??
                data['chatHeadId'] ??
                data['chatId'])
            ?.toString();
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
    final chatId =
        (data['chat_head_id'] ??
                data['chat_id'] ??
                data['chatHeadId'] ??
                data['chatId'])
            ?.toString();
    if (chatId == null) return;
    final senderId = int.tryParse(
      (data['user_id'] ??
                  data['userId'] ??
                  data['sender_id'] ??
                  data['senderId'])
              ?.toString() ??
          '',
    );
    if (senderId != null &&
        senderId == ServerApiService.instance.currentUserId) {
      return;
    }
    final typingValue = data['is_typing'] ?? data['typing'] ?? data['isTyping'];
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

    final existingList = LocalChatStorage.instance.conversationsNotifier.value;
    final exists = existingList.any((c) => c.id == chatId);
    if (exists) {
      await LocalChatStorage.instance.updateConversation(
        chatId,
        (conversation) => conversation.copyWith(isTyping: isTyping),
      );
    } else if (isTyping) {
      unawaited(_resolveChatDetailsAndSync(int.parse(chatId)));
    }

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
    final chatHeadId =
        (data['chat_head_id'] ?? data['chat_id'] ?? data['chatHeadId'])
            ?.toString();

    final rawOnline = data['is_online'] ?? data['online'] ?? data['status'];
    if (rawOnline == null) return;

    final isOnline =
        rawOnline == true ||
        rawOnline == 1 ||
        rawOnline.toString().toLowerCase() == 'online' ||
        rawOnline.toString().toLowerCase() == 'true';

    final rawLastSeen =
        data['last_seen_at'] ?? data['lastSeenAt'] ?? data['updated_at'];
    final parsedLastSeen =
        rawLastSeen != null
            ? DateTime.tryParse(rawLastSeen.toString())?.toLocal()
            : null;

    final conversations = LocalChatStorage.instance.conversationsNotifier.value;
    final matchingChatIds = <String>{};

    if (userId != null && userId > 0) {
      for (final c in conversations) {
        if (c.peerUserId == userId) matchingChatIds.add(c.id);
      }
    }
    if (chatHeadId != null && chatHeadId.isNotEmpty && chatHeadId != '0') {
      matchingChatIds.add(chatHeadId);
    }

    for (final chatId in matchingChatIds) {
      await LocalChatStorage.instance.updateConversation(
        chatId,
        (conversation) => conversation.copyWith(
          isOnline: isOnline,
          lastSeenAt:
              isOnline
                  ? null
                  : (parsedLastSeen ?? conversation.lastSeenAt ?? DateTime.now()),
        ),
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

        // Safety check: Ignore malformed socket message events that carry no valid message id, content, or media
        if (sm.id <= 0 ||
            (!sm.isDeleted &&
                plaintext.trim().isEmpty &&
                (sm.filePath == null || sm.filePath!.trim().isEmpty))) {
          debugPrint(
            '[SERVER CHAT] Ignoring malformed socket new_message event with empty content for id=${sm.id}',
          );
          return;
        }

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
              (sm.filePath != null && sm.filePath!.trim().isNotEmpty
                  ? 'application/octet-stream'
                  : 'text'),
          mediaUrl: (sm.filePath != null && sm.filePath!.trim().isNotEmpty)
              ? sm.filePath
              : null,
          fileName: (sm.fileName != null && sm.fileName!.trim().isNotEmpty)
              ? sm.fileName
              : null,
          isRead: isMe ? sm.isRead : false,
          isDelivered: true,
          isEdited: sm.isEdited,
          isDeleted: sm.isDeleted,
          isSaved: sm.isSaved,
          disappearType: sm.disappearType,
          expiresAt: DateTime.tryParse(sm.expiresAt ?? ''),
          updatedAt: DateTime.tryParse(sm.updatedAt ?? ''),
          reaction: sm.chatReact,
          replyToId: sm.replyToId,
        );

        final conversations =
            LocalChatStorage.instance.conversationsNotifier.value;
        final existing = conversations.cast<ChatConversation?>().firstWhere(
          (c) => c?.id == incomingChatId,
          orElse: () => null,
        );

        final peerName =
            existing != null &&
                !existing.name.startsWith('User #') &&
                !existing.name.startsWith('Chat #')
            ? existing.name
            : 'User #${sm.senderId}';

        await LocalChatStorage.instance.saveMessage(
          deviceId: incomingChatId,
          peerName: peerName,
          message: msg,
          markUnread: activeChatId != incomingChatId,
          clearTyping: true,
          peerUserId: isMe ? null : sm.senderId,
        );

        if (activeChatId == incomingChatId) {
          await LocalChatStorage.instance.markAsRead(incomingChatId);
        }

        // If thread is brand new or has placeholder name, resolve chat details in background
        if (existing == null ||
            existing.name.startsWith('User #') ||
            existing.name.startsWith('Chat #')) {
          unawaited(_resolveChatDetailsAndSync(sm.chatHeadId));
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

    // 3b. Message Saved
    _socketSubscriptions.add(
      SocketChatService.instance.onMessageSaved.listen((event) async {
        if (generation != _socketGeneration) return;
        debugPrint('[SERVER CHAT] Socket message saved event: $event');
        final chatId =
            (event['chat_head_id'] ?? event['chatHeadId'] ?? event['chat_id'])
                ?.toString();
        final messageId =
            (event['message_id'] ?? event['messageId'] ?? event['id'])
                ?.toString();
        final isSaved =
            event['is_saved'] == true ||
            event['isSaved'] == true ||
            event['is_saved'] == 1;

        if (chatId != null && messageId != null) {
          final messages =
              await LocalChatStorage.instance.loadMessages(chatId);
          final index = messages.indexWhere((m) => m.id == messageId);
          if (index >= 0) {
            final updatedMsg = messages[index].copyWith(isSaved: isSaved);
            final conversations =
                LocalChatStorage.instance.conversationsNotifier.value;
            final existing =
                conversations.cast<ChatConversation?>().firstWhere(
                      (c) => c?.id == chatId,
                      orElse: () => null,
                    );
            await LocalChatStorage.instance.saveMessage(
              deviceId: chatId,
              peerName: existing?.name ?? 'Chat #$chatId',
              message: updatedMsg,
              markUnread: false,
            );
          }
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
        final chatId =
            (data['chat_head_id'] ??
                    data['chat_id'] ??
                    data['chatHeadId'] ??
                    data['chatId'])
                ?.toString();
        final readerId = int.tryParse(
          (data['user_id'] ?? data['userId'] ?? '').toString(),
        );
        final currentUserId = ServerApiService.instance.currentUserId;
        if (chatId == null || currentUserId == null) return;
        if (readerId != null && readerId == currentUserId) return;

        final lastReadAt = DateTime.tryParse(
          (data['last_read_at'] ?? data['lastReadAt'] ?? '').toString(),
        );
        await LocalChatStorage.instance.markAllOutgoingMessagesAsRead(
          chatId,
          readThrough: lastReadAt,
        );
      }),
    );

    // 4b. Messages delivered
    _socketSubscriptions.add(
      SocketChatService.instance.onDelivered.listen((data) async {
        if (generation != _socketGeneration) return;
        debugPrint('[SERVER CHAT] Socket messages delivered event: $data');
        final chatId =
            (data['chat_head_id'] ??
                    data['chat_id'] ??
                    data['chatHeadId'] ??
                    data['chatId'])
                ?.toString();
        if (chatId != null) {
          await LocalChatStorage.instance.markAllOutgoingMessagesAsDelivered(
            chatId,
          );
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
