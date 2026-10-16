import '../entities/chat_conversation.dart';
import '../models/server_models.dart';
import 'local_chat_storage.dart';
import 'server_api_service.dart';
import 'server_chat_manager.dart';

/// The single QR/link/text format accepted when starting a direct chat.
class ChatInvite {
  static String forUser(int userId) =>
      'securecalc://chat?target_id=$userId&v=1';

  /// Accepts the app link, its HTTPS fallback, or a plain numeric user ID.
  static int? targetUserIdFrom(String value) {
    final input = value.trim();
    if (input.isEmpty) return null;
    final bareId = int.tryParse(input);
    if (bareId != null && bareId > 0) return bareId;

    final uri = Uri.tryParse(input);
    if (uri == null) return null;
    final isAppLink = uri.scheme == 'securecalc' && uri.host == 'chat';
    final isFallbackLink =
        uri.scheme == 'https' && uri.host == 'realragnardev-dotcom.github.io';
    if (!isAppLink && !isFallbackLink) return null;
    final targetId = int.tryParse(uri.queryParameters['target_id'] ?? '');
    return targetId != null && targetId > 0 ? targetId : null;
  }
}

/// Creates a direct server chat and returns the canonical local conversation.
/// All entry points (search, QR scan, pasted code, and app link) should use it.
class DirectChatStarter {
  DirectChatStarter._();
  static final instance = DirectChatStarter._();

  Future<ChatConversation> start(int targetUserId) async {
    final currentUserId = ServerApiService.instance.currentUserId;
    if (currentUserId == null || ServerApiService.instance.authToken == null) {
      throw StateError('Please unlock the vault before starting a chat.');
    }
    if (targetUserId == currentUserId) {
      throw ArgumentError('You cannot start a chat with your own profile.');
    }

    final UserModel? targetUser = await ServerApiService.instance.getUser(
      targetUserId,
    );
    final serverChat = await ServerApiService.instance.createDirectChat(
      targetUserId,
    );
    if (serverChat.id <= 0) {
      throw StateError('The server did not return a valid chat ID.');
    }

    final chats = await ServerChatManager.instance.syncChats();
    for (final chat in chats) {
      if (chat.id == serverChat.id.toString()) return chat;
    }

    // The list endpoint can lag just after creation. Keep the new thread usable.
    final displayName = targetUser?.name ?? serverChat.groupName ?? 'Contact';
    final avatar = targetUser?.avatar ?? serverChat.groupAvatar ?? '';
    await LocalChatStorage.instance.createOrGetConversation(
      deviceId: serverChat.id.toString(),
      displayName: displayName,
      avatarUrl: avatar,
      peerUserId: targetUserId,
    );
    final cached = await LocalChatStorage.instance.loadConversations();
    return cached.firstWhere(
      (chat) => chat.id == serverChat.id.toString(),
      orElse: () => ChatConversation(
        id: serverChat.id.toString(),
        name: displayName,
        avatarUrl: avatar,
        lastMessage: 'Tap to start thread',
        lastMessageTime: 'Just now',
        peerUserId: targetUserId,
        messages: const [],
      ),
    );
  }
}
