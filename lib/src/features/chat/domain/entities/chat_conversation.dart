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
  final DateTime? lastSeenAt;
  final bool isTyping;
  final int? peerUserId;
  final bool isGroup;
  final int disappearType;
  final Map<int, String> memberNames;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final String? backgroundUrl;
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
    this.lastSeenAt,
    this.isTyping = false,
    this.peerUserId,
    this.isGroup = false,
    this.disappearType = 0,
    this.memberNames = const {},
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.backgroundUrl,
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
    DateTime? lastSeenAt,
    bool? isTyping,
    int? peerUserId,
    bool? isGroup,
    int? disappearType,
    Map<int, String>? memberNames,
    bool? isPinned,
    bool? isMuted,
    bool? isArchived,
    String? backgroundUrl,
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
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isTyping: isTyping ?? this.isTyping,
      peerUserId: peerUserId ?? this.peerUserId,
      isGroup: isGroup ?? this.isGroup,
      disappearType: disappearType ?? this.disappearType,
      memberNames: memberNames ?? this.memberNames,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isArchived: isArchived ?? this.isArchived,
      backgroundUrl: backgroundUrl ?? this.backgroundUrl,
      messages: messages ?? this.messages,
    );
  }
}
