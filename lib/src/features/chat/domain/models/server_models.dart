
import 'dart:convert';
import '../services/e2e_crypto_service.dart';
import '../services/server_api_service.dart';

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
    final rawId = json['id'] ?? json['user_id'] ?? json['userId'];
    final id = rawId is int ? rawId : (int.tryParse(rawId?.toString() ?? '') ?? 0);

    final rawName = json['name']?.toString() ??
        json['username']?.toString() ??
        json['full_name']?.toString() ??
        json['fullName']?.toString() ??
        json['display_name']?.toString() ??
        json['displayName']?.toString();

    final phone = (json['phone'] ?? json['phone_number'] ?? json['phoneNumber'])?.toString();
    final email = json['email']?.toString();

    String name = (rawName != null && rawName.trim().isNotEmpty && rawName.trim().toLowerCase() != 'null')
        ? rawName.trim()
        : '';

    if (name.isEmpty || name.toLowerCase() == 'user') {
      if (phone != null && phone.trim().isNotEmpty) {
        name = phone.trim();
      } else if (email != null && email.trim().isNotEmpty) {
        name = email.trim();
      } else if (id > 0) {
        name = 'User #$id';
      } else {
        name = 'User';
      }
    }

    return UserModel(
      id: id,
      name: name,
      phone: phone,
      email: email,
      publicKey: (json['public_key'] ?? json['publicKey'])?.toString(),
      avatar: (json['avatar'] ?? json['avatar_url'] ?? json['avatarUrl'] ?? json['profile_pic'] ?? json['profilePic'])?.toString(),
      role: json['role']?.toString(),
      encryptedPrivateKey: (json['encrypted_private_key'] ?? json['encryptedPrivateKey'])?.toString(),
      keySalt: (json['key_salt'] ?? json['keySalt'])?.toString(),
      keyIv: (json['key_iv'] ?? json['keyIv'])?.toString(),
      isOnline: json['is_online'] == true ||
          json['is_online'] == 1 ||
          json['is_online'] == 'true' ||
          json['is_online'] == '1' ||
          json['isOnline'] == true ||
          json['isOnline'] == 1 ||
          json['isOnline'] == 'true' ||
          json['isOnline'] == '1',
      lastSeenAt: (json['last_seen_at'] ?? json['lastSeenAt'])?.toString(),
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

/// Paginated Chat Head List Response model for GET /chats?page={page}&limit={limit}
class ServerChatListPageModel {
  final int page;
  final int limit;
  final int total;
  final int totalPages;
  final List<ServerChatModel> chats;

  ServerChatListPageModel({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
    required this.chats,
  });

  bool get hasMore => page < totalPages;

  factory ServerChatListPageModel.fromJson(Map<String, dynamic> json) {
    int readInt(dynamic value, int fallback) {
      if (value is int) return value;
      if (value != null) {
        final parsed = int.tryParse(value.toString());
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    final page = readInt(json['page'], 1);
    final limit = readInt(json['limit'], 20);
    int total = readInt(json['total'], 0);
    int totalPages = readInt(json['total_pages'] ?? json['totalPages'], 1);

    List list = [];
    if (json['data'] is List) {
      list = json['data'] as List;
    } else if (json['chats'] is List) {
      list = json['chats'] as List;
    } else if (json['chat_heads'] is List) {
      list = json['chat_heads'] as List;
    } else if (json['chatHeads'] is List) {
      list = json['chatHeads'] as List;
    } else if (json['items'] is List) {
      list = json['items'] as List;
    } else if (json['results'] is List) {
      list = json['results'] as List;
    } else if (json['data'] is Map) {
      final dataMap = json['data'] as Map;
      total = readInt(dataMap['total'], total);
      totalPages = readInt(dataMap['total_pages'] ?? dataMap['totalPages'], totalPages);
      if (dataMap['chats'] is List) {
        list = dataMap['chats'] as List;
      } else if (dataMap['chat_heads'] is List) {
        list = dataMap['chat_heads'] as List;
      } else if (dataMap['items'] is List) {
        list = dataMap['items'] as List;
      }
    }

    final chats = list
        .map((c) => ServerChatModel.fromJson(
            c is Map<String, dynamic> ? c : Map<String, dynamic>.from(c as Map)))
        .toList();

    if (total <= 0) total = chats.length;
    if (totalPages <= 1 && chats.length >= limit) {
      totalPages = page + 1;
    }

    return ServerChatListPageModel(
      page: page,
      limit: limit,
      total: total,
      totalPages: totalPages,
      chats: chats,
    );
  }
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
    final rawMembers = json['members'] ??
        json['participants'] ??
        json['users'] ??
        json['members_list'] ??
        json['membersList'];

    if (rawMembers != null && rawMembers is List) {
      membersList = rawMembers
          .map((m) => UserModel.fromJson(
                m is Map<String, dynamic>
                    ? m
                    : (m is Map ? Map<String, dynamic>.from(m) : {}),
              ))
          .toList();
    }

    Map<String, dynamic>? extraUserMap;
    if (json['other_user'] is Map) {
      extraUserMap = Map<String, dynamic>.from(json['other_user'] as Map);
    } else if (json['otherUser'] is Map) {
      extraUserMap = Map<String, dynamic>.from(json['otherUser'] as Map);
    } else if (json['user'] is Map) {
      extraUserMap = Map<String, dynamic>.from(json['user'] as Map);
    } else if (json['peer'] is Map) {
      extraUserMap = Map<String, dynamic>.from(json['peer'] as Map);
    }

    if (extraUserMap != null) {
      final extraUser = UserModel.fromJson(extraUserMap);
      if (extraUser.id > 0) {
        final existingIdx = membersList.indexWhere((m) => m.id == extraUser.id);
        if (existingIdx >= 0) {
          final existing = membersList[existingIdx];
          if (existing.name.startsWith('User #') || existing.name == 'User') {
            membersList[existingIdx] = extraUser;
          }
        } else {
          membersList.add(extraUser);
        }
      }
    }

    final rawLastMessage = json['last_message'] ??
        json['lastMessage'] ??
        json['latest_message'] ??
        json['latestMessage'] ??
        json['last_msg'] ??
        json['lastMsg'];

    final lastMessageJson = rawLastMessage is Map
        ? Map<String, dynamic>.from(rawLastMessage)
        : <String, dynamic>{};

    final rawId = json['id'] ??
        json['chat_head_id'] ??
        json['chatHeadId'] ??
        json['chat_id'] ??
        json['chatId'];

    final rawUnread = json['unread'] ??
        json['unread_count'] ??
        json['unreadCount'] ??
        json['unread_messages_count'] ??
        json['unreadMessagesCount'];

    final unreadVal = rawUnread is int
        ? rawUnread
        : int.tryParse(rawUnread?.toString() ?? '0') ?? 0;

    final rawGroup = json['is_group'] ??
        json['isGroup'] ??
        json['is_group_chat'] ??
        json['isGroupChat'];

    final isGroupVal = rawGroup == true ||
        rawGroup == 1 ||
        rawGroup == 'true' ||
        rawGroup == '1' ||
        json['type'] == 'group';

    return ServerChatModel(
      id: rawId is int ? rawId : (int.tryParse(rawId?.toString() ?? '') ?? 0),
      groupName: (json['group_name'] ?? json['groupName'] ?? json['name'] ?? json['title'])?.toString(),
      groupAvatar: (json['group_avatar'] ?? json['groupAvatar'] ?? json['avatar'] ?? json['icon'])?.toString(),
      isGroup: isGroupVal,
      lastMessageCiphertext: lastMessageJson['ciphertext']?.toString() ??
          lastMessageJson['encrypted_message']?.toString() ??
          json['last_message_ciphertext']?.toString() ??
          json['lastMessageCiphertext']?.toString() ??
          json['ciphertext']?.toString(),
      lastMessage: lastMessageJson['message']?.toString() ??
          lastMessageJson['text']?.toString() ??
          lastMessageJson['content']?.toString() ??
          (rawLastMessage is String ? rawLastMessage : null),
      lastMessageFilePath: lastMessageJson['file_path']?.toString() ??
          lastMessageJson['filePath']?.toString() ??
          lastMessageJson['file_url']?.toString() ??
          lastMessageJson['fileUrl']?.toString(),
      lastMessageFileName: lastMessageJson['file_name']?.toString() ??
          lastMessageJson['fileName']?.toString() ??
          lastMessageJson['name']?.toString(),
      lastMessageId: int.tryParse(lastMessageJson['id']?.toString() ?? ''),
      lastMessageSenderId: int.tryParse(
          (lastMessageJson['sender_id'] ?? lastMessageJson['senderId'] ?? lastMessageJson['user_id'])?.toString() ?? ''),
      lastMessageCreatedAt: (lastMessageJson['created_at'] ?? lastMessageJson['createdAt'] ?? json['last_message_created_at'] ?? json['lastMessageCreatedAt'])?.toString(),
      unreadCount: unreadVal,
      members: membersList,
      updatedAt: (json['updated_at'] ?? json['updatedAt'])?.toString(),
      createdAt: (json['created_at'] ?? json['createdAt'])?.toString(),
      createdBy: json['created_by'] is int
          ? json['created_by'] as int
          : int.tryParse((json['created_by'] ?? json['createdBy'])?.toString() ?? ''),
      totalMembers: json['total_members'] is int
          ? json['total_members'] as int
          : int.tryParse((json['total_members'] ?? json['totalMembers'])?.toString() ?? ''),
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
      user: UserModel.fromJson(data['user'] is Map<String, dynamic> ? data['user'] : (data['user'] != null ? Map<String, dynamic>.from(data['user']) : <String, dynamic>{})),
    );
  }
}

/// Represents an uploaded file item in the Private Vault Storage.
class UploadItemModel {
  final int id;
  final String filePath;
  final String folder;
  final String fileName;
  final String fileType;
  final int fileSize;
  final String createdAt;
  final String url;

  UploadItemModel({
    required this.id,
    required this.filePath,
    required this.folder,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.createdAt,
    required this.url,
  });

  factory UploadItemModel.fromJson(Map<String, dynamic> json) {
    return UploadItemModel(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      filePath: (json['file_path'] ?? json['filePath'] ?? json['path'])?.toString() ?? '',
      folder: json['folder']?.toString() ?? '',
      fileName: (json['file_name'] ?? json['fileName'] ?? json['name'])?.toString() ?? 'File',
      fileType: (json['file_type'] ?? json['fileType'] ?? json['type'])?.toString() ?? 'application/octet-stream',
      fileSize: json['file_size'] is int
          ? json['file_size'] as int
          : json['fileSize'] is int
              ? json['fileSize'] as int
              : json['size'] is int
                  ? json['size'] as int
                  : int.tryParse((json['file_size'] ?? json['fileSize'] ?? json['size'])?.toString() ?? '0') ?? 0,
      createdAt: (json['created_at'] ?? json['createdAt'])?.toString() ?? '',
      url: (json['url'] ?? json['path'] ?? json['file_path'])?.toString() ?? '',
    );
  }

  /// Construct full absolute media URL
  String get fullUrl {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final apiBase = ServerApiService.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final origin = apiBase.replaceFirst(RegExp(r'/api$'), '');

    if (url.isNotEmpty && url.contains('/')) {
      if (url.startsWith('/')) {
        return '$origin$url';
      }
      return '$origin/$url';
    }

    final targetPath = filePath.isNotEmpty ? filePath : url;
    if (targetPath.isNotEmpty) {
      final clean = targetPath.replaceFirst(RegExp(r'^/+'), '');
      if (clean.startsWith('api/files/')) {
        return '$origin/$clean';
      }
      if (clean.startsWith('files/')) {
        return '$apiBase/$clean';
      }
      return '$apiBase/files/$clean';
    }

    return '';
  }

  String get formattedSize {
    if (fileSize <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (fileSize.toString().length - 1) ~/ 3;
    if (i >= suffixes.length) i = suffixes.length - 1;
    final value = fileSize / (1 << (i * 10));
    return '${value.toStringAsFixed(value < 10 && i > 0 ? 1 : 0)} ${suffixes[i]}';
  }

  String get formattedDate {
    if (createdAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return createdAt;
    }
  }

  bool get isImage {
    final f = folder.toLowerCase();
    if (f == 'image' || f == 'images') return true;
    final lowerType = fileType.toLowerCase();
    if (lowerType.startsWith('image/')) return true;
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp', 'svg'].contains(ext);
  }

  bool get isVideo {
    final f = folder.toLowerCase();
    if (f == 'video' || f == 'videos') return true;
    final lowerType = fileType.toLowerCase();
    if (lowerType.startsWith('video/')) return true;
    final ext = fileName.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp', 'flv'].contains(ext);
  }

  bool get isAudio {
    final f = folder.toLowerCase();
    if (f == 'audio' || f == 'audios' || f == 'music' || f == 'sound' || f == 'voice') return true;
    final lowerType = fileType.toLowerCase();
    if (lowerType.startsWith('audio/')) return true;
    final ext = fileName.split('.').last.toLowerCase();
    return ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac', 'opus', 'amr', 'wma'].contains(ext);
  }

  bool get isDoc {
    final f = folder.toLowerCase();
    if (f == 'doc' || f == 'document' || f == 'documents' || f == 'file' || f == 'files') return true;
    return !isImage && !isVideo && !isAudio;
  }
}

/// Paginated Uploads Response from GET /uploads?folder={folder}&page={page}&limit={limit}
class UploadsResponseModel {
  final int page;
  final int limit;
  final int total;
  final List<UploadItemModel> items;

  UploadsResponseModel({
    required this.page,
    required this.limit,
    required this.total,
    required this.items,
  });

  factory UploadsResponseModel.fromJson(Map<String, dynamic> json, {String? requestedFolder}) {
    final page = json['page'] is int
        ? json['page'] as int
        : int.tryParse(json['page']?.toString() ?? '1') ?? 1;
    final limit = json['limit'] is int
        ? json['limit'] as int
        : int.tryParse(json['limit']?.toString() ?? '20') ?? 20;
    int total = json['total'] is int
        ? json['total'] as int
        : int.tryParse(json['total']?.toString() ?? '0') ?? 0;
    List<UploadItemModel> items = [];

    final folders = json['folders'];
    if (folders is Map) {
      final foldersMap = Map<String, dynamic>.from(folders);

      if (requestedFolder != null && requestedFolder.isNotEmpty) {
        final req = requestedFolder.toLowerCase();
        Map<String, dynamic>? targetFolderMap;

        for (final entry in foldersMap.entries) {
          final kLower = entry.key.toString().toLowerCase();
          if (kLower == req ||
              (req == 'doc' && (kLower == 'document' || kLower == 'documents' || kLower == 'files')) ||
              (req == 'image' && kLower == 'images') ||
              (req == 'video' && kLower == 'videos') ||
              (req == 'audio' && (kLower == 'audios' || kLower == 'music'))) {
            if (entry.value is Map) {
              targetFolderMap = Map<String, dynamic>.from(entry.value as Map);
              break;
            }
          }
        }

        if (targetFolderMap != null) {
          if (targetFolderMap['total'] != null) {
            total = targetFolderMap['total'] is int
                ? targetFolderMap['total'] as int
                : int.tryParse(targetFolderMap['total'].toString()) ?? total;
          }
          final rawItems = targetFolderMap['items'];
          if (rawItems is List) {
            items = rawItems
                .whereType<Map>()
                .map((e) => UploadItemModel.fromJson(Map<String, dynamic>.from(e)))
                .toList();
          }
        }
      } else {
        for (final entry in foldersMap.entries) {
          if (entry.value is Map) {
            final fMap = Map<String, dynamic>.from(entry.value as Map);
            final rawItems = fMap['items'];
            if (rawItems is List) {
              items.addAll(
                rawItems
                    .whereType<Map>()
                    .map((e) => UploadItemModel.fromJson(Map<String, dynamic>.from(e))),
              );
            }
          }
        }
      }
    } else if (json['items'] is List) {
      final rawItems = json['items'] as List;
      items = rawItems
          .whereType<Map>()
          .map((e) => UploadItemModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    if (requestedFolder != null && requestedFolder.isNotEmpty) {
      final req = requestedFolder.toLowerCase();
      if (req == 'image') {
        items = items.where((item) => item.isImage).toList();
      } else if (req == 'video') {
        items = items.where((item) => item.isVideo).toList();
      } else if (req == 'audio') {
        items = items.where((item) => item.isAudio).toList();
      } else if (req == 'doc' || req == 'document' || req == 'documents') {
        items = items.where((item) => item.isDoc).toList();
      }
      total = items.length > total ? items.length : total;
    }

    return UploadsResponseModel(
      page: page,
      limit: limit,
      total: total,
      items: items,
    );
  }
}

/// Paginated Server Messages Response from GET /chats/:chatId/messages?page={page}&limit={limit}
class ServerMessagesPageModel {
  final int page;
  final int limit;
  final int total;
  final int totalPages;
  final List<ServerMessageModel> messages;

  ServerMessagesPageModel({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
    required this.messages,
  });

  bool get hasMore => page < totalPages;

  factory ServerMessagesPageModel.fromJson(Map<String, dynamic> json) {
    final page = json['page'] is int
        ? json['page'] as int
        : int.tryParse(json['page']?.toString() ?? '1') ?? 1;
    final limit = json['limit'] is int
        ? json['limit'] as int
        : int.tryParse(json['limit']?.toString() ?? '20') ?? 20;
    final total = json['total'] is int
        ? json['total'] as int
        : int.tryParse(json['total']?.toString() ?? '0') ?? 0;
    final totalPages = json['total_pages'] is int
        ? json['total_pages'] as int
        : (json['totalPages'] is int
            ? json['totalPages'] as int
            : int.tryParse((json['total_pages'] ?? json['totalPages'])?.toString() ?? '1') ?? 1);

    List<ServerMessageModel> msgs = [];
    final items = json['items'] ?? json['messages'];
    if (items is List) {
      msgs = items
          .whereType<Map>()
          .map((m) => ServerMessageModel.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    return ServerMessagesPageModel(
      page: page,
      limit: limit,
      total: total,
      totalPages: totalPages,
      messages: msgs,
    );
  }
}

