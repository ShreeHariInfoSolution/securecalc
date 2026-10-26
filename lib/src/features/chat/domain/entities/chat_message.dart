enum MessageStatus { sending, sent, delivered, read }

/// Domain entity representing a chat message.
class ChatMessage {
  final String id;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final String type; // 'text', 'image', 'video', 'call'
  final String? mediaUrl;
  final String? fileName;
  final bool isRead;
  final bool isDelivered;
  final String status; // 'sending', 'sent', 'delivered', 'read'
  final DateTime? deliveredAt;
  final bool isEdited;
  final bool isDeleted;
  final bool isSaved;
  final bool isForwarded;
  final int disappearType;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final String? reaction;
  final int? replyToId;
  final String? msgType;
  final int? callId;
  final String? callType;
  final String? callStatus;
  final int? callDuration;

  MessageStatus get messageStatus {
    final s = status.toLowerCase().trim();
    if (s == 'read' || isRead) return MessageStatus.read;
    if (s == 'delivered' || isDelivered) return MessageStatus.delivered;
    if (s == 'sending' || id.startsWith('local_')) return MessageStatus.sending;
    return MessageStatus.sent;
  }

  bool get hasMedia {
    final t = type.toLowerCase().trim();
    if (t == 'text' || t == 'text/plain' || t == 'call') return false;
    return mediaUrl != null && mediaUrl!.trim().isNotEmpty;
  }

  bool get isMedia => hasMedia;

  bool get isCallMessage =>
      type == 'call' ||
      msgType == 'call' ||
      callStatus != null ||
      callId != null;

  bool get isMissedCall {
    final s = (callStatus ?? '').toLowerCase().trim();
    final text = content.toLowerCase().trim();
    return s == 'missed' ||
        s == 'rejected' ||
        s == 'declined' ||
        s == 'no answer' ||
        s == 'cancelled' ||
        text.contains('missed') ||
        text.contains('declined') ||
        text.contains('no answer') ||
        text.contains('rejected');
  }

  String get previewText {
    if (isCallMessage) {
      final isVideo = (callType ?? '').toLowerCase() == 'video' ||
          content.toLowerCase().contains('video');
      final callIcon = isVideo ? '📹' : '📞';
      if (isMissedCall) {
        return '$callIcon Missed ${isVideo ? 'video' : 'voice'} call';
      }
      return '$callIcon ${content.isNotEmpty ? content : (isVideo ? 'Video call' : 'Voice call')}';
    }

    final attachmentType = type.toLowerCase().trim();
    final url = (mediaUrl ?? '').toLowerCase().trim();
    final name = (fileName ?? '').toLowerCase().trim();
    final prefix = isForwarded ? 'Forwarded: ' : '';

    final isImage = attachmentType.contains('image') ||
        attachmentType == 'photo' ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].any((ext) =>
            url.contains('.$ext') || name.endsWith('.$ext'));

    final isVideo = attachmentType.contains('video') ||
        ['mp4', 'mov', 'avi', 'mkv', 'webm'].any((ext) =>
            url.contains('.$ext') || name.endsWith('.$ext'));

    final isAudio = attachmentType.contains('audio') ||
        attachmentType.contains('voice') ||
        ['m4a', 'mp3', 'wav', 'aac', 'ogg'].any((ext) =>
            url.contains('.$ext') || name.endsWith('.$ext'));

