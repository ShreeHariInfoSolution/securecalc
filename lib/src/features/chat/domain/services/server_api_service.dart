import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_models.dart';
import 'e2e_crypto_service.dart';
import 'local_chat_storage.dart';

/// Central REST API Service connecting Flutter client to https://synqerp.com/calculatorchat/api/
class ServerApiService {
  ServerApiService._();

  static final ServerApiService instance = ServerApiService._();

  static const String baseUrl = 'https://synqerp.com/calculatorchat/api';
  static const String _authTokenKey = 'PREF_SERVER_AUTH_TOKEN';
  static const String _authUserIdKey = 'PREF_SERVER_USER_ID';
  static const String _authUserKey = 'PREF_SERVER_USER';

  String? _authToken;
  int? _currentUserId;
  UserModel? _currentUser;

  String? get authToken => _authToken;
  int? get currentUserId => _currentUserId;
  UserModel? get currentUser => _currentUser;

  /// Restores saved authentication token and user ID from SharedPreferences.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString(_authTokenKey);
    _currentUserId = prefs.getInt(_authUserIdKey);
    LocalChatStorage.instance.setAccountId(_currentUserId);
    final savedUser = prefs.getString(_authUserKey);
    if (savedUser != null) {
      try {
        _currentUser = UserModel.fromJson(jsonDecode(savedUser));
      } catch (_) {
        _currentUser = null;
      }
    }
  }

  Future<void> saveSession(String token, int userId, {UserModel? user}) async {
    final prefs = await SharedPreferences.getInstance();
    final previousUserId =
        _currentUserId ?? prefs.getInt(_authUserIdKey);
    if (previousUserId != null && previousUserId != userId) {
      // Defensively isolate account switches even if login happens without
      // the normal logout path completing first.
      await LocalChatStorage.instance.clearChats();
    }

    _authToken = token;
    _currentUserId = userId;
    _currentUser = user ?? _currentUser;
    LocalChatStorage.instance.setAccountId(userId);
    await prefs.setString(_authTokenKey, token);
    await prefs.setInt(_authUserIdKey, userId);
    if (_currentUser != null) {
      await prefs.setString(_authUserKey, jsonEncode(_currentUser!.toJson()));
    }
  }

  Future<void> clearSession() async {
    _authToken = null;
    _currentUserId = null;
    _currentUser = null;
    LocalChatStorage.instance.setAccountId(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
    await prefs.remove(_authUserIdKey);
    await prefs.remove(_authUserKey);
  }

  Map<String, String> _headers({bool requiresAuth = true}) {
    final map = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (requiresAuth && _authToken != null && _authToken!.isNotEmpty) {
      map['Authorization'] = 'Bearer $_authToken';
    }
    return map;
  }

  // ─── Health Checks ─────────────────────────────────────────────────────────

  Future<bool> checkStatus() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/status'),
        headers: _headers(requiresAuth: false),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[API] Status Error: $e');
      return false;
    }
  }

  Future<bool> checkDb() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/db'),
        headers: _headers(requiresAuth: false),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[API] DB Check Error: $e');
      return false;
    }
  }

  // ─── Auth Endpoints ────────────────────────────────────────────────────────

  Future<AuthResponseModel> register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) async {
    final pubKey = E2eCryptoService.instance.generatePublicKey();
    final body = {
      'name': name,
      'phone': phone,
      'email': email,
      'password': password,
      'public_key': pubKey,
      'encrypted_private_key': 'backup_enc_priv_key',
      'key_salt': 'salt_123',
      'key_iv': 'iv_123',
    };

    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _headers(requiresAuth: false),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final json = jsonDecode(res.body);
      final auth = AuthResponseModel.fromJson(json);
      await saveSession(auth.token, auth.user.id, user: auth.user);
      return auth;
    } else {
      String cleanError = 'Registration failed';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          cleanError = decoded['message'] ?? decoded['error'] ?? decoded['msg'] ?? cleanError;
        }
      } catch (_) {}
      throw Exception(cleanError);
    }
  }

  Future<AuthResponseModel> login({
    required String phoneOrEmail,
    required String password,
  }) async {
    final body = {
      if (phoneOrEmail.contains('@')) 'email': phoneOrEmail else 'phone': phoneOrEmail,
      'password': password,
    };

    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers(requiresAuth: false),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body);
      final auth = AuthResponseModel.fromJson(json);
      await saveSession(auth.token, auth.user.id, user: auth.user);
      return auth;
    } else {
      if (res.statusCode == 401 || res.statusCode == 400 || res.statusCode == 404) {
        throw Exception('Wrong credentials');
      }
      String cleanError = 'Wrong credentials';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          cleanError = decoded['message'] ?? decoded['error'] ?? decoded['msg'] ?? cleanError;
        }
      } catch (_) {}
      throw Exception(cleanError);
    }
  }

  Future<UserModel?> getProfile() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = json['data'] is Map<String, dynamic> ? json['data'] : json;
        _currentUser = UserModel.fromJson(data);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_authUserKey, jsonEncode(_currentUser!.toJson()));
        return _currentUser;
      }
    } catch (e) {
      debugPrint('[API] Get Profile Error: $e');
    }
    return null;
  }

  // ─── Users Endpoints ───────────────────────────────────────────────────────

  Future<List<UserModel>> searchUsers(String query) async {
    try {
      final url = Uri.parse('$baseUrl/users').replace(queryParameters: {'q': query});
      final res = await http.get(url, headers: _headers());
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final list = json['data'] is List ? json['data'] as List : [];
        return list.map((u) => UserModel.fromJson(u)).toList();
      }
    } catch (e) {
      debugPrint('[API] Search Users Error: $e');
    }
    return [];
  }

  /// Loads the registered user directory for group member selection.
  Future<List<UserModel>> getUsers() async {
    final firstPage = await getUsersPage(page: 1, limit: 20);
    final users = [...firstPage.users];
    for (var page = 2; page <= firstPage.totalPages; page++) {
      final nextPage = await getUsersPage(page: page, limit: firstPage.limit);
      users.addAll(nextPage.users);
    }
    return users;
  }

  Future<UserListPageModel> getUsersPage({
    int page = 1,
    int limit = 20,
    String query = '',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/users/list').replace(
        queryParameters: {
          'page': page.toString(),
          'limit': limit.toString(),
          'q': query,
        },
      );
      final res = await http.get(uri, headers: _headers());
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final data = decoded is Map ? decoded['data'] : null;
        final list = data is Map && data['users'] is List
            ? data['users'] as List
            : data is List
                ? data
                : const [];
        int readInt(dynamic value, int fallback) =>
            value is int ? value : int.tryParse(value?.toString() ?? '') ?? fallback;
        return UserListPageModel(
          users: list
              .whereType<Map>()
              .map((user) => UserModel.fromJson(
                    Map<String, dynamic>.from(user),
                  ))
              .toList(),
          page: readInt(data is Map ? data['page'] : null, page),
          limit: readInt(data is Map ? data['limit'] : null, limit),
          total: readInt(data is Map ? data['total'] : null, list.length),
          totalPages: readInt(data is Map ? data['total_pages'] : null, 1),
        );
      }
      throw Exception('Get User List Failed (${res.statusCode}): ${res.body}');
    } catch (e) {
      debugPrint('[API] Get User List Error: $e');
      rethrow;
    }
  }

  Future<UserModel?> getUser(int id) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/users/$id'), headers: _headers());
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = json['data'] is Map<String, dynamic> ? json['data'] : json;
        return UserModel.fromJson(data);
      }
    } catch (e) {
      debugPrint('[API] Get User Error: $e');
    }
    return null;
  }

  // ─── Chats Endpoints ───────────────────────────────────────────────────────

  Future<List<ServerChatModel>> getChats() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/chats'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final list = json['data'] is List ? json['data'] as List : [];
        return list.map((c) => ServerChatModel.fromJson(c)).toList();
      }
      throw Exception('Get Chats Failed (${res.statusCode}): ${res.body}');
    } catch (e) {
      debugPrint('[API] Get Chats Error: $e');
      rethrow;
    }
  }

  Future<int> getUnreadCount() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/chats/unread-count'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = json['data'];
        if (data is Map && data.containsKey('unread')) {
          return data['unread'] as int;
        }
      }
    } catch (e) {
      debugPrint('[API] Unread Count Error: $e');
    }
    return 0;
  }

  Future<ServerChatModel> createDirectChat(int targetUserId) async {
    final body = {
      'user_id': targetUserId,
    };

    final res = await http.post(
      Uri.parse('$baseUrl/chats/direct'),
      headers: _headers(),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final json = jsonDecode(res.body);
      final data = json['data'] is Map<String, dynamic> ? json['data'] : json;
      return ServerChatModel.fromJson(data);
    } else {
      throw Exception('Create Direct Chat Error (${res.statusCode}): ${res.body}');
    }
  }

  Future<ServerChatModel> createGroup({
    required String groupName,
    List<int>? memberIds,
    String? groupAvatar,
  }) async {
    final body = {
      'group_name': groupName,
      'member_ids': memberIds ?? [],
      if (groupAvatar != null) 'group_avatar': groupAvatar,
    };

    final res = await http.post(
      Uri.parse('$baseUrl/chats/group'),
      headers: _headers(),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final json = jsonDecode(res.body);
      final data = json['data'] is Map<String, dynamic> ? json['data'] : json;
      return ServerChatModel.fromJson(data);
    } else {
      throw Exception('Create Group Error (${res.statusCode}): ${res.body}');
    }
  }

  Future<ServerChatModel?> getChatDetails(int chatId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/chats/$chatId'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = json['data'] is Map<String, dynamic> ? json['data'] : json;
        return ServerChatModel.fromJson(data);
      }
    } catch (e) {
      debugPrint('[API] Get Chat Details Error: $e');
    }
    return null;
  }

  Future<bool> addGroupMembers({
    required int chatId,
    required List<int> userIds,
  }) async {
    try {
      final body = {'user_ids': userIds};
      final res = await http.post(
        Uri.parse('$baseUrl/chats/$chatId/members'),
        headers: _headers(),
        body: jsonEncode(body),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[API] Add Group Members Error: $e');
      return false;
    }
  }

  Future<bool> removeGroupMember({
    required int chatId,
    required int userId,
  }) async {
    try {
      final body = {'user_id': userId};
      final res = await http.post(
        Uri.parse('$baseUrl/chats/$chatId/members/remove'),
        headers: _headers(),
        body: jsonEncode(body),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[API] Remove Group Member Error: $e');
      return false;
    }
  }

  Future<bool> deleteGroup(int chatId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/chats/$chatId'),
        headers: _headers(),
      );
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      debugPrint('[API] Delete Group Error: $e');
      return false;
    }
  }

  // ─── Messages Endpoints ────────────────────────────────────────────────────

  Future<List<ServerMessageModel>> getMessages(
    int chatId, {
    int? limit,
    String? before,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (limit != null && limit > 0) {
        queryParams['limit'] = '$limit';
      }
      if (before != null && before.isNotEmpty) {
        queryParams['before'] = before;
      }
      final endpoint = Uri.parse('$baseUrl/chats/$chatId/messages');
      final url = queryParams.isEmpty
          ? endpoint
          : endpoint.replace(queryParameters: queryParams);
      final res = await http.get(url, headers: _headers());

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final json = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
        final data = json['data'];
        final list = data is List
            ? data
            : data is Map && data['messages'] is List
                ? data['messages'] as List
                : json['messages'] is List
                    ? json['messages'] as List
                    : <dynamic>[];
        return list
            .whereType<Map>()
            .map((message) => ServerMessageModel.fromJson(
                  Map<String, dynamic>.from(message),
                ))
            .toList();
      }
      throw Exception(
        'Load Messages Failed (${res.statusCode}): ${res.body}',
      );
    } catch (e) {
      debugPrint('[API] Get Messages Error: $e');
      rethrow;
    }
  }

  Future<ServerMessageModel> sendMessageREST({
    required int chatId,
    required String message,
    String? filePath,
    String? fileName,
    String? fileType,
    int? replyToId,
    String? clientId,
  }) async {
    final body = {
      'message': message,
      'reply_to_id': replyToId,
      'client_id': clientId ?? 'local_${DateTime.now().millisecondsSinceEpoch}',
      if (filePath != null) 'file_path': filePath,
      if (fileName != null) 'file_name': fileName,
      if (fileType != null) 'file_type': fileType,
    };

    final res = await http.post(
      Uri.parse('$baseUrl/chats/$chatId/messages'),
      headers: _headers(),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final json = jsonDecode(res.body);
      final data = json['data'] is Map<String, dynamic> ? json['data'] : json;
      return ServerMessageModel.fromJson(data);
    } else {
      throw Exception('Send Message REST Error (${res.statusCode}): ${res.body}');
    }
  }

  Future<Map<String, dynamic>?> markChatRead(int chatId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/chats/$chatId/read'),
        headers: _headers(),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final json = jsonDecode(res.body);
        return json is Map<String, dynamic> ? json : null;
      }
    } catch (e) {
      debugPrint('[API] Mark Chat Read Error: $e');
    }
    return null;
  }

  Future<bool> clearChatREST(int chatId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/chats/$chatId/messages'),
        headers: _headers(),
      );
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      debugPrint('[API] Clear Chat REST Error: $e');
      return false;
    }
  }

  Future<bool> editMessageREST({
    required int messageId,
    required String message,
  }) async {
    try {
      final body = {
        'message': message,
      };
      final res = await http.put(
        Uri.parse('$baseUrl/messages/$messageId'),
        headers: _headers(),
        body: jsonEncode(body),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[API] Edit Message REST Error: $e');
      return false;
    }
  }

  Future<bool> deleteMessageREST(int messageId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/messages/$messageId'),
        headers: _headers(),
      );
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      debugPrint('[API] Delete Message REST Error: $e');
      return false;
    }
  }

  Future<bool> reactMessageREST({
    required int messageId,
    required String chatReact,
  }) async {
    try {
      // The API writes this value directly into a PostgreSQL JSON column.
      // Encode the emoji as a JSON string within the request JSON so the DB
      // receives a valid JSON value (matches the working Postman payload).
      final body = {'chat_react': jsonEncode(chatReact)};
      final res = await http.post(
        Uri.parse('$baseUrl/messages/$messageId/react'),
        headers: _headers(),
        body: jsonEncode(body),
      );
      debugPrint(
        '[API] React Message Response (${res.statusCode}): ${res.body}',
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[API] React Message REST Error: $e');
      return false;
    }
  }

  // ─── Files Endpoints ───────────────────────────────────────────────────────

  Future<String?> uploadFile(File file, {String? filename}) async {
    try {
      final uri = Uri.parse('$baseUrl/upload');
      final req = http.MultipartRequest('POST', uri);
      if (_authToken != null) {
        req.headers['Authorization'] = 'Bearer $_authToken';
      }
      req.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: filename ?? file.path.split(RegExp(r'[/\\]')).last,
      ));

      final streamedRes = await req.send();
      final res = await http.Response.fromStream(streamedRes);

      if (res.statusCode == 200 || res.statusCode == 201) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final data = decoded['data'];
          if (data is String && data.isNotEmpty) return data;
          if (data is Map) {
            for (final key in const [
              'path',
              'file_path',
              'url',
              'file_url',
              'location',
            ]) {
              final value = data[key]?.toString();
              if (value != null && value.isNotEmpty) return value;
            }
          }
          for (final key in const [
            'path',
            'file_path',
            'url',
            'file_url',
            'location',
          ]) {
            final value = decoded[key]?.toString();
            if (value != null && value.isNotEmpty) return value;
          }
        }
        debugPrint('[API] Upload succeeded but response has no file path: ${res.body}');
      } else {
        debugPrint('[API] Upload failed (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      debugPrint('[API] Upload File Error: $e');
    }
    return null;
  }
}

