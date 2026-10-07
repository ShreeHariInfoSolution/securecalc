
import 'dart:convert';
import '../services/e2e_crypto_service.dart';

/// The API stores `chat_react` as JSON text and may return a quoted JSON
/// string (for example, `"\"👍\""`). Convert it back to the emoji for UI.
String? normalizeChatReaction(dynamic value) {
  if (value == null) return null;
  var reaction = value.toString();
  for (var i = 0; i < 2; i++) {
    try {
      final decoded = jsonDecode(reaction);
      if (decoded is! String) break;
      reaction = decoded;
    } on FormatException {
      break;
    }
  }
  return reaction.isEmpty ? null : reaction;
}

String? inferAttachmentType({
  String? fileType,
  String? fileName,
  String? filePath,
}) {
  if (fileType != null && fileType.isNotEmpty) return fileType.toLowerCase();
  final source = fileName?.isNotEmpty == true ? fileName! : filePath ?? '';
  final extension = source.split('?').first.split('#').first.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'wav' => 'audio/wav',
    'ogg' || 'opus' => 'audio/ogg',
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt' => 'text/plain',
    'zip' => 'application/zip',
    _ => null,
  };
}

/// Represents a registered user on the calculatorchat server.
class UserModel {
  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? publicKey;
  final String? avatar;
  final String? role;
  final String? encryptedPrivateKey;
  final String? keySalt;
  final String? keyIv;
  final bool isOnline;
  final String? lastSeenAt;

  UserModel({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.publicKey,
    this.avatar,
    this.role,
    this.encryptedPrivateKey,
    this.keySalt,
    this.keyIv,
    this.isOnline = false,
    this.lastSeenAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] is int ? json['id'] : int.tryParse(json['id'].toString()) ?? 0,
      name: json['name'] ?? 'User',
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      publicKey: json['public_key']?.toString(),
      avatar: json['avatar']?.toString(),
      role: json['role']?.toString(),
      encryptedPrivateKey: json['encrypted_private_key']?.toString(),
      keySalt: json['key_salt']?.toString(),
      keyIv: json['key_iv']?.toString(),
      isOnline: json['is_online'] == true || json['is_online'] == 1,
      lastSeenAt: json['last_seen_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'public_key': publicKey,
      'avatar': avatar,
      'encrypted_private_key': encryptedPrivateKey,
      'key_salt': keySalt,
      'key_iv': keyIv,
      'is_online': isOnline,
      'last_seen_at': lastSeenAt,
    };
  }
}

class UserListPageModel {
  final List<UserModel> users;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  const UserListPageModel({
    required this.users,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });
}

/// Represents a 1-to-1 or group Chat Head on the server.
class ServerChatModel {
  final int id;
  final String? groupName;
  final String? groupAvatar;
  final bool isGroup;
  final String? lastMessageCiphertext;
  final String? lastMessage;
  final String? lastMessageFilePath;
  final String? lastMessageFileName;
  final int? lastMessageId;
  final int? lastMessageSenderId;
  final String? lastMessageCreatedAt;
  final int unreadCount;
  final List<UserModel> members;
  final String? updatedAt;
  final String? createdAt;
  final int? createdBy;
  final int? totalMembers;

  ServerChatModel({
    required this.id,
    this.groupName,
    this.groupAvatar,
    this.isGroup = false,
    this.lastMessageCiphertext,
    this.lastMessage,
    this.lastMessageFilePath,
    this.lastMessageFileName,
    this.lastMessageId,
    this.lastMessageSenderId,
    this.lastMessageCreatedAt,
    this.unreadCount = 0,
    required this.members,
    this.updatedAt,
    this.createdAt,
    this.createdBy,
    this.totalMembers,
  });