    final isDoc = attachmentType.contains('doc') ||
        attachmentType.contains('pdf') ||
        ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'zip'].any((ext) =>
            url.contains('.$ext') || name.endsWith('.$ext'));

    final hasCustomText = content.trim().isNotEmpty &&
        content != '[Attachment]' &&
        !content.startsWith('http://') &&
        !content.startsWith('https://') &&
        !content.startsWith('uploads/') &&
        !content.startsWith('api/');

    final cleanContent = content.trim();
    final isDefaultCaption = cleanContent == 'Photo' ||
        cleanContent == 'Video' ||
        cleanContent == 'Sent a photo' ||
        cleanContent == 'Sent a video' ||
        cleanContent == 'Sent an attachment';

    if (isImage) {
      final caption = hasCustomText && !isDefaultCaption ? ': $content' : '';
      return '$prefix📷 Photo$caption';
    }

    if (isVideo) {
      final caption = hasCustomText && !isDefaultCaption ? ': $content' : '';
      return '$prefix🎥 Video$caption';
    }

    if (isAudio) {
      return '$prefix🎙️ Voice message';
    }

    if (isDoc || (url.isNotEmpty && !hasCustomText)) {
      final docName = fileName?.isNotEmpty == true
          ? fileName!
          : (url.isNotEmpty ? url.split('/').last.split('?').first : 'Document');
      return '${prefix}📄 $docName';
    }

    if (hasCustomText) {
      return '$prefix$content';
    }

    return isForwarded ? 'Forwarded message' : 'Message';
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
    this.isDelivered = false,
    this.status = 'sent',
    this.deliveredAt,
    this.isEdited = false,
    this.isDeleted = false,
    this.isSaved = false,
    this.isForwarded = false,
    this.disappearType = 0,
    this.expiresAt,
    this.updatedAt,
    this.reaction,
    this.replyToId,
    this.msgType,
    this.callId,
    this.callType,
    this.callStatus,
    this.callDuration,
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
    bool? isDelivered,
    String? status,
    DateTime? deliveredAt,
    bool? isEdited,
    bool? isDeleted,
    bool? isSaved,
    bool? isForwarded,
    int? disappearType,
    DateTime? expiresAt,
    DateTime? updatedAt,
    String? reaction,
    int? replyToId,
    String? msgType,
    int? callId,
    String? callType,
    String? callStatus,
    int? callDuration,
  }) {
    // Status can only move forward: sending (0) -> sent (1) -> delivered (2) -> read (3)
    final newStatusStr = status ?? this.status;
    final currentRank = _statusRank(this.status);
    final newRank = _statusRank(newStatusStr);
    final finalStatus = newRank >= currentRank ? newStatusStr : this.status;

    final newIsRead = isRead ?? this.isRead || finalStatus == 'read';
    final newIsDelivered = isDelivered ?? this.isDelivered || finalStatus == 'delivered' || newIsRead;

    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      fileName: fileName ?? this.fileName,
      isRead: newIsRead,
      isDelivered: newIsDelivered,
      status: finalStatus,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      isSaved: isSaved ?? this.isSaved,
      isForwarded: isForwarded ?? this.isForwarded,
      disappearType: disappearType ?? this.disappearType,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reaction: reaction ?? this.reaction,
      replyToId: replyToId ?? this.replyToId,
      msgType: msgType ?? this.msgType,
      callId: callId ?? this.callId,
      callType: callType ?? this.callType,
      callStatus: callStatus ?? this.callStatus,
      callDuration: callDuration ?? this.callDuration,
    );
  }

  static int _statusRank(String s) {
    switch (s.toLowerCase().trim()) {
      case 'read':
      case 'seen':
        return 3;
      case 'delivered':
        return 2;
      case 'sent':
        return 1;
      case 'sending':
      default:
        return 0;
    }
  }
}

/// Helper function to check if a message has expired / should disappear.
bool isMessageExpired(
  ChatMessage msg, {
  int chatDisappearType = 0,
  bool keepReadSessionMessages = false,
}) {
  if (msg.isSaved) return false;

  if (msg.expiresAt != null && DateTime.now().isAfter(msg.expiresAt!)) {
    return true;
  }

  final type = msg.disappearType > 0 ? msg.disappearType : chatDisappearType;
  final now = DateTime.now();

  if (type == 1) {
    if (msg.timestamp.add(const Duration(hours: 24)).isBefore(now)) {
      return true;
    }
  } else if (type == 2) {
    if (msg.timestamp.add(const Duration(days: 7)).isBefore(now)) {
      return true;
    }
  } else if (type == 3) {
    if (keepReadSessionMessages) return false;
    if (msg.isRead) {
      return true;
    }
  }

  return false;
}
