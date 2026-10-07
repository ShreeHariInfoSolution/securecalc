import 'chat_message.dart';

class ChatConversation {
  final String id;
  final String name;
  final String avatarUrl;
  final String lastMessage;
  final String lastMessageTime;
  final DateTime? lastActivityAt;
  final int unreadCount;
  final bool isOnline;
  final bool isTyping;
  final int? peerUserId;
  final bool isGroup;
  final Map<int, String> memberNames;
  final bool isPinned;
  final bool isMuted;
  final List<ChatMessage> messages;

  const ChatConversation({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.lastMessage,
    required this.lastMessageTime,
    this.lastActivityAt,
    this.unreadCount = 0,
    this.isOnline = false,
    this.isTyping = false,
    this.peerUserId,
    this.isGroup = false,
    this.memberNames = const {},
    this.isPinned = false,
    this.isMuted = false,
    required this.messages,
  });

  ChatConversation copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? lastMessage,
    String? lastMessageTime,
    DateTime? lastActivityAt,
    int? unreadCount,
    bool? isOnline,
    bool? isTyping,
    int? peerUserId,
    bool? isGroup,
    Map<int, String>? memberNames,
    bool? isPinned,
    bool? isMuted,
    List<ChatMessage>? messages,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      isTyping: isTyping ?? this.isTyping,
      peerUserId: peerUserId ?? this.peerUserId,
      isGroup: isGroup ?? this.isGroup,
      memberNames: memberNames ?? this.memberNames,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      messages: messages ?? this.messages,
    );
  }
}
