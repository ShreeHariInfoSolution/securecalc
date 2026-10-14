/// Domain entity representing a chat message.
class ChatMessage {
  final String id;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final String type; // 'text', 'image', 'video'
  final String? mediaUrl;
  final String? fileName;
  final bool isRead;
  final bool isEdited;
  final bool isDeleted;
  final bool isSaved;
  final int disappearType;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final String? reaction;
  final int? replyToId;

  String get previewText {
    final attachmentType = type.toLowerCase();
    if (mediaUrl == null || mediaUrl!.isEmpty) return content;
    if (attachmentType.startsWith('image/')) return 'Photo';
    if (attachmentType.startsWith('video/')) return 'Video';
    if (attachmentType.startsWith('audio/')) return 'Voice message';
    return fileName?.isNotEmpty == true ? fileName! : 'Document';
  }

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.type = 'text',
    this.mediaUrl,
    this.fileName,
    this.isRead = false,
    this.isEdited = false,
    this.isDeleted = false,
    this.isSaved = false,
    this.disappearType = 0,
    this.expiresAt,
    this.updatedAt,
    this.reaction,
    this.replyToId,
  });

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? content,
    DateTime? timestamp,
    String? type,
    String? mediaUrl,
    String? fileName,
    bool? isRead,
    bool? isEdited,
    bool? isDeleted,
    bool? isSaved,
    int? disappearType,
    DateTime? expiresAt,
    DateTime? updatedAt,
    String? reaction,
    int? replyToId,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      fileName: fileName ?? this.fileName,
      isRead: isRead ?? this.isRead,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      isSaved: isSaved ?? this.isSaved,
      disappearType: disappearType ?? this.disappearType,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reaction: reaction ?? this.reaction,
      replyToId: replyToId ?? this.replyToId,
    );
  }
}

/// Helper function to check if a message has expired / should disappear.
bool isMessageExpired(
  ChatMessage msg, {
  int chatDisappearType = 0,
  bool keepReadSessionMessages = false,
}) {
  // 1. Saved messages never expire
  if (msg.isSaved) return false;

  // 2. Deleted messages are hidden
  if (msg.isDeleted) return true;

  // 3. Explicit server expiration timestamp
  if (msg.expiresAt != null && DateTime.now().isAfter(msg.expiresAt!)) {
    return true;
  }

  // 4. Effective disappear type (message override or chat default)
  final type = msg.disappearType > 0 ? msg.disappearType : chatDisappearType;
  final now = DateTime.now();

  if (type == 1) {
    // 24 Hours
    if (msg.timestamp.add(const Duration(hours: 24)).isBefore(now)) {
      return true;
    }
  } else if (type == 2) {
    // 1 Week (7 Days)
    if (msg.timestamp.add(const Duration(days: 7)).isBefore(now)) {
      return true;
    }
  } else if (type == 3) {
    // After Read / After Seen
    // If keepReadSessionMessages is true (user actively viewing chat screen),
    // do NOT expire read messages immediately so user can read them!
    if (keepReadSessionMessages) return false;
    if (msg.isRead) {
      return true;
    }
  }

  return false;
}
