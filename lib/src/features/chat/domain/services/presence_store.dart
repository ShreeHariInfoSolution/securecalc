import 'dart:async';
import 'package:flutter/foundation.dart';

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

  /// Formats last seen text dynamically using device local time according to
  /// backend spec rules.
  String formattedLastSeen() {
    if (isOnline) return 'online';

    if (lastSeenAt == null) {
      return (lastSeenText != null && lastSeenText!.trim().isNotEmpty)
          ? lastSeenText!
          : 'offline';
    }

    final now = DateTime.now();
    final localTime = lastSeenAt!.toLocal();
    final diff = now.difference(localTime);

    if (diff.inSeconds < 60 && diff.inSeconds >= 0) {
      return 'last seen just now';
    }

    final sameDay = now.year == localTime.year &&
        now.month == localTime.month &&
        now.day == localTime.day;

    final timeStr = _format12HourTime(localTime);

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

    if (diff.inDays >= 2 && diff.inDays < 7) {
      final weekday = _getWeekdayName(localTime.weekday);
      return 'last seen $weekday at $timeStr';
    }

    final dayStr = localTime.day.toString().padLeft(2, '0');
    final monthStr = _getMonthShort(localTime.month);
    return 'last seen $dayStr $monthStr ${localTime.year}';
  }

  static String _format12HourTime(DateTime dt) {
    final hour12 = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minStr = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minStr $period';
  }

  static String _getWeekdayName(int weekday) {
    const days = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return (weekday >= 1 && weekday <= 7) ? days[weekday] : '';
  }

  static String _getMonthShort(int month) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return (month >= 1 && month <= 12) ? months[month] : '';
  }
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
    _minuteTimer = Timer.periodic(const Duration(seconds: 30), (_) {
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

  void updatePresence(Map<String, dynamic> data) {
    final state = PresenceState.fromMap(data);
    if (state.userId <= 0) return;

    final currentMap = Map<int, PresenceState>.from(presenceNotifier.value);
    currentMap[state.userId] = state;
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

    int? targetUserId = peerUserId;
    targetUserId ??= int.tryParse(chatId);
    targetUserId ??= _chatIdToUserIdMap[chatId];

    if (targetUserId != null && targetUserId > 0) {
      return presenceNotifier.value[targetUserId];
    }
    return null;
  }
}
