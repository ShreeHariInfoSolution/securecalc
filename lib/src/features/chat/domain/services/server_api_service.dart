import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_models.dart';
import 'e2e_crypto_service.dart';
import 'local_chat_storage.dart';
import 'push_service.dart';
import 'server_chat_manager.dart';
import 'socket_chat_service.dart';

import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/features/calling/domain/services/device_identity_service.dart';

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
        if (_currentUser != null) {
          if (_currentUser!.name.isNotEmpty) {
            await AppPreferences.setDisplayName(_currentUser!.name);
          }
          if (_currentUser!.avatar != null &&
              _currentUser!.avatar!.isNotEmpty) {
            await AppPreferences.setProfileImagePath(_currentUser!.avatar!);
          }
        }
      } catch (_) {
        _currentUser = null;
      }
    }
  }

  Future<void> saveSession(String token, int userId, {UserModel? user}) async {
    final prefs = await SharedPreferences.getInstance();
    final previousUserId = _currentUserId ?? prefs.getInt(_authUserIdKey);
    if (previousUserId != null && previousUserId != userId) {
      debugPrint(
        '[AUTH] Account switch detected ($previousUserId -> $userId). Isolating session...',
      );
      SocketChatService.instance.disconnect();
      ServerChatManager.instance.activeChatId = null;
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
      if (_currentUser!.name.isNotEmpty) {
        await AppPreferences.setDisplayName(_currentUser!.name);
      }
      if (_currentUser!.avatar != null && _currentUser!.avatar!.isNotEmpty) {
        await AppPreferences.setProfileImagePath(_currentUser!.avatar!);
      }
    }
    unawaited(ServerChatManager.instance.init());
    unawaited(PushService.instance.registerAfterLogin());
  }

  Future<void> clearSession() async {
    await PushService.instance.unregisterOnLogout();
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
    final deviceId = await DeviceIdentityService.instance.getDeviceId();
    final body = {
      'name': name,
      'phone': phone,
      'email': email,
      'password': password,
      'public_key': pubKey,
      'encrypted_private_key': 'backup_enc_priv_key',
      'key_salt': 'salt_123',
      'key_iv': 'iv_123',
      'device_key': deviceId,
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
          cleanError =
              decoded['message'] ??
              decoded['error'] ??
              decoded['msg'] ??
              cleanError;
        }
      } catch (_) {}
      throw Exception(cleanError);
    }
  }

  Future<AuthResponseModel> login({
    required String phoneOrEmail,
    required String password,
  }) async {
    final deviceId = await DeviceIdentityService.instance.getDeviceId();
    final body = {
      if (phoneOrEmail.contains('@'))
        'email': phoneOrEmail
      else
        'phone': phoneOrEmail,
      'password': password,
      'device_key': deviceId,
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
      if (res.statusCode == 401 ||
          res.statusCode == 400 ||
          res.statusCode == 404) {
        throw Exception('Invalid phone, email, or password. Please try again.');
      }
      String cleanError = 'Invalid phone, email, or password. Please try again.';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          cleanError =
              decoded['message'] ??
              decoded['error'] ??
              decoded['msg'] ??
              cleanError;
        }
      } catch (_) {}
      throw Exception(cleanError);
    }
  }

  Future<AuthResponseModel> deviceLogin(String deviceKey) async {
    final body = {'device_key': deviceKey};

    final res = await http.post(
      Uri.parse('$baseUrl/auth/device-login'),
      headers: _headers(requiresAuth: false),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final json = jsonDecode(res.body);
      final auth = AuthResponseModel.fromJson(json);
      await saveSession(auth.token, auth.user.id, user: auth.user);
      return auth;
    } else {
      String cleanError = 'Device login failed';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          cleanError =
              decoded['message'] ??
              decoded['error'] ??
              decoded['msg'] ??
              cleanError;
        }
      } catch (_) {}
      throw Exception(cleanError);
    }
  }

  /// Swaps/migrates device key on the server (`POST /api/auth/swap-device`).
  /// Transfers account data from [oldDeviceKey] to [newDeviceKey] and saves the session.
  Future<AuthResponseModel> swapDevice({
    required String oldDeviceKey,
    required String newDeviceKey,
  }) async {
    final body = {
      'old_device_key': oldDeviceKey,
      'new_device_key': newDeviceKey,
    };

    final res = await http.post(
      Uri.parse('$baseUrl/auth/swap-device'),
      headers: _headers(requiresAuth: false),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final json = jsonDecode(res.body);
      AuthResponseModel auth;
      try {
        auth = AuthResponseModel.fromJson(json);
        if (auth.token.isNotEmpty) {
          await saveSession(auth.token, auth.user.id, user: auth.user);
          return auth;
        }
      } catch (_) {}

      // Fallback: If swap endpoint returns success status without full token, call deviceLogin with new key
      auth = await deviceLogin(newDeviceKey);
      return auth;
    } else {
      String cleanError = 'Device backup restore failed';
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          cleanError =
              decoded['message'] ??
              decoded['error'] ??
              decoded['msg'] ??
              cleanError;
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
        if (_currentUser!.name.isNotEmpty) {
          await AppPreferences.setDisplayName(_currentUser!.name);
        }
        if (_currentUser!.avatar != null && _currentUser!.avatar!.isNotEmpty) {
          await AppPreferences.setProfileImagePath(_currentUser!.avatar!);
        }
        return _currentUser;
      }
    } catch (e) {
      debugPrint('[API] Get Profile Error: $e');
    }
    return null;
  }

  /// Updates user profile on the server (`PUT /api/users/me`).
  Future<UserModel?> updateProfile({String? name, File? profileImage}) async {
    try {
      final uri = Uri.parse('$baseUrl/users/me');
      final request = http.MultipartRequest('PUT', uri);

      if (_authToken != null && _authToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }

      if (name != null && name.trim().isNotEmpty) {
        request.fields['name'] = name.trim();
      }

      if (profileImage != null && await profileImage.exists()) {
        final multipartFile = await http.MultipartFile.fromPath(
          'profile_image',
          profileImage.path,
        );
        request.files.add(multipartFile);
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        final data = decoded['data'] is Map<String, dynamic>
            ? decoded['data'] as Map<String, dynamic>
            : decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{};

        final updatedUser = UserModel.fromJson(data);
        _currentUser = updatedUser;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_authUserKey, jsonEncode(updatedUser.toJson()));

        if (updatedUser.name.isNotEmpty) {
          await AppPreferences.setDisplayName(updatedUser.name);
        }
        if (updatedUser.avatar != null && updatedUser.avatar!.isNotEmpty) {
          await AppPreferences.setProfileImagePath(updatedUser.avatar!);
        }

        return updatedUser;
      } else {
        String cleanError = 'Failed to update profile (${response.statusCode})';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            cleanError = decoded['message'] ?? decoded['error'] ?? cleanError;
          }
        } catch (_) {}
        throw Exception(cleanError);
      }
    } catch (e) {
      debugPrint('[API] Update Profile Error: $e');
      rethrow;
    }
  }

  /// Removes profile image on the server (`DELETE /api/users/me/avatar`).
  Future<UserModel?> deleteProfileImage() async {
    try {
      final uri = Uri.parse('$baseUrl/users/me/avatar');
      final res = await http.delete(
        uri,
        headers: _headers(),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final decoded = jsonDecode(res.body);
        final data = decoded['data'] is Map<String, dynamic>
            ? decoded['data'] as Map<String, dynamic>
            : decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{};

        final updatedUser = UserModel.fromJson(data);
        _currentUser = updatedUser;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_authUserKey, jsonEncode(updatedUser.toJson()));

        await AppPreferences.setProfileImagePath('');

        return updatedUser;
      }
    } catch (e) {
      debugPrint('[API] Delete Profile Image Error: $e');
    }
    return null;
  }

  // ─── Users Endpoints ───────────────────────────────────────────────────────

  Future<List<UserModel>> searchUsers(String query) async {
    try {
      final url = Uri.parse('$baseUrl/users')
          .replace(queryParameters: {'q': query});
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
        int readInt(dynamic value, int fallback) => value is int
            ? value
            : int.tryParse(value?.toString() ?? '') ?? fallback;
        return UserListPageModel(
          users: list
              .whereType<Map>()
              .map(
                (user) => UserModel.fromJson(Map<String, dynamic>.from(user)),
              )
              .toList(),
          page: readInt(data is Map ? data['page'] : null, page),
          limit: readInt(data is Map ? data['limit'] : null, limit),
          total: readInt(data is Map ? data['total'] : null, list.length),
          totalPages: readInt(data is Map ? data['total_pages'] : null, 1),
        );
      }
      throw Exception('Unable to load user list. Please try again.');
    } catch (e) {
      debugPrint('[API] Get User List Error: $e');
      rethrow;
    }
  }

  Future<UserModel?> getUser(int id) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/users/$id'),
        headers: _headers(),
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final data = json['data'] is Map<String, dynamic>
            ? json['data'] as Map<String, dynamic>
            : json;
        return UserModel.fromJson(data);
      }
    } catch (e) {
      debugPrint('[API] Get User Error: $e');
    }
    return null;
  }

  // ─── Chats Endpoints ───────────────────────────────────────────────────────

  Future<ServerChatListPageModel> getChatsPage({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/chats')
          .replace(queryParameters: {'page': '$page', 'limit': '$limit'});
      debugPrint('[API] GET $uri');
      final res = await http.get(uri, headers: _headers());
      debugPrint('[API] GET $uri (${res.statusCode}): ${res.body}');

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          final chats = decoded
              .map(
                (c) => ServerChatModel.fromJson(
                  c is Map<String, dynamic>
                      ? c
                      : Map<String, dynamic>.from(c as Map),
                ),
              )
              .toList();
          return ServerChatListPageModel(
            page: page,
            limit: limit,
            total: chats.length,
            totalPages: 1,
            chats: chats,
          );
        } else if (decoded is Map<String, dynamic>) {
          return ServerChatListPageModel.fromJson(decoded);
        } else if (decoded is Map) {
          return ServerChatListPageModel.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      }
      throw Exception('Unable to load chats. Please try again.');
    } catch (e) {
      debugPrint('[API] Get Chats Page Error (page=$page): $e');
      rethrow;
    }
  }

  Future<List<ServerChatModel>> getChats({int page = 1, int limit = 20}) async {
    try {
      final res = await getChatsPage(page: page, limit: limit);
      return res.chats;
    } catch (e) {
      debugPrint('[API] Get Chats Error: $e');
      return [];
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
    final body = {'user_id': targetUserId};

    final url = '$baseUrl/chats/direct';
    debugPrint('[API] POST $url with body: ${jsonEncode(body)}');

    final res = await http.post(
      Uri.parse(url),
      headers: _headers(),
      body: jsonEncode(body),
    );

    debugPrint(
      '[API] Create Direct Chat Response (${res.statusCode}): ${res.body}',
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final json = jsonDecode(res.body);
      final data = json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : (json is Map<String, dynamic> ? json : <String, dynamic>{});

      final chatHeadId =
          (data['chat_head_id'] ?? data['id'] ?? data['chat_id']) is int
          ? (data['chat_head_id'] ?? data['id'] ?? data['chat_id']) as int
          : int.tryParse(
                  (data['chat_head_id'] ?? data['id'] ?? data['chat_id'])
                          ?.toString() ??
                      '',
                ) ??
                0;

      if (chatHeadId > 0) {
        final details = await getChatDetails(chatHeadId);
        if (details != null) return details;
      }
      return ServerChatModel.fromJson(data);
    } else {
      debugPrint(
        '[API ERROR] Create Direct Chat Failed (${res.statusCode}): ${res.body}',
      );
      throw Exception('Unable to create direct chat. Please try again.');
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

    final url = '$baseUrl/chats/group';
    debugPrint('[API] POST $url with body: ${jsonEncode(body)}');

    final res = await http.post(
      Uri.parse(url),
      headers: _headers(),
      body: jsonEncode(body),
    );

    debugPrint('[API] Create Group Response (${res.statusCode}): ${res.body}');

    if (res.statusCode == 200 || res.statusCode == 201) {
      final json = jsonDecode(res.body);
      final data = json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : (json is Map<String, dynamic> ? json : <String, dynamic>{});

      final chatHeadId =
          (data['chat_head_id'] ?? data['id'] ?? data['chat_id']) is int
          ? (data['chat_head_id'] ?? data['id'] ?? data['chat_id']) as int
          : int.tryParse(
                  (data['chat_head_id'] ?? data['id'] ?? data['chat_id'])
                          ?.toString() ??
                      '',
                ) ??
                0;

      if (chatHeadId > 0) {
        final details = await getChatDetails(chatHeadId);
        if (details != null) return details;
      }
      return ServerChatModel.fromJson(data);
    } else {
      debugPrint(
        '[API ERROR] Create Group Failed (${res.statusCode}): ${res.body}',
      );
      throw Exception('Unable to create group. Please try again.');
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

  Future<String?> uploadChatBackground(int chatId, File image) async {
    try {
      final uri = Uri.parse('$baseUrl/chats/$chatId/background');
      final request = http.MultipartRequest('PUT', uri);

      if (_authToken != null && _authToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }

      final multipartFile = await http.MultipartFile.fromPath(
        'background_image',
        image.path,
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        final data = decoded['data'] is Map ? decoded['data'] : decoded;
        return data['background_url']?.toString();
      } else {
        throw Exception('Failed to update background image. Please try again.');
      }
    } catch (e) {
      debugPrint('[API] Upload Chat Background Error: $e');
      return null;
    }
  }

  Future<bool> removeChatBackground(int chatId) async {
    try {
      final uri = Uri.parse('$baseUrl/chats/$chatId/background');
      final response = await http.delete(uri, headers: _headers());

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[API] Remove Chat Background Error: $e');
      return false;
    }
  }

  // ─── Messages Endpoints ────────────────────────────────────────────────────

  /// Fetches paginated chat messages from GET /chats/:chatId/messages?page={page}&limit={limit}
  Future<ServerMessagesPageModel> getMessagesPage(
    int chatId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/chats/$chatId/messages')
          .replace(queryParameters: {'page': '$page', 'limit': '$limit'});
      debugPrint('[API] GET $uri');
      final res = await http.get(uri, headers: _headers());
      debugPrint('[API] GET $uri (${res.statusCode}): ${res.body}');

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final json = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
        final data = json['data'] is Map
            ? Map<String, dynamic>.from(json['data'] as Map)
            : json;
        return ServerMessagesPageModel.fromJson(data);
      }
      throw Exception('Unable to load chat messages. Please try again.');
    } catch (e) {
      debugPrint('[API] Get Messages Page Error ($chatId, page=$page): $e');
      rethrow;
    }
  }

  Future<List<ServerMessageModel>> getMessages(
    int chatId, {
    int? limit,
    int? page,
    String? before,
  }) async {
    try {
      final res = await getMessagesPage(
        chatId,
        page: page ?? 1,
        limit: limit ?? 20,
      );
      return res.messages;
    } catch (e) {
      debugPrint('[API] Get Messages Error: $e');
      return [];
    }
  }

  Future<ServerMessageModel> sendMessageREST({
    required int chatId,
    required String message,
    File? file,
    String? filePath,
    String? fileName,
    String? fileType,
    int? replyToId,
    String? clientId,
  }) async {
    final url = '$baseUrl/chats/$chatId/messages';

    if (file != null && await file.exists()) {
      debugPrint('[API] POST $url (Multipart File: ${file.path})');
      final req = http.MultipartRequest('POST', Uri.parse(url));
      if (_authToken != null) {
        req.headers['Authorization'] = 'Bearer $_authToken';
      }
      req.fields['message'] = message;
      if (replyToId != null) req.fields['reply_to_id'] = replyToId.toString();
      if (clientId != null) req.fields['client_id'] = clientId;
      if (fileType != null) req.fields['file_type'] = fileType;
      if (fileName != null) req.fields['file_name'] = fileName;

      req.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: fileName ?? file.path.split(RegExp(r'[/\\]')).last,
        ),
      );

      final streamedRes = await req.send();
      final res = await http.Response.fromStream(streamedRes);

      debugPrint(
        '[API] Send Message with File Response (${res.statusCode}): ${res.body}',
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final json = jsonDecode(res.body);
        final data = json['data'] is Map<String, dynamic>
            ? json['data'] as Map<String, dynamic>
            : (json is Map<String, dynamic> ? json : <String, dynamic>{});
        return ServerMessageModel.fromJson(data);
      } else {
        debugPrint(
          '[API ERROR] Send Message with File Failed (${res.statusCode}): ${res.body}',
        );
        throw Exception('Failed to send attachment. Please try again.');
      }
    } else {
      final body = {
        'message': message,
        'reply_to_id': replyToId,
        'client_id':
            clientId ?? 'local_${DateTime.now().millisecondsSinceEpoch}',
        if (filePath != null) 'file_path': filePath,
        if (fileName != null) 'file_name': fileName,
        if (fileType != null) 'file_type': fileType,
      };

      debugPrint('[API] POST $url with body: ${jsonEncode(body)}');

      final res = await http.post(
        Uri.parse(url),
        headers: _headers(),
        body: jsonEncode(body),
      );

      debugPrint(
        '[API] Send Message Response (${res.statusCode}): ${res.body}',
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final json = jsonDecode(res.body);
        final data = json['data'] is Map<String, dynamic>
            ? json['data'] as Map<String, dynamic>
            : (json is Map<String, dynamic> ? json : <String, dynamic>{});
        return ServerMessageModel.fromJson(data);
      } else {
        debugPrint(
          '[API ERROR] Send Message Failed (${res.statusCode}): ${res.body}',
        );
        throw Exception('Failed to send message. Please try again.');
      }
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
      final body = {'message': message};
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

  /// Sets disappearing messages setting for a chat head.
  /// PUT /chats/:chatId/disappear
  Future<Map<String, dynamic>?> setDisappearingMessagesREST({
    required int chatId,
    required int disappearType,
  }) async {
    try {
      final body = {'disappear_type': disappearType};
      final res = await http.put(
        Uri.parse('$baseUrl/chats/$chatId/disappear'),
        headers: _headers(),
        body: jsonEncode(body),
      );
      debugPrint('[API] Disappear Response (${res.statusCode}): ${res.body}');
      if (res.statusCode == 200 || res.statusCode == 201) {
        final json = jsonDecode(res.body);
        if (json is Map<String, dynamic>) return json;
      }
      return null;
    } catch (e) {
      debugPrint('[API] Disappear REST Error: $e');
      return null;
    }
  }

  /// Saves or unsaves a message.
  /// PUT /chats/:chatId/messages/:messageId/save
  Future<bool> saveMessageREST({
    required int chatId,
    required int messageId,
    required bool isSaved,
  }) async {
    try {
      final body = {'is_saved': isSaved};
      final res = await http.put(
        Uri.parse('$baseUrl/chats/$chatId/messages/$messageId/save'),
        headers: _headers(),
        body: jsonEncode(body),
      );
      debugPrint(
        '[API] Save Message Response (${res.statusCode}): ${res.body}',
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('[API] Save Message REST Error: $e');
      return false;
    }
  }

  // ─── Files Endpoints ───────────────────────────────────────────────────────

  /// Fetches paginated uploads for a given folder type ('image', 'video', 'audio', 'doc').
  Future<UploadsResponseModel> getUploads({
    required String folder,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/uploads').replace(
        queryParameters: {
          'folder': folder,
          'page': page.toString(),
          'limit': limit.toString(),
        },
      );

      debugPrint('[API] GET $uri');
      final res = await http.get(uri, headers: _headers());
      debugPrint('[API] GET $uri (${res.statusCode}): ${res.body}');

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final json = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
        final data = json['data'] is Map
            ? Map<String, dynamic>.from(json['data'] as Map)
            : json;
        return UploadsResponseModel.fromJson(data, requestedFolder: folder);
      } else {
        throw Exception('Failed to load $folder files. Please try again.');
      }
    } catch (e) {
      debugPrint('[API] Get Uploads Error ($folder): $e');
      rethrow;
    }
  }

  Future<String?> uploadFile(File file, {String? filename}) async {
    final item = await uploadVaultFile(file, filename: filename);
    return item?.filePath.isNotEmpty == true ? item!.filePath : item?.url;
  }

  /// Uploads a file to POST /upload and returns the parsed [UploadItemModel]
  Future<UploadItemModel?> uploadVaultFile(
    File file, {
    String? filename,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/upload');
      debugPrint('[API] POST $uri (File: ${file.path})');

      final req = http.MultipartRequest('POST', uri);
      if (_authToken != null) {
        req.headers['Authorization'] = 'Bearer $_authToken';
      }
      req.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: filename ?? file.path.split(RegExp(r'[/\\]')).last,
        ),
      );

      final streamedRes = await req.send();
      final res = await http.Response.fromStream(streamedRes);

      debugPrint('[API] POST $uri (${res.statusCode}): ${res.body}');

      if (res.statusCode == 200 || res.statusCode == 201) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final data = decoded['data'];
          if (data is Map<String, dynamic>) {
            return UploadItemModel.fromJson(data);
          }
          if (data is String && data.isNotEmpty) {
            return UploadItemModel(
              id: 0,
              filePath: data,
              folder: '',
              fileName: filename ?? file.path.split(RegExp(r'[/\\]')).last,
              fileType: '',
              fileSize: await file.length(),
              createdAt: DateTime.now().toIso8601String(),
              url: data,
            );
          }
        }
        debugPrint(
          '[API] Upload succeeded but response data unexpected: ${res.body}',
        );
      } else {
        debugPrint('[API] Upload failed (${res.statusCode}): ${res.body}');
      }
    } catch (e) {
      debugPrint('[API] Upload File Error: $e');
    }
    return null;
  }

  /// Deletes an uploaded file by ID or path
  Future<bool> deleteUploadFile(int id, {String? filePath}) async {
    try {
      final uri = Uri.parse('$baseUrl/uploads/$id');
      debugPrint('[API] DELETE $uri');

      var res = await http.delete(uri, headers: _headers());
      debugPrint('[API] DELETE $uri (${res.statusCode}): ${res.body}');

      if (res.statusCode == 200 || res.statusCode == 204) return true;
      if (filePath != null && filePath.isNotEmpty) {
        final clean = filePath.replaceFirst(RegExp(r'^/+'), '');
        final fileUri = Uri.parse('$baseUrl/files/$clean');
        debugPrint('[API] DELETE $fileUri');

        res = await http.delete(fileUri, headers: _headers());
        debugPrint('[API] DELETE $fileUri (${res.statusCode}): ${res.body}');

        if (res.statusCode == 200 || res.statusCode == 204) return true;
      }
    } catch (e) {
      debugPrint('[API] Delete Upload File Error: $e');
    }
    return false;
  }
}
