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
      reaction: reaction ?? this.reaction,
      replyToId: replyToId ?? this.replyToId,
    );
  }
}
