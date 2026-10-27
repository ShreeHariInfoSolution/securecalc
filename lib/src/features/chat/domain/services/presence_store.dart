import 'dart:async';
import 'package:flutter/foundation.dart';
import 'server_api_service.dart';

class PresenceState {
  final int userId;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final String? lastSeenText;

  PresenceState({
    required this.userId,
    required this.isOnline,
    this.lastSeenAt,
    this.lastSeenText,
  });

  factory PresenceState.fromMap(Map<String, dynamic> map) {
    final rawUserId = map['user_id'] ?? map['userId'] ?? map['id'];
    final userId = rawUserId is int
        ? rawUserId
        : (int.tryParse(rawUserId?.toString() ?? '') ?? 0);

    final rawOnline = map['is_online'] ?? map['isOnline'] ?? map['online'] ?? map['status'];
    final isOnline = rawOnline == true ||
        rawOnline == 1 ||
        rawOnline == '1' ||
        rawOnline == 'true' ||
        rawOnline?.toString().toLowerCase() == 'online';

    final rawLastSeen = map['last_seen_at'] ?? map['lastSeenAt'] ?? map['updated_at'];
    DateTime? lastSeenAt;
    if (rawLastSeen is String && rawLastSeen.isNotEmpty) {
      lastSeenAt = DateTime.tryParse(rawLastSeen);
    } else if (rawLastSeen is DateTime) {
      lastSeenAt = rawLastSeen;
    }

    final lastSeenText = (map['last_seen_text'] ?? map['lastSeenText'])?.toString();

    return PresenceState(
      userId: userId,
      isOnline: isOnline,
      lastSeenAt: lastSeenAt,
      lastSeenText: lastSeenText,
    );
  }

  String formattedLastSeen() {
    if (isOnline) return 'online';
    return formatLastSeenTime(lastSeenAt, lastSeenText: lastSeenText);
  }
}

String formatLastSeenTime(DateTime? lastSeenAt, {String? lastSeenText}) {
  if (lastSeenText != null &&
      lastSeenText.trim().isNotEmpty &&
      lastSeenText.trim().toLowerCase() != 'online' &&
      lastSeenText.trim().toLowerCase() != 'offline') {
    return lastSeenText.trim();
  }

  if (lastSeenAt == null) return '';

  final now = DateTime.now();
  final localTime = lastSeenAt.toLocal();
  final diff = now.difference(localTime);

  if (diff.inSeconds < 60 && diff.inSeconds >= 0) {
    return 'last seen just now';
  }

  if (diff.inMinutes < 60 && diff.inMinutes >= 1) {
    final mins = diff.inMinutes;
    return 'last seen $mins ${mins == 1 ? 'min' : 'mins'} ago';
  }

  final sameDay = now.year == localTime.year &&
      now.month == localTime.month &&
      now.day == localTime.day;

  final hour12 = localTime.hour > 12
      ? localTime.hour - 12
      : (localTime.hour == 0 ? 12 : localTime.hour);
  final minStr = localTime.minute.toString().padLeft(2, '0');
  final period = localTime.hour >= 12 ? 'PM' : 'AM';
  final timeStr = '$hour12:$minStr $period';

  if (sameDay) {
    return 'last seen today at $timeStr';
  }

  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday = yesterday.year == localTime.year &&
      yesterday.month == localTime.month &&
      yesterday.day == localTime.day;

  if (isYesterday) {
    return 'last seen yesterday at $timeStr';
  }

  if (diff.inDays >= 1 && diff.inDays < 7) {
    const days = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final weekday = (localTime.weekday >= 1 && localTime.weekday <= 7) ? days[localTime.weekday] : '';
    return 'last seen $weekday at $timeStr';
  }

  final dayStr = localTime.day.toString().padLeft(2, '0');
  const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final monthStr = (localTime.month >= 1 && localTime.month <= 12) ? months[localTime.month] : '';
  if (now.year == localTime.year) {
    return 'last seen $dayStr $monthStr at $timeStr';
  }
  return 'last seen $dayStr $monthStr ${localTime.year} at $timeStr';
}

class PresenceStore {
  PresenceStore._();
  static final PresenceStore instance = PresenceStore._();

  final ValueNotifier<Map<int, PresenceState>> presenceNotifier =
      ValueNotifier<Map<int, PresenceState>>({});

  final Map<String, int> _chatIdToUserIdMap = {};

  Timer? _minuteTimer;

  void startTimer() {
    _minuteTimer?.cancel();
    _minuteTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      presenceNotifier.value = Map.from(presenceNotifier.value);
    });
  }

  void stopTimer() {
    _minuteTimer?.cancel();
    _minuteTimer = null;
  }

  void bindChatUser(String chatId, int userId) {
    if (chatId.isNotEmpty && userId > 0) {
      _chatIdToUserIdMap[chatId] = userId;
    }
  }

  int? getUserIdForChat(String chatId) {
    return _chatIdToUserIdMap[chatId];
  }

  void updatePresence(Map<String, dynamic> data) {
    final rawData = data['data'] is Map ? Map<String, dynamic>.from(data['data'] as Map) : data;
    final state = PresenceState.fromMap(rawData);
    if (state.userId <= 0) return;

    final myUserId = ServerApiService.instance.currentUserId;
    if (myUserId != null && myUserId > 0 && state.userId == myUserId) {
      // Do not store or update presence for my own user ID
      return;
    }

    final chatHeadId = (rawData['chat_head_id'] ??
            rawData['chat_id'] ??
            rawData['chatHeadId'] ??
            data['chat_head_id'] ??
            data['chat_id'])
        ?.toString();

    if (chatHeadId != null && chatHeadId.isNotEmpty && chatHeadId != '0') {
      bindChatUser(chatHeadId, state.userId);
    }

    final currentMap = Map<int, PresenceState>.from(presenceNotifier.value);
    final existing = currentMap[state.userId];

    DateTime? effectiveLastSeen = state.lastSeenAt;
    if (!state.isOnline) {
      if (effectiveLastSeen == null) {
        if (existing != null && !existing.isOnline && existing.lastSeenAt != null) {
          effectiveLastSeen = existing.lastSeenAt;
        } else {
          effectiveLastSeen = DateTime.now();
        }
      }
    }

    final updatedState = PresenceState(
      userId: state.userId,
      isOnline: state.isOnline,
      lastSeenAt: state.isOnline ? null : effectiveLastSeen,
      lastSeenText: state.lastSeenText ?? (state.isOnline ? 'online' : null),
    );

    currentMap[state.userId] = updatedState;
    presenceNotifier.value = currentMap;
  }

  PresenceState? getPresence(int? userId) {
    if (userId == null || userId <= 0) return null;
    return presenceNotifier.value[userId];
  }

  PresenceState? getPresenceForChat({
    int? peerUserId,
    required String chatId,
    bool isGroup = false,
  }) {
    if (isGroup) return null;

    final targetUserId = (peerUserId != null && peerUserId > 0)
        ? peerUserId
        : (_chatIdToUserIdMap[chatId] ?? int.tryParse(chatId));

    if (targetUserId != null && targetUserId > 0) {
      return presenceNotifier.value[targetUserId];
    }

    return null;
  }
}
