class LocationShareModel {
  final int id;
  final int chatHeadId;
  final int? messageId;
  final int? userId;
  final bool isLive;
  final String status; // static | active | ended
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? heading;
  final double? speed;
  final int? durationMinutes;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final DateTime? lastUpdateAt;
  final DateTime? endedAt;
  final int? remainingSeconds;
  final String? userName;
  final String? userAvatar;

  const LocationShareModel({
    required this.id,
    required this.chatHeadId,
    this.messageId,
    this.userId,
    required this.isLive,
    required this.status,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.heading,
    this.speed,
    this.durationMinutes,
    this.startedAt,
    this.expiresAt,
    this.lastUpdateAt,
    this.endedAt,
    this.remainingSeconds,
    this.userName,
    this.userAvatar,
  });

  bool get isActive {
    if (!isLive || status != 'active' || endedAt != null) return false;
    if (expiresAt != null) return expiresAt!.isAfter(DateTime.now());
    return remainingSeconds == null || remainingSeconds! > 0;
  }

  factory LocationShareModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v).toLocal();
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    double parseDouble(dynamic v, [double defaultValue = 0.0]) {
      if (v == null) return defaultValue;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? defaultValue;
    }

    int parseInt(dynamic v, [int defaultValue = 0]) {
      if (v == null) return defaultValue;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? defaultValue;
    }

    return LocationShareModel(
      id: parseInt(json['id'] ?? json['location_id']),
      chatHeadId: parseInt(json['chat_head_id'] ?? json['chatHeadId']),
      messageId: json['message_id'] != null ? parseInt(json['message_id']) : null,
      userId: json['user_id'] != null ? parseInt(json['user_id']) : null,
      isLive: json['is_live'] == true || json['isLive'] == true,
      status: json['status']?.toString() ?? 'static',
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      accuracy: json['accuracy'] != null ? parseDouble(json['accuracy']) : null,
      heading: json['heading'] != null ? parseDouble(json['heading']) : null,
      speed: json['speed'] != null ? parseDouble(json['speed']) : null,
      durationMinutes: json['duration_minutes'] != null ? parseInt(json['duration_minutes']) : null,
      startedAt: parseDate(json['started_at'] ?? json['startedAt']),
      expiresAt: parseDate(json['expires_at'] ?? json['expiresAt']),
      lastUpdateAt: parseDate(json['last_update_at'] ?? json['lastUpdateAt']),
      endedAt: parseDate(json['ended_at'] ?? json['endedAt']),
      remainingSeconds: json['remaining_seconds'] != null ? parseInt(json['remaining_seconds']) : null,
      userName: (json['user_name'] ?? json['name'])?.toString(),
      userAvatar: (json['avatar'] ?? json['user_avatar'] ?? json['profile_image'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_head_id': chatHeadId,
      'message_id': messageId,
      'user_id': userId,
      'is_live': isLive,
      'status': status,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'heading': heading,
      'speed': speed,
      'duration_minutes': durationMinutes,
      'started_at': startedAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'last_update_at': lastUpdateAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'remaining_seconds': remainingSeconds,
      'user_name': userName,
      'user_avatar': userAvatar,
    };
  }

  /// Apply a server location object, but keep identity fields the server doesn't send.
  LocationShareModel mergeJson(Map<String, dynamic> raw) {
    if (raw['latitude'] == null || raw['longitude'] == null) return this;
    final f = LocationShareModel.fromJson(raw);
    return f.copyWith(
      userName: f.userName ?? userName,
      userAvatar: f.userAvatar ?? userAvatar,
      messageId: f.messageId ?? messageId,
    );
  }

  LocationShareModel copyWith({
    int? id,
    int? chatHeadId,
    int? messageId,
    int? userId,
    bool? isLive,
    String? status,
    double? latitude,
    double? longitude,
    double? accuracy,
    double? heading,
    double? speed,
    int? durationMinutes,
    DateTime? startedAt,
    DateTime? expiresAt,
    DateTime? lastUpdateAt,
    DateTime? endedAt,
    int? remainingSeconds,
    String? userName,
    String? userAvatar,
  }) {
    return LocationShareModel(
      id: id ?? this.id,
      chatHeadId: chatHeadId ?? this.chatHeadId,
      messageId: messageId ?? this.messageId,
      userId: userId ?? this.userId,
      isLive: isLive ?? this.isLive,
      status: status ?? this.status,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastUpdateAt: lastUpdateAt ?? this.lastUpdateAt,
      endedAt: endedAt ?? this.endedAt,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
    );
  }
}