  factory ServerChatModel.fromJson(Map<String, dynamic> json) {
    List<UserModel> membersList = [];
    if (json['members'] != null && json['members'] is List) {
      membersList = (json['members'] as List)
          .map((m) => UserModel.fromJson(m is Map<String, dynamic> ? m : {}))
          .toList();
    }

    final lastMessageJson = json['last_message'] is Map
        ? Map<String, dynamic>.from(json['last_message'] as Map)
        : <String, dynamic>{};
    final rawLastMessage = json['last_message'];
    return ServerChatModel(
      id: (json['id'] ?? json['chat_head_id']) is int
          ? (json['id'] ?? json['chat_head_id']) as int
          : int.tryParse(
                (json['id'] ?? json['chat_head_id'])?.toString() ?? '',
              ) ??
              0,
      groupName: json['group_name']?.toString(),
      groupAvatar: json['group_avatar']?.toString(),
      isGroup: json['is_group'] == true || json['is_group'] == 1,
      lastMessageCiphertext: lastMessageJson['ciphertext']?.toString() ??
          json['last_message_ciphertext']?.toString(),
      lastMessage: lastMessageJson['message']?.toString() ??
          (rawLastMessage is String ? rawLastMessage : null),
      lastMessageFilePath: lastMessageJson['file_path']?.toString(),
      lastMessageFileName: lastMessageJson['file_name']?.toString(),
      lastMessageId: int.tryParse(lastMessageJson['id']?.toString() ?? ''),
      lastMessageSenderId: int.tryParse(lastMessageJson['sender_id']?.toString() ?? ''),
      lastMessageCreatedAt: lastMessageJson['created_at']?.toString(),
      unreadCount: json['unread'] is int ? json['unread'] : int.tryParse(json['unread']?.toString() ?? '0') ?? 0,
      members: membersList,
      updatedAt: json['updated_at']?.toString(),
      createdAt: json['created_at']?.toString(),
      createdBy: json['created_by'] is int
          ? json['created_by']
          : int.tryParse(json['created_by']?.toString() ?? ''),
      totalMembers: json['total_members'] is int
          ? json['total_members']
          : int.tryParse(json['total_members']?.toString() ?? ''),
    );
  }
}

/// Represents an encrypted message on the server.
class ServerMessageModel {
  final int id;
  final int chatHeadId;
  final int senderId;
  final String ciphertext;
  final String? message;
  final int keyVersion;
  final String? filePath;
  final String? fileType;
  final String? fileName;
  final int? replyToId;
  final String? chatReact;
  final bool isEdited;
  final bool isDeleted;
  final String createdAt;

  ServerMessageModel({
    required this.id,
    required this.chatHeadId,
    required this.senderId,
    required this.ciphertext,
    this.message,
    this.keyVersion = 1,
    this.filePath,
    this.fileType,
    this.fileName,
    this.replyToId,
    this.chatReact,
    this.isEdited = false,
    this.isDeleted = false,
    required this.createdAt,
  });

  factory ServerMessageModel.fromJson(Map<String, dynamic> json) {
    // `message` and `text` are plaintext API/socket fields. Only decrypt the
    // dedicated `ciphertext` field so plain text that resembles base64 stays
    // readable as-is.
    final messageStr = (json['message'] ?? json['text'])?.toString();
    final cipherStr = json['ciphertext']?.toString();
    final rawId = json['id'] ?? json['message_id'] ?? json['messageId'];
    final rawSenderId = json['sender_id'] ?? json['senderId'];
    return ServerMessageModel(
      id: rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0,
      chatHeadId: json['chat_head_id'] is int
          ? json['chat_head_id']
          : int.tryParse(
                (json['chat_head_id'] ?? json['chat_id'] ?? json['chatHeadId'])
                        ?.toString() ??
                    '0',
              ) ??
              0,
      senderId: rawSenderId is int
          ? rawSenderId
          : int.tryParse(rawSenderId?.toString() ?? '0') ?? 0,
      ciphertext: cipherStr ?? messageStr ?? '',
      message: messageStr,
      keyVersion: json['key_version'] is int
          ? json['key_version']
          : int.tryParse(json['key_version']?.toString() ?? '1') ?? 1,
      filePath: (json['file_path'] ?? json['filePath'])?.toString(),
      fileType: (json['file_type'] ?? json['fileType'])?.toString(),
      fileName: (json['file_name'] ?? json['fileName'])?.toString(),
      replyToId: json['reply_to_id'] is int
          ? json['reply_to_id']
          : int.tryParse(json['reply_to_id']?.toString() ?? ''),
      chatReact: normalizeChatReaction(json['chat_react']),
      isEdited: json['is_edited'] == true || json['is_edited'] == 1,
      isDeleted: json['is_deleted'] == true || json['is_deleted'] == 1,
      createdAt: (json['created_at'] ?? json['createdAt'])?.toString() ??
          DateTime.now().toIso8601String(),
    );
  }

  /// Returns decrypted message content given the secret key.
  String decryptedContent(String secretKey) {
    final raw = message?.isNotEmpty == true ? message! : ciphertext;
    return E2eCryptoService.instance.decryptText(raw, secretKey);
  }
}

/// Response returned by Auth Login/Register endpoints.
class AuthResponseModel {
  final String token;
  final UserModel user;

  AuthResponseModel({
    required this.token,
    required this.user,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic> ? json['data'] : json;
    return AuthResponseModel(
      token: data['token']?.toString() ?? '',
      user: UserModel.fromJson(data['user'] is Map<String, dynamic> ? data['user'] : data),
    );
  }
}
